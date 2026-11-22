import UIKit
import XCTest
@testable import Typr

@MainActor
final class DictationLearningKeyboardTests: XCTestCase {
    private var results: [DictationEditResult] = []

    private func keyboard(_ field: FixtureTextTarget) -> TyprFullKeyboardView {
        let view = TyprFullKeyboardView(model: KeyboardViewModel(), target: field,
            autocorrect: TyprAutocorrectEngine(spatialDecoder: nil))
        view.suggestionBarOverride = true
        view.orientationOverride = .portrait
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        view.dictationEdits.onResult = { [unowned self] in self.results.append($0) }
        return view
    }

    private func dictate(_ text: String, into field: FixtureTextTarget, view: TyprFullKeyboardView, learns: Bool = true) {
        let before = field.documentContextBeforeInput ?? "", after = field.documentContextAfterInput ?? ""
        field.insertText(text)
        view.didInsertDictation(text, before: before, after: after, learns: learns)
        view.layoutIfNeeded()
    }

    private func undoChip(_ view: UIView) -> UIButton? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let button = view as? UIButton, button.configuration?.title == "Undo dictation" { return button }
        return view.subviews.lazy.compactMap(undoChip).first
    }

    private func replaceWal(in field: FixtureTextTarget, view: TyprFullKeyboardView) {
        field.adjustTextPosition(byCharacterOffset: -" getroffen.".count)
        view.selectionDidChange()
        for _ in 0..<3 { view.engine.deleteBackward() }
        field.insertText("Wahl")
        view.textDidChange()
    }

    func testAWordReplacedWithTheKeysIsReportedAsAFix() throws {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = keyboard(field)
        dictate(" Ich habe die Wal getroffen.", into: field, view: view)
        replaceWal(in: field, view: view)
        XCTAssertEqual(field.text, "Hallo Jörg. Ich habe die Wahl getroffen.")
        view.finishDictationEdits()
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.outcome, .edited)
        XCTAssertEqual(result.pairs, [DictationEditPair(inserted: "Wal", meant: "Wahl", caseIsKnown: true)])
    }

    func testNothingIsFollowedWhileLearningIsOff() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = keyboard(field)
        dictate(" Ich habe die Wal getroffen.", into: field, view: view, learns: false)
        replaceWal(in: field, view: view)
        view.finishDictationEdits()
        XCTAssertTrue(results.isEmpty)
    }

    func testUndoDictationIsUndoneAndNeverPairedWithTheNextDictation() throws {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = keyboard(field)
        dictate(" Ich habe die Wal getroffen.", into: field, view: view)
        try XCTUnwrap(undoChip(view)).sendActions(for: .touchUpInside)
        XCTAssertEqual(field.text, "Hallo Jörg.")
        view.textDidChange()
        dictate(" Ich habe die Wahl getroffen.", into: field, view: view)
        view.finishDictationEdits()
        XCTAssertEqual(results.map(\.outcome), [.undone, .kept])
        XCTAssertTrue(results.allSatisfy { $0.pairs.isEmpty })
    }
}

@MainActor
private final class LearningAudio: AudioManaging {
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?
    func requestPermission() async -> Bool { true }
    func startKeepalive(microphone: MicrophoneChoice) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }
    func beginCapture(at url: URL, maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ActiveAudioCapture {
        LearningCapture(url: url)
    }
}

@MainActor
private final class LearningCapture: ActiveAudioCapture {
    let url: URL
    var isRecording = true
    var currentTime: TimeInterval { 1.5 }
    init(url: URL) {
        self.url = url
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    func normalizedPowerLevel() -> Float { 0.5 }
    func stop() { isRecording = false }
}

private actor LearningASR: LocalTranscribing {
    nonisolated let displayName = "Test ASR"
    let languageName = "German"
    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {}
    func transcribe(_ url: URL) async throws -> String { "Ich habe die Wal getroffen" }
}

@MainActor
final class DictationLearningPipelineTests: XCTestCase {
    /// Two edits of "Wal" to "Wahl" make the next dictation write "Wahl", only with the
    /// experiment on.
    func testLearnedFixIsAppliedOnTheNextDictation() async throws {
        for switchOn in [true, false] {
            let suite = "dictation.learning.pipeline.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = TyprSettings(defaults: defaults)
            settings.dictationLanguage = .german
            settings[experiment: .learnFromEdits] = switchOn
            let store = DictationLearningStore(defaults: defaults)
            for _ in 0..<2 {
                store.record(DictationEditResult(outcome: .edited,
                    pairs: [DictationEditPair(inserted: "Wal", meant: "Wahl", caseIsKnown: true)]))
            }
            let asr = LearningASR()
            let controller = DictationController(audio: LearningAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
                transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false,
                customVocabularySettings: CustomVocabularySettings(defaults: defaults), dictationLearning: store,
                languageSettings: settings)
            controller.prepareModel()
            try await waitForState("model ready") { controller.phase == .ready }
            controller.startRecording(keyboardJobID: "learn-\(switchOn)", styleOverride: .polished, copyToPasteboard: false)
            try await waitForState("recording") { controller.phase == .recording }
            controller.finishRecording()
            try await waitForState("delivered") { controller.isIdleForTest }
            XCTAssertEqual(controller.transcript,
                           switchOn ? "Ich habe die Wahl getroffen." : "Ich habe die Wal getroffen.", "\(switchOn)")
            controller.cancelCurrentJob()
            await mainActorBarrier()
        }
    }
}
