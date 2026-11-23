import Foundation
import XCTest
@testable import Typr

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
        provider: (any SpeechEngineProviding)? = nil,
        multilingualDownload: ParakeetUltraDownload? = nil
    ) -> DictationController {
        let settings = TyprSettings(defaults: defaults)
        let controller = DictationController(
            audio: PrepAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
            transcriber: UnpreparedTranscriber(), transcriberFactory: factory, autoPrepareOnInit: false,
            languageSettings: settings, engineProvider: provider, multilingualDownload: multilingualDownload)
        controller.preparationLimits = (firstReport: .milliseconds(300), stall: .milliseconds(300))
        return controller
    }

    private final class Queue: @unchecked Sendable {
        private var items: [any LocalTranscribing]
        private(set) var made = 0
        init(_ items: [any LocalTranscribing]) { self.items = items }
        func next() -> any LocalTranscribing {
            made += 1
            return items.count > 1 ? items.removeFirst() : items[0]
        }
    }


    func testAPreparationThatNeverReportsEndsAndTryAgainDoesNotWaitForIt() async throws {
        let hung = PrepTranscriber(.gated)
        let ready = PrepTranscriber(.ready)
        let queue = Queue([hung, ready])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ended") { controller.phase == .failed("The speech model isn't ready. Try again.") }
        XCTAssertFalse(controller.isModelReady)

        controller.prepareModel()
        try await waitForState("ready after Try again") { controller.phase == .ready }
        let hungFinished = await hung.finished
        XCTAssertFalse(hungFinished, "ready while the dropped preparation still runs")
        XCTAssertTrue(controller.isModelReady)
        XCTAssertEqual(queue.made, 2)
        await hung.release()
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

    func testDeletionWaitsForALoadTheTimeoutDropped() async throws {
        let dropped = PrepTranscriber(.gated, name: "Parakeet V2")
        let provider = PrepProvider(PrepTranscriber(.ready))
        let controller = controller(factory: { dropped }, provider: provider)
        controller.prepareModel()
        try await waitForState("ended") { controller.phase.isFailure }
        let deletion = Task { await controller.deleteModel(.parakeetV2) }
        try await waitForState("deletion waits") { controller.deletionWaitsForTesting == 1 }
        XCTAssertTrue(provider.deleted.isEmpty, "the dropped load still reads its files")
        await dropped.release()
        _ = await deletion.value
        XCTAssertEqual(provider.deleted, [.parakeetV2])
    }

    func testALateDroppedLoadDoesNotEndTheTrackingOfTheNewerOne() async throws {
        let dropped = PrepTranscriber(.gated, name: "Parakeet V2")
        let newer = PrepTranscriber(.gated, name: "Parakeet V2")
        let queue = Queue([dropped, newer])
        let provider = PrepProvider(PrepTranscriber(.ready))
        let controller = controller(factory: { queue.next() }, provider: provider)
        controller.prepareModel()
        try await waitForState("ended") { controller.phase.isFailure }

        controller.preparationLimits = (firstReport: .seconds(60), stall: .seconds(60))
        controller.prepareModel()
        try await waitForState("newer load running") { await newer.entered }

        let deletion = Task { await controller.deleteModel(.parakeetV2) }
        try await waitForState("deletion waits") { controller.deletionWaitsForTesting == 1 }
        await dropped.release()
        try await waitForState("deletion woke for the dropped load and waits again") {
            controller.deletionWaitsForTesting == 2
        }
        XCTAssertTrue(provider.deleted.isEmpty, "the newer load still reads its files")
        await newer.release()
        _ = await deletion.value
        XCTAssertEqual(provider.deleted, [.parakeetV2])
    }

    func testAChosenDownloadedEngineKeepsTyprsBackgroundPreparationInstead() async throws {
        let provider = PrepProvider(PrepTranscriber(.silentFor(.milliseconds(900)), name: "Orukeet"))
        let controller = controller(provider: provider)
        XCTAssertEqual(controller.selectEngine(.orukeet), .selected)
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(controller.currentEngine, .orukeet)
    }


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

    // MARK: - Experimental › Hex experiments › Multilingual model (Parakeet)

    /// The App Group switch the controller reads, cleared after each test.
    private func clearMultilingualSwitch() {
        let group = UserDefaults(suiteName: KeyboardBridge.appGroup)
        group?.removeObject(forKey: MultilingualParakeetSettings.enabledKey)
        group?.removeObject(forKey: MultilingualParakeetSettings.modelReadyKey)
        ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel).forget()
    }

    func testTurningTheMultilingualModelOffDeletesItOnlyOnceItsLoadReturned() async throws {
        defer {
            ParakeetUltraModel.remove()
            clearMultilingualSwitch()
        }
        let controller = controller(factory: { PrepTranscriber(.ready) })
        let folder = ParakeetUltraModel.directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller.multilingualLoads.insert(99)

        controller.turnOffMultilingualParakeet()
        try await waitForState("deletion waits") {
            controller.deletionWaitsForTesting >= 1 && controller.phase == .ready
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "the load still reads its files")

        controller.multilingualLoads.remove(99)
        try await waitForState("deleted") { !FileManager.default.fileExists(atPath: folder.path) }
    }

    private func readyParakeetV2(
        download: ParakeetUltraDownload? = nil
    ) -> (DictationController, ParakeetTranscriber) {
        let controller = controller(multilingualDownload: download)
        let working = ParakeetTranscriber()
        controller.setDictationLanguage(.english)
        controller.transcriber = working
        controller.currentEngine = .parakeetV2
        controller.engineName = working.displayName
        controller.isModelReady = true
        controller.phase = .ready
        return (controller, working)
    }

    func testLowMemoryKeepsTheWorkingParakeetV2() async throws {
        defer { clearMultilingualSwitch() }
        let (controller, working) = readyParakeetV2()
        MultilingualParakeetSettings().isEnabled = true

        controller.syncMultilingualParakeet(availableMemory: 900 << 20, downloaded: true)

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)
        XCTAssertEqual(controller.multilingualDownload.state, .failed(ParakeetUltraTranscriber.notEnoughMemoryMessage))
        XCTAssertTrue(controller.multilingualLoads.isEmpty)
    }

    func testAMultilingualModelThatFailsToLoadKeepsTheEngineThatWorked() async throws {
        defer { clearMultilingualSwitch() }
        let (controller, working) = readyParakeetV2()
        MultilingualParakeetSettings().isEnabled = true

        controller.loadMultilingualParakeetBeside(language: "en-US") { _ in
            PrepTranscriber(.fails(PrepError()), name: ParakeetUltraTranscriber.name)
        }
        await controller.preparationTask?.value

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.currentEngine, .parakeetV2)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)
        XCTAssertEqual(controller.multilingualDownload.state, .failed("No model here."))
        XCTAssertTrue(controller.multilingualLoads.isEmpty)
    }

    func testOptOutDuringTranscriptionDoesNotRestoreUltraIfTheFallbackFails() async throws {
        defer { clearMultilingualSwitch() }
        let controller = controller(factory: { PrepTranscriber(.fails(PrepError()), name: "Apple Speech") })
        let settings = MultilingualParakeetSettings()
        settings.isEnabled = true
        settings.isModelReady = true
        controller.transcriber = ParakeetUltraTranscriber(language: "en-US")
        controller.engineName = ParakeetUltraTranscriber.name
        controller.isModelReady = true
        controller.phase = .transcribing

        controller.turnOffMultilingualParakeet()
        XCTAssertTrue(controller.pendingAppleLanguageChange)
        XCTAssertFalse(settings.isModelReady)
        controller.phase = .ready
        controller.preparePendingAppleLanguageIfIdle()
        await controller.preparationTask?.value

        XCTAssertEqual(controller.phase, .failed("No model here."))
        XCTAssertFalse(controller.isModelReady)
        XCTAssertFalse(controller.transcriber is ParakeetUltraTranscriber)
        XCTAssertFalse(settings.isModelReady)
    }

    func testBesideLoadDiscardsUltraWhenLanguageBecomesIneligible() async throws {
        let languageSettings = LanguageSettings()
        let previousLanguage = languageSettings.dictationLanguage
        defer {
            clearMultilingualSwitch()
            languageSettings.dictationLanguage = previousLanguage
        }
        let (controller, working) = readyParakeetV2()
        let candidate = PrepTranscriber(.gated, name: ParakeetUltraTranscriber.name)
        languageSettings.dictationLanguage = "ja-JP"
        let settings = MultilingualParakeetSettings()
        settings.isEnabled = true

        controller.loadMultilingualParakeetBeside(language: "en-US") { _ in candidate }
        try await waitForState("Ultra load entered") { await candidate.entered }
        controller.setDictationLanguage(.automatic)
        await candidate.release()
        await controller.preparationTask?.value

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)
        XCTAssertFalse(settings.isModelReady)
        XCTAssertEqual(controller.multilingualDownload.state, .idle)
    }

    func testLanguagePickerPausesAndResumesUltraDownloadWithoutReloadingV2() async throws {
        let languageSettings = LanguageSettings()
        let previousLanguage = languageSettings.dictationLanguage
        let writer = GatedMultilingualDownload()
        let download = ParakeetUltraDownload(fetch: { _ in try await writer.fetch() })
        defer {
            download.cancel()
            writer.releaseFirstAttempt()
            clearMultilingualSwitch()
            languageSettings.dictationLanguage = previousLanguage
        }

        let (controller, working) = readyParakeetV2(download: download)
        languageSettings.dictationLanguage = "ja-JP"
        MultilingualParakeetSettings().isEnabled = true
        controller.multilingualParakeetChanged()
        try await waitForState("first writer started") { writer.attempts == 1 }

        controller.setDictationLanguage(.automatic)
        XCTAssertNil(controller.multilingualLanguage())
        XCTAssertEqual(download.state, .idle)
        XCTAssertFalse(download.isRunning)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)

        controller.setDictationLanguage(.english)
        XCTAssertEqual(controller.multilingualLanguage(), "en-US")
        XCTAssertTrue(download.isRunning)
        await mainActorBarrier()
        XCTAssertEqual(writer.attempts, 1, "the replacement waits for cancellation to drain")
        writer.releaseFirstAttempt()

        try await waitForState("replacement writer started") { writer.attempts == 2 }
        XCTAssertTrue(writer.firstAttemptWasCancelled)
        XCTAssertNil(controller.preparationTask)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)
        XCTAssertFalse(MultilingualParakeetSettings().isModelReady)
        await download.cancel()?.value
    }

    func testPinningTheReadyEngineCancelsAnActiveUltraDownloadAndSuppressesRetries() async throws {
        defer { clearMultilingualSwitch() }
        let download = ParakeetUltraDownload(fetch: { _ in try await Task.sleep(for: .seconds(60)) })
        let (controller, working) = readyParakeetV2(download: download)
        MultilingualParakeetSettings().isEnabled = true
        download.start()

        XCTAssertEqual(controller.selectEngine(.parakeetV2), .selected)
        XCTAssertFalse(download.isRunning)
        controller.noteSceneDidBecomeActive()
        controller.retryMultilingualParakeet()

        XCTAssertEqual(download.state, .idle)
        XCTAssertFalse(download.isRunning)
        XCTAssertTrue((controller.transcriber as? ParakeetTranscriber) === working)
        await download.cancel()?.value
    }

    func testTurningMultilingualParakeetOnOrOffPreparesAgainOnceIdle() async throws {
        defer { clearMultilingualSwitch() }
        let queue = Queue([PrepTranscriber(.ready)])
        let controller = controller(factory: { queue.next() })
        controller.prepareModel()
        try await waitForState("ready") { controller.phase == .ready }
        XCTAssertEqual(queue.made, 1)

        // Turned off while the usual engine dictates: nothing to prepare again.
        controller.turnOffMultilingualParakeet()
        XCTAssertEqual(controller.phase, .ready, "no preparation started")

        // Turned off while Parakeet Ultra dictated: Typr prepares the engine it picks without it.
        controller.engineName = ParakeetUltraTranscriber.name
        controller.multilingualParakeetChanged()
        try await waitForState("prepared again") { queue.made == 2 && controller.phase == .ready }
    }

    func testTheMultilingualModelNeverReplacesAChosenEngine() async throws {
        defer { clearMultilingualSwitch() }
        let provider = PrepProvider(PrepTranscriber(.ready, name: "Orukeet"))
        let controller = controller(provider: provider)
        XCTAssertEqual(controller.selectEngine(.orukeet), .selected)
        try await waitForState("ready") { controller.phase == .ready }

        MultilingualParakeetSettings().isEnabled = true
        controller.multilingualParakeetChanged()
        XCTAssertEqual(controller.multilingualDownload.state, .idle, "no download for a chosen engine")
        XCTAssertFalse(controller.multilingualDownload.isRunning)
        XCTAssertEqual(controller.currentEngine, .orukeet)
        XCTAssertEqual(provider.created, 1)
    }

    func testSilenceFromTheMultilingualModelKeepsItLoaded() {
        XCTAssertTrue(DictationController.transcriptionFailureKeepsModel(ParakeetUltraTranscriber.TranscriberError.emptyTranscript))
        XCTAssertFalse(DictationController.transcriptionFailureKeepsModel(ParakeetUltraTranscriber.TranscriberError.notPrepared))
        XCTAssertEqual(DictationController.switchNotice(for: ParakeetUltraTranscriber.TranscriberError.notEnoughMemory),
                       ParakeetUltraTranscriber.notEnoughMemoryMessage)
    }
}

@MainActor
private final class GatedMultilingualDownload {
    private(set) var attempts = 0
    private(set) var firstAttemptWasCancelled = false
    private var firstAttempt: CheckedContinuation<Void, Never>?

    func fetch() async throws {
        attempts += 1
        if attempts == 1 {
            await withCheckedContinuation { firstAttempt = $0 }
            firstAttemptWasCancelled = Task.isCancelled
            try Task.checkCancellation()
        }
        try await Task.sleep(for: .seconds(60))
    }

    func releaseFirstAttempt() {
        firstAttempt?.resume()
        firstAttempt = nil
    }
}

private struct PrepError: LocalizedError {
    var errorDescription: String? { "No model here." }
}

private actor PrepTranscriber: LocalTranscribing {
    enum Behavior: Sendable {
        case ready
        case hangs
        case silentFor(Duration)
        case reportsThenHangs
        case reportsFor(Duration)
        case gated
        case fails(any Error & Sendable)
    }

    private var gate: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private(set) var finished = false

    func release() {
        gate?.resume()
        gate = nil
    }

    nonisolated let displayName: String
    let languageName = "English"
    private let behavior: Behavior

    init(_ behavior: Behavior, name: String = "Controlled Speech") {
        self.behavior = behavior
        displayName = name
    }

    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {
        entered = true
        defer { finished = true }
        switch behavior {
        case .ready:
            progressHandler(ModelPreparationProgress(fractionCompleted: 1, detail: "Ready"))
        case .hangs:
            try await Task.sleep(for: .seconds(60))
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
        case .gated:
            await withCheckedContinuation { gate = $0 }
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

    private(set) var deleted: [SpeechEngineChoice] = []

    func isInstalled(_ engine: SpeechEngineChoice) -> Bool { true }

    func availability(of engine: SpeechEngineChoice, language: DictationLanguage) async -> SpeechEngineAvailability {
        .installed
    }

    func deleteModel(_ engine: SpeechEngineChoice) throws {
        deleted.append(engine)
    }
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
