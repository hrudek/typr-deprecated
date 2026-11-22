import Translation
import XCTest
@testable import Typr

private struct StandInError: Error {}

@MainActor
private final class StandInTranslation {
    var status: LanguageAvailability.Status = .installed
    var replies: [Result<String, StandInError>] = []
    var suspends = false
    private(set) var calls: [(text: String, source: String, target: String)] = []
    private(set) var cancelled = false
    private var gate: CheckedContinuation<String, any Error>?
    private var timers: [CheckedContinuation<Void, any Error>] = []

    var translator: DictationTranslator {
        DictationTranslator(
            status: { _, _ in self.status },
            translate: { text, source, target in try await self.translate(text, source, target) },
            sleep: { _ in try await self.sleep() }
        )
    }

    var isWaiting: Bool { gate != nil }
    var hasDeadline: Bool { !timers.isEmpty }

    func expireDeadline() {
        let pending = timers
        timers = []
        for timer in pending { timer.resume() }
    }

    private func sleep() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { timers.append($0) }
        } onCancel: {
            Task { @MainActor in
                let pending = self.timers
                self.timers = []
                for timer in pending { timer.resume(throwing: CancellationError()) }
            }
        }
    }

    private func translate(_ text: String, _ source: Locale.Language, _ target: Locale.Language) async throws -> String {
        calls.append((text, source.minimalIdentifier, target.minimalIdentifier))
        if suspends {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { gate = $0 }
            } onCancel: {
                Task { @MainActor in
                    self.cancelled = true
                    self.gate?.resume(throwing: CancellationError())
                    self.gate = nil
                }
            }
        }
        return try replies.removeFirst().get()
    }
}

@MainActor
final class DictationTranslationSettingsTests: XCTestCase {
    func testOffByDefaultWithEnglishTarget() {
        let suite = "translation.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        XCTAssertFalse(settings.translateDictation)
        XCTAssertEqual(settings.translationTarget, .english)
        XCTAssertNil(settings.translationFailure)
    }

    func testChoicesPersistAndUnknownTargetFallsBackToEnglish() {
        let suite = "translation.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        settings.translateDictation = true
        settings.translationTarget = .german
        settings.translationFailure = .notDownloaded
        let reread = TyprSettings(defaults: defaults)
        XCTAssertTrue(reread.translateDictation)
        XCTAssertEqual(reread.translationTarget, .german)
        XCTAssertEqual(reread.translationFailure, .notDownloaded)
        reread.translationFailure = nil
        XCTAssertNil(TyprSettings(defaults: defaults).translationFailure)
        defaults.set("automatic", forKey: "typr.translationTarget")
        XCTAssertEqual(TyprSettings(defaults: defaults).translationTarget, .english)
    }
}

@MainActor
final class DictationTranslatorTests: XCTestCase {
    func testTranslatesGermanIntoEnglish() async {
        let apple = StandInTranslation()
        apple.replies = [.success(" See you tomorrow at ten. ")]
        let outcome = await apple.translator.translate("Wir sehen uns morgen um zehn.", from: .german, to: .english)
        XCTAssertEqual(outcome, .translated("See you tomorrow at ten."))
        XCTAssertEqual(apple.calls.map(\.source), ["de"])
        XCTAssertEqual(apple.calls.map(\.target), ["en"])
    }

    func testTranslatesEnglishIntoGerman() async {
        let apple = StandInTranslation()
        apple.replies = [.success("Bis morgen.")]
        let outcome = await apple.translator.translate("See you tomorrow.", from: .english, to: .german)
        XCTAssertEqual(outcome, .translated("Bis morgen."))
        XCTAssertEqual(apple.calls.map(\.source), ["en"])
    }

    func testAutomaticLanguageIsReadFromTheText() async {
        let apple = StandInTranslation()
        apple.replies = [.success("I'll call you back later today.")]
        let outcome = await apple.translator.translate("Ich rufe dich heute später noch einmal zurück.", from: .automatic, to: .english)
        XCTAssertEqual(outcome, .translated("I'll call you back later today."))
        XCTAssertEqual(apple.calls.map(\.source), ["de"])
    }

    func testSameLanguageAndEmptyTextAreSkipped() async {
        let apple = StandInTranslation()
        let same = await apple.translator.translate("Bis morgen.", from: .german, to: .german)
        let empty = await apple.translator.translate("  ", from: .german, to: .english)
        XCTAssertEqual(same, .skipped)
        XCTAssertEqual(empty, .skipped)
        XCTAssertTrue(apple.calls.isEmpty)
    }

    func testMissingPackFailsWithoutTranslating() async {
        let apple = StandInTranslation()
        apple.status = .supported
        let outcome = await apple.translator.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome, .failed(.notDownloaded))
        XCTAssertTrue(apple.calls.isEmpty)
    }

    func testUnsupportedPairFails() async {
        let apple = StandInTranslation()
        apple.status = .unsupported
        let outcome = await apple.translator.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome, .failed(.failed))
        XCTAssertTrue(apple.calls.isEmpty)
    }

    func testAFailedTranslationIsRetriedOnce() async {
        let apple = StandInTranslation()
        apple.replies = [.failure(StandInError()), .success("See you tomorrow.")]
        let outcome = await apple.translator.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome, .translated("See you tomorrow."))
        XCTAssertEqual(apple.calls.count, 2)
    }

    func testTwoFailuresGoInAsSpoken() async {
        let apple = StandInTranslation()
        apple.replies = [.failure(StandInError()), .success("  ")]
        let outcome = await apple.translator.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome, .failed(.failed))
        XCTAssertEqual(apple.calls.count, 2)
    }

    func testDeadlineEndsAWaitingTranslation() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let task = Task { await apple.translator.translate("Bis morgen.", from: .german, to: .english) }
        try await waitForState("translating") { apple.isWaiting && apple.hasDeadline }
        apple.expireDeadline()
        let outcome = await task.value
        XCTAssertEqual(outcome, .failed(.failed))
        try await waitForState("translation cancelled") { apple.cancelled }
        XCTAssertEqual(apple.calls.count, 1)
    }

    func testCancellationReturnsNothing() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let task = Task { await apple.translator.translate("Bis morgen.", from: .german, to: .english) }
        try await waitForState("translating") { apple.isWaiting }
        task.cancel()
        let outcome = await task.value
        XCTAssertNil(outcome)
        try await waitForState("translation cancelled") { apple.cancelled }
    }
}

@MainActor
private final class TranslationAudio: AudioManaging {
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?
    func requestPermission() async -> Bool { true }
    func startKeepalive(microphone: MicrophoneChoice) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }
    func beginCapture(at url: URL, maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ActiveAudioCapture {
        TranslationCapture(url: url)
    }
}

@MainActor
private final class TranslationCapture: ActiveAudioCapture {
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

private actor TranslationASR: LocalTranscribing {
    nonisolated let displayName = "Test ASR"
    let languageName = "German"
    let text: String
    init(_ text: String) { self.text = text }
    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {}
    func transcribe(_ url: URL) async throws -> String { text }
}

@MainActor
final class DictationTranslationPipelineTests: XCTestCase {
    private struct Fixture {
        let controller: DictationController
        let settings: TyprSettings
        let bridge: KeyboardBridge
        let model: CleanupTestSession
        let clock: CleanupTestSleeper
    }

    private func makeFixture(spoken: String, translate: Bool, apple: StandInTranslation, aiCleanup: Bool = false,
                             cleaned: String = "") async throws -> Fixture {
        let suite = "translation.pipeline.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let settings = TyprSettings(defaults: defaults)
        settings.dictationLanguage = .german
        settings.translateDictation = translate
        settings.translationTarget = .english
        let model = CleanupTestSession()
        model.result = cleaned
        let clock = CleanupTestSleeper()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model),
            background: CleanupTestBackground(), isEnabled: { aiCleanup }, sleep: clock.sleep)
        let asr = TranslationASR(spoken)
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = DictationController(audio: TranslationAudio(), keyboardBridge: bridge,
            transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false,
            customVocabularySettings: CustomVocabularySettings(defaults: defaults), cleanup: deps,
            languageSettings: settings, translator: apple.translator)
        controller.prepareModel()
        try await waitForState("model ready") { controller.phase == .ready }
        return Fixture(controller: controller, settings: settings, bridge: bridge, model: model, clock: clock)
    }

    private func dictate(_ f: Fixture, style: DictationStyle = .polished) async throws {
        f.controller.startRecording(keyboardJobID: UUID().uuidString, styleOverride: style, copyToPasteboard: false)
        try await waitForState("recording") { f.controller.phase == .recording }
        f.controller.finishRecording()
    }

    private func drain(_ f: Fixture) async throws {
        f.controller.cancelCurrentJob()
        f.clock.fire()
        try await waitForState("idle") { f.controller.isIdleForTest && f.model.cleansInFlight == 0 }
        await mainActorBarrier()
    }

    func testTranslationIsInsertedAndFormattedInEnglish() async throws {
        let apple = StandInTranslation()
        apple.replies = [.success("see you tomorrow at the office")]
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        f.settings.translationFailure = .failed
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(apple.calls.map(\.text), ["Wir sehen uns morgen im Büro"])
        XCTAssertEqual(f.controller.transcript, "See you tomorrow at the office.")
        XCTAssertEqual(f.bridge.snapshot().transcript, "See you tomorrow at the office.")
        XCTAssertNil(f.bridge.snapshot().resultNote)
        XCTAssertNil(f.controller.translationFailure)
        XCTAssertNil(f.settings.translationFailure)
        try await drain(f)
    }

    func testMissingPackPastesAsSpokenWithANote() async throws {
        let apple = StandInTranslation()
        apple.status = .supported
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(f.controller.transcript, "Wir sehen uns morgen im Büro.")
        let snapshot = f.bridge.snapshot()
        XCTAssertEqual(snapshot.transcript, "Wir sehen uns morgen im Büro.")
        XCTAssertEqual(snapshot.resultNote, TranslationFailure.notDownloaded.note)
        XCTAssertTrue(snapshot.resultNote?.contains("Pasted as spoken") == true)
        XCTAssertEqual(f.controller.translationFailure, .notDownloaded)
        XCTAssertEqual(f.settings.translationFailure, .notDownloaded)
        try await drain(f)
    }

    func testTimeoutPastesAsSpokenWithANote() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        try await dictate(f)
        try await waitForState("translating") { apple.isWaiting && apple.hasDeadline }
        apple.expireDeadline()
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(f.controller.transcript, "Wir sehen uns morgen im Büro.")
        XCTAssertEqual(f.bridge.snapshot().resultNote, "Couldn't translate, pasted as spoken")
        XCTAssertEqual(f.settings.translationFailure, .failed)
        try await drain(f)
    }

    func testCancellingDuringTranslationDeliversNothing() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        try await dictate(f)
        try await waitForState("translating") { apple.isWaiting }
        f.controller.cancelCurrentJob()
        try await waitForState("idle") { f.controller.isIdleForTest }
        try await waitForState("translation cancelled") { apple.cancelled }
        XCTAssertEqual(f.controller.transcript, "")
        XCTAssertNil(f.bridge.snapshot().transcript)
        XCTAssertNil(f.settings.translationFailure)
        try await drain(f)
    }

    func testTranslationRunsAfterAICleanupOnItsOutput() async throws {
        let apple = StandInTranslation()
        apple.replies = [.success("See you tomorrow at the office.")]
        let f = try await makeFixture(spoken: "wir sehen uns morgen im büro", translate: true, apple: apple,
                                      aiCleanup: true, cleaned: "Wir sehen uns morgen im Büro.")
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(f.model.prompts.count, 1)
        XCTAssertEqual(apple.calls.map(\.text), ["Wir sehen uns morgen im Büro."])
        XCTAssertEqual(f.controller.transcript, "See you tomorrow at the office.")
        try await drain(f)
    }

    func testOffLeavesThePipelineAsBefore() async throws {
        let apple = StandInTranslation()
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: false, apple: apple)
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertTrue(apple.calls.isEmpty)
        XCTAssertEqual(f.controller.transcript, "Wir sehen uns morgen im Büro.")
        XCTAssertNil(f.bridge.snapshot().resultNote)
        try await drain(f)
    }

    func testSettingIsFrozenWhenRecordingStarts() async throws {
        let apple = StandInTranslation()
        let f = try await makeFixture(spoken: "Bis morgen", translate: false, apple: apple)
        f.controller.startRecording(keyboardJobID: UUID().uuidString, styleOverride: .polished, copyToPasteboard: false)
        try await waitForState("recording") { f.controller.phase == .recording }
        f.settings.translateDictation = true
        f.controller.finishRecording()
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertTrue(apple.calls.isEmpty)
        XCTAssertEqual(f.controller.transcript, "Bis morgen.")
        try await drain(f)
    }
}
