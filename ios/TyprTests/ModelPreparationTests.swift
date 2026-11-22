import Foundation
import XCTest
@testable import Typr

/// Hex's model preparation (`DictationController+ModelPreparation`): a preparation that says
/// nothing new ends, Automatic moves on after a language or memory set-aside, and a failed
/// automatic guess keeps the engine that worked. A chosen engine never falls back.
@MainActor
final class ModelPreparationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "typr.tests.prep.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func controller(
        factory: (() async -> any LocalTranscribing)? = nil,
        provider: (any SpeechEngineProviding)? = nil
    ) -> DictationController {
        let settings = TyprSettings(defaults: defaults)
        let controller = DictationController(
            audio: PrepAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
            transcriber: UnpreparedTranscriber(), transcriberFactory: factory, autoPrepareOnInit: false,
            languageSettings: settings, engineProvider: provider)
        controller.preparationLimits = (firstReport: .milliseconds(300), stall: .milliseconds(300))
        return controller
    }

    /// Hands out transcribers in order, the last one again once the list runs out.
    private final class Queue: @unchecked Sendable {
        private var items: [any LocalTranscribing]
        private(set) var made = 0
        init(_ items: [any LocalTranscribing]) { self.items = items }
        func next() -> any LocalTranscribing {
            made += 1
            return items.count > 1 ? items.removeFirst() : items[0]
        }
    }

    // MARK: - Ending a preparation that says nothing new

    func testAPreparationThatNeverReportsEndsAndTryAgainDoesNotWaitForIt() async throws {
        // Like an XPC call that never returns: cancelling it doesn't end it.
        let hung = PrepTranscriber(.ignoresCancellation(.seconds(5)))
        let ready = PrepTranscriber(.ready)
        let queue = Queue([hung, ready])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ended") { controller.phase == .failed("The speech model isn't ready. Try again.") }
        XCTAssertFalse(controller.isModelReady)

        controller.prepareModel()
        try await waitForState("ready after Try again", timeout: .seconds(3)) { controller.phase == .ready }
        XCTAssertTrue(controller.isModelReady)
        XCTAssertEqual(queue.made, 2)
    }

    func testAPreparationThatStopsMovingEndsAfterTheStallLimit() async throws {
        let controller = controller(factory: { PrepTranscriber(.reportsThenHangs) })
        controller.preparationLimits = (firstReport: .seconds(60), stall: .milliseconds(300))
        controller.prepareModel()
        try await waitForState("ended") { controller.phase == .failed("The speech model isn't ready. Try again.") }
    }

    func testAPreparationThatKeepsMovingIsNotEnded() async throws {
        let controller = controller(factory: { PrepTranscriber(.reportsFor(.milliseconds(900))) })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }
    }

    func testAChosenDownloadedEngineKeepsTyprsBackgroundPreparationInstead() async throws {
        let provider = PrepProvider(PrepTranscriber(.silentFor(.milliseconds(900)), name: "Orukeet"))
        let controller = controller(provider: provider)
        XCTAssertEqual(controller.selectEngine(.orukeet), .selected)
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(controller.currentEngine, .orukeet)
    }

    // MARK: - Automatic moves on, a chosen engine never does

    func testAutomaticMovesOnFromALanguageThisIPhoneCantDictate() async throws {
        let russian = SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone, fallback: "en-US")
        let queue = Queue([PrepTranscriber(.fails(russian)), PrepTranscriber(.ready)])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(queue.made, 2, "prepared again with what Automatic picks now")
        XCTAssertEqual(controller.languageNotice, "Russian isn't available on this iPhone yet. Using English.")
    }

    func testParakeetWithoutRoomPreparesAnotherEngineInsteadOfLoading() async throws {
        let queue = Queue([PrepTranscriber(.fails(ParakeetTranscriber.TranscriberError.notEnoughMemory)), PrepTranscriber(.ready)])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(queue.made, 2)
        XCTAssertEqual(controller.languageNotice,
                       "Not enough memory for the speech model. Typr is using Apple's on-device speech recognition.")
    }

    func testAutomaticMovesOnAtMostTwice() async throws {
        let queue = Queue([PrepTranscriber(.fails(ParakeetTranscriber.TranscriberError.notEnoughMemory))])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("failed") { controller.phase.isFailure }
        XCTAssertEqual(queue.made, 3)
    }

    func testAChosenEngineThatFailsIsNeverReplaced() async throws {
        let provider = PrepProvider(PrepTranscriber(.fails(ParakeetTranscriber.TranscriberError.notEnoughMemory), name: "Parakeet V2"))
        let controller = controller(provider: provider)
        XCTAssertEqual(controller.selectEngine(.parakeetV2), .selected)
        try await waitForState("failed") { controller.phase.isFailure }
        XCTAssertEqual(provider.created, 1, "no other engine and no second try")
        XCTAssertEqual(controller.preferredEngine, .parakeetV2)
        XCTAssertNil(controller.languageNotice)
    }

    // MARK: - A failed guess keeps the engine that worked (Hex #2371)

    func testAFailedAutomaticGuessKeepsTheEngineThatWorked() async throws {
        let working = PrepTranscriber(.ready, name: "Apple Speech")
        let queue = Queue([working, PrepTranscriber(.fails(PrepError()))])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }

        controller.prepareModel()
        try await waitForState("second preparation ended") { queue.made == 2 && controller.phase != .preparingModel }
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertEqual(controller.currentEngine, .appleSpeech)
        XCTAssertEqual(controller.languageNotice, "No model here. Typr keeps using Apple Speech.")
    }

    func testAStalledAutomaticGuessKeepsTheEngineThatWorked() async throws {
        let queue = Queue([PrepTranscriber(.ready, name: "Apple Speech"), PrepTranscriber(.hangs)])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }
        controller.prepareModel()
        try await waitForState("kept") { queue.made == 2 && controller.phase == .ready }
        XCTAssertEqual(controller.currentEngine, .appleSpeech)
        XCTAssertEqual(controller.languageNotice, "The speech model isn't ready. Try again. Typr keeps using Apple Speech.")
    }

    // MARK: - A download cut off in the background

    func testADownloadCutOffInTheBackgroundIsTriedAgainOnReturn() async throws {
        let queue = Queue([PrepTranscriber(.fails(URLError(.networkConnectionLost))), PrepTranscriber(.ready)])
        let controller = controller(factory: { queue.next() })
        controller.noteSceneDidEnterBackground()
        controller.prepareModel()
        try await waitForState("failed") { controller.phase.isFailure }
        controller.noteSceneDidBecomeActive()
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(queue.made, 2)
    }

    func testOnlyDownloadInterruptionsAndSetAsidesAreRecognized() {
        XCTAssertTrue(DictationController.isDownloadInterruption(URLError(.timedOut)))
        XCTAssertTrue(DictationController.isDownloadInterruption(StallWatch.Stalled()))
        XCTAssertTrue(DictationController.isDownloadInterruption(ParakeetTranscriber.TranscriberError.downloadFailed))
        XCTAssertFalse(DictationController.isDownloadInterruption(PrepError()))
        XCTAssertNil(DictationController.switchNotice(for: PrepError()))
        XCTAssertNil(DictationController.switchNotice(for: SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone)),
                     "nothing to move on to")
        XCTAssertNil(DictationController.switchNotice(
            for: SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone, fallback: "en-US", automatic: false)),
            "a language picked by hand is not switched")
    }
}

private struct PrepError: LocalizedError {
    var errorDescription: String? { "No model here." }
}

private actor PrepTranscriber: LocalTranscribing {
    enum Behavior: Sendable {
        case ready
        case hangs
        case ignoresCancellation(Duration)
        case silentFor(Duration)
        case reportsThenHangs
        /// Reports something new every 100 ms for that long, then is ready.
        case reportsFor(Duration)
        case fails(any Error & Sendable)
    }

    nonisolated let displayName: String
    let languageName = "English"
    private let behavior: Behavior

    init(_ behavior: Behavior, name: String = "Controlled Speech") {
        self.behavior = behavior
        displayName = name
    }

    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {
        switch behavior {
        case .ready:
            progressHandler(ModelPreparationProgress(fractionCompleted: 1, detail: "Ready"))
        case .hangs:
            try await Task.sleep(for: .seconds(60))
        case .ignoresCancellation(let duration):
            let clock = ContinuousClock()
            let end = clock.now + duration
            while clock.now < end {
                try? await Task.sleep(for: .milliseconds(50))
            }
        case .silentFor(let duration):
            try await Task.sleep(for: duration)
        case .reportsThenHangs:
            progressHandler(ModelPreparationProgress(fractionCompleted: 0.1, detail: "Downloading"))
            try await Task.sleep(for: .seconds(60))
        case .reportsFor(let duration):
            let clock = ContinuousClock()
            let end = clock.now + duration
            var step = 0.0
            while clock.now < end {
                step += 0.01
                progressHandler(ModelPreparationProgress(fractionCompleted: step, detail: "Downloading"))
                try await Task.sleep(for: .milliseconds(100))
            }
        case .fails(let error):
            throw error
        }
    }

    func transcribe(_ audioURL: URL) async throws -> String { "" }
}

@MainActor
private final class PrepProvider: SpeechEngineProviding {
    private let transcriber: PrepTranscriber
    private(set) var created = 0

    init(_ transcriber: PrepTranscriber) {
        self.transcriber = transcriber
    }

    func automaticTranscriber(language: DictationLanguage) async -> any LocalTranscribing {
        XCTFail("a chosen engine never takes the automatic path")
        return transcriber
    }

    func transcriber(for engine: SpeechEngineChoice, language: DictationLanguage) async throws -> any LocalTranscribing {
        created += 1
        return transcriber
    }

    func isInstalled(_ engine: SpeechEngineChoice) -> Bool { true }

    func availability(of engine: SpeechEngineChoice, language: DictationLanguage) async -> SpeechEngineAvailability {
        .installed
    }

    func deleteModel(_ engine: SpeechEngineChoice) throws {}
}

private final class PrepAudio: AudioManaging {
    struct NoCapture: Error {}
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?

    func requestPermission() async -> Bool { true }
    func startKeepalive(microphone: MicrophoneChoice) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }

    func beginCapture(at url: URL, maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ActiveAudioCapture {
        throw NoCapture()
    }
}
