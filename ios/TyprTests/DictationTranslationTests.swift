import Translation
import XCTest
@testable import Typr

private struct StandInError: Error {}

@MainActor
private final class StandInTranslation {
    var status: LanguageAvailability.Status = .installed
    var replies: [Result<String, any Error>] = []
    var suspends = false
    private(set) var calls: [(text: String, source: String, target: String)] = []
    private(set) var cancelled = false
    private var gate: CheckedContinuation<String, any Error>?
    private var timers: [CheckedContinuation<Void, any Error>] = []

    var engine: TranslationEngine {
        TranslationEngine(
            status: { _, _ in self.status },
            translate: { text, source, target in try await self.translate(text, source, target) }
        )
    }

    var policy: TyprDictationTranslator {
        TyprDictationTranslator(engine: engine, sleep: { _ in try await self.sleep() })
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

private func isolatedDefaults(_ test: XCTestCase) -> UserDefaults {
    let suite = "translation.\(UUID().uuidString)"
    test.addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    return UserDefaults(suiteName: suite)!
}

private let chinese = Locale.Language(identifier: "zh-CN")

@MainActor
final class DictationTranslationSettingsTests: XCTestCase {
    func testOffByDefaultWithAnEnglishTarget() {
        let defaults = isolatedDefaults(self)
        defaults.set(true, forKey: "typr.translateDictation")
        let settings = DictationTranslationSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled, "Typr's old switch is not read")
        XCTAssertEqual(settings.targetLanguage, "en")
        XCTAssertNil(settings.lastFailure)
        XCTAssertNil(DictationTranslationPlan(settings: settings, typrPolicy: false))
    }

    func testChoicesAndTheLastFailurePersist() {
        let defaults = isolatedDefaults(self)
        let settings = DictationTranslationSettings(defaults: defaults)
        settings.isEnabled = true
        settings.targetLanguage = "de"
        let failure = TranslationFailure(.notDownloaded, source: Locale.Language(identifier: "en-US"),
                                         target: Locale.Language(identifier: "de"))
        settings.lastFailure = failure
        let reread = DictationTranslationSettings(defaults: defaults)
        XCTAssertTrue(reread.isEnabled)
        XCTAssertEqual(reread.targetLanguage, "de")
        XCTAssertEqual(reread.lastFailure, failure)
        XCTAssertEqual(failure.language, "de", "the language that isn't English is downloaded")
        XCTAssertEqual(TranslationFailure(.notDownloaded, source: Locale.Language(identifier: "de-DE"),
                                          target: Locale.Language(identifier: "en")).language, "de")
        reread.lastFailure = nil
        XCTAssertNil(DictationTranslationSettings(defaults: defaults).lastFailure)
    }

    func testThePlanKeepsTheTargetOrGermanOrEnglishUnderTheTyprPolicy() {
        let settings = DictationTranslationSettings(defaults: isolatedDefaults(self))
        settings.isEnabled = true
        settings.targetLanguage = "ja"
        XCTAssertEqual(DictationTranslationPlan(settings: settings, typrPolicy: false)?.target, "ja")
        XCTAssertEqual(DictationTranslationPlan(settings: settings, typrPolicy: true)?.target, "en")
        settings.targetLanguage = "de-AT"
        XCTAssertEqual(DictationTranslationPlan(settings: settings, typrPolicy: true)?.target, "de")
    }
}

@MainActor
final class DictationTranslatorTests: XCTestCase {
    private func settings() -> DictationTranslationSettings {
        let settings = DictationTranslationSettings(defaults: isolatedDefaults(self))
        settings.isEnabled = true
        return settings
    }

    func testTranslatesAnyLanguageAndClearsTheLastFailure() async {
        let settings = settings()
        settings.lastFailure = TranslationFailure(.failed, source: chinese, target: Locale.Language(identifier: "en"))
        let apple = StandInTranslation()
        apple.replies = [.success(" See you tomorrow. ")]
        let outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome, .translated("See you tomorrow."))
        XCTAssertEqual(apple.calls.map(\.source), ["zh"])
        XCTAssertNil(settings.lastFailure)
    }

    func testWithoutASourceTheLanguageIsReadFromTheText() async {
        let apple = StandInTranslation()
        apple.replies = [.success("I'll call you back later today.")]
        let outcome = await DictationTranslator.translate("Ich rufe dich heute später noch einmal zurück.",
                                                          target: "en", settings: settings(), engine: apple.engine)
        XCTAssertEqual(outcome, .translated("I'll call you back later today."))
        XCTAssertEqual(apple.calls.map(\.source), ["de"])
    }

    func testSameLanguageAndEmptyTextAreSkipped() async {
        let apple = StandInTranslation()
        let german = Locale.Language(identifier: "de-DE")
        let same = await DictationTranslator.translate("Bis morgen.", source: german, target: "de", settings: settings(), engine: apple.engine)
        let empty = await DictationTranslator.translate("  ", source: german, target: "en", settings: settings(), engine: apple.engine)
        XCTAssertEqual(same, .skipped)
        XCTAssertEqual(empty, .skipped)
        XCTAssertTrue(apple.calls.isEmpty)
    }

    func testMissingOrUnsupportedPairsFailWithTheirFix() async {
        let settings = settings()
        let apple = StandInTranslation()
        apple.status = .supported
        var outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome.failure?.reason, .notDownloaded)
        XCTAssertEqual(outcome.failure?.fix, "Download Chinese in Settings")
        XCTAssertEqual(settings.lastFailure?.reason, .notDownloaded)
        apple.status = .unsupported
        outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome.failure?.reason, .unsupported)
        XCTAssertTrue(apple.calls.isEmpty)
    }

    func testAFailedTranslationIsRetriedOnceAndNeverSticks() async {
        let settings = settings()
        let apple = StandInTranslation()
        apple.replies = [.failure(TranslationError.internalError), .success("See you tomorrow.")]
        var outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome, .translated("See you tomorrow."))
        XCTAssertEqual(apple.calls.count, 2)

        apple.replies = [.failure(TranslationError.internalError), .failure(TranslationError.internalError)]
        outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome.failure?.reason, .failed)
        XCTAssertEqual(outcome.failure?.fix, "Download Chinese again in Settings")
        XCTAssertNotNil(outcome.failure?.detail)
        XCTAssertEqual(apple.calls.count, 4)

        apple.replies = [.success("See you.")]
        outcome = await DictationTranslator.translate("再见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome, .translated("See you."))
        XCTAssertNil(settings.lastFailure)
    }

    func testBeforeIOS26WithoutTyprsWindowItSaysSo() async {
        let settings = settings()
        let apple = StandInTranslation()
        apple.replies = [.failure(TranslationEngine.NoSession()), .failure(TranslationEngine.NoSession())]
        let outcome = await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome.failure?.reason, .needsTyprOpen)
        XCTAssertEqual(outcome.failure?.fix, "iOS 18 translates only with Typr open")
        XCTAssertEqual(apple.calls.count, 1, "another wait wouldn't bring a session")
        XCTAssertEqual(settings.lastFailure?.reason, .needsTyprOpen)
    }

    func testACancelledTranslationKeepsNoFailure() async throws {
        let settings = settings()
        let apple = StandInTranslation()
        apple.suspends = true
        let engine = apple.engine
        let task = Task { await DictationTranslator.translate("我们明天见。", source: chinese, target: "en", settings: settings, engine: engine) }
        try await waitForState("translating") { apple.isWaiting }
        task.cancel()
        _ = await task.value
        XCTAssertEqual(apple.calls.count, 1)
        XCTAssertNil(settings.lastFailure)
    }
}

@MainActor
final class TyprDictationTranslatorTests: XCTestCase {
    func testTranslatesGermanAndEnglishBothWays() async {
        let apple = StandInTranslation()
        apple.replies = [.success(" See you tomorrow at ten. "), .success("Bis morgen.")]
        let english = await apple.policy.translate("Wir sehen uns morgen um zehn.", from: .german, to: .english)
        let german = await apple.policy.translate("See you tomorrow.", from: .english, to: .german)
        XCTAssertEqual(english, .translated("See you tomorrow at ten."))
        XCTAssertEqual(german, .translated("Bis morgen."))
        XCTAssertEqual(apple.calls.map(\.source), ["de", "en"])
    }

    func testAutomaticReadsGermanOrEnglishFromTheText() async {
        let apple = StandInTranslation()
        apple.replies = [.success("I'll call you back later today.")]
        let outcome = await apple.policy.translate("Ich rufe dich heute später noch einmal zurück.", from: .automatic, to: .english)
        XCTAssertEqual(outcome, .translated("I'll call you back later today."))
        XCTAssertEqual(apple.calls.map(\.source), ["de"])
    }

    func testMissingPackAndTwoFailuresGoInAsSpoken() async {
        let apple = StandInTranslation()
        apple.status = .supported
        var outcome = await apple.policy.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome?.failure?.reason, .notDownloaded)
        XCTAssertTrue(apple.calls.isEmpty)
        apple.status = .installed
        apple.replies = [.failure(StandInError()), .success("  ")]
        outcome = await apple.policy.translate("Bis morgen.", from: .german, to: .english)
        XCTAssertEqual(outcome?.failure?.reason, .failed)
        XCTAssertEqual(apple.calls.count, 2)
    }

    func testDeadlineEndsAWaitingTranslation() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let policy = apple.policy
        let task = Task { await policy.translate("Bis morgen.", from: .german, to: .english) }
        try await waitForState("translating") { apple.isWaiting && apple.hasDeadline }
        apple.expireDeadline()
        let outcome = await task.value
        XCTAssertEqual(outcome?.failure?.reason, .failed)
        try await waitForState("translation cancelled") { apple.cancelled }
        XCTAssertEqual(apple.calls.count, 1)
    }

    func testCancellationReturnsNothing() async throws {
        let apple = StandInTranslation()
        apple.suspends = true
        let policy = apple.policy
        let task = Task { await policy.translate("Bis morgen.", from: .german, to: .english) }
        try await waitForState("translating") { apple.isWaiting }
        task.cancel()
        let outcome = await task.value
        XCTAssertNil(outcome)
        try await waitForState("translation cancelled") { apple.cancelled }
    }

    func testThePlanUsesItForAnyTargetAndKeepsItsFailure() async {
        let settings = DictationTranslationSettings(defaults: isolatedDefaults(self))
        settings.isEnabled = true
        settings.targetLanguage = "ja"
        let apple = StandInTranslation()
        apple.status = .supported
        let plan = DictationTranslationPlan(settings: settings, typrPolicy: true)
        let outcome = await plan?.translate("Bis morgen.", source: .german, settings: settings, engine: apple.engine)
        XCTAssertEqual(outcome?.failure?.reason, .notDownloaded)
        XCTAssertEqual(outcome?.failure?.target, "en")
        XCTAssertEqual(settings.lastFailure, outcome?.failure)
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
        let translation: DictationTranslationSettings
        let bridge: KeyboardBridge
        let model: CleanupTestSession
        let clock: CleanupTestSleeper
    }

    private func makeFixture(spoken: String, translate: Bool, target: String = "en", typrPolicy: Bool = false,
                             apple: StandInTranslation, aiCleanup: Bool = false, cleaned: String = "") async throws -> Fixture {
        let defaults = isolatedDefaults(self)
        let settings = TyprSettings(defaults: defaults)
        settings.dictationLanguage = .german
        settings[experiment: .typrTranslationPolicy] = typrPolicy
        let translation = DictationTranslationSettings(defaults: defaults)
        translation.isEnabled = translate
        translation.targetLanguage = target
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
            languageSettings: settings, translationSettings: translation, translationEngine: apple.engine)
        controller.prepareModel()
        try await waitForState("model ready") { controller.phase == .ready }
        return Fixture(controller: controller, translation: translation, bridge: bridge, model: model, clock: clock)
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

    func testTranslationIsInsertedAndFormattedInTheTarget() async throws {
        let apple = StandInTranslation()
        apple.replies = [.success("see you tomorrow at the office")]
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        f.translation.lastFailure = TranslationFailure(.failed, source: Locale.Language(identifier: "de"), target: Locale.Language(identifier: "en"))
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(apple.calls.map(\.text), ["Wir sehen uns morgen im Büro"])
        XCTAssertEqual(apple.calls.map(\.source), ["de"])
        XCTAssertEqual(f.controller.transcript, "See you tomorrow at the office.")
        XCTAssertEqual(f.bridge.snapshot().transcript, "See you tomorrow at the office.")
        XCTAssertNil(f.bridge.snapshot().translationFailure)
        XCTAssertEqual(f.bridge.snapshot().translated, true, "Learn from my edits must skip a translation")
        XCTAssertNil(f.controller.translationFailure)
        XCTAssertNil(f.translation.lastFailure)
        try await drain(f)
    }

    func testMissingPackPastesAsSpokenAndTellsTheKeyboardWhy() async throws {
        let apple = StandInTranslation()
        apple.status = .supported
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, apple: apple)
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(f.controller.transcript, "Wir sehen uns morgen im Büro.")
        let snapshot = f.bridge.snapshot()
        XCTAssertEqual(snapshot.transcript, "Wir sehen uns morgen im Büro.")
        XCTAssertEqual(snapshot.translationFailure?.reason, .notDownloaded)
        XCTAssertEqual(snapshot.translationFailure?.fix, "Download German in Settings")
        XCTAssertNotEqual(snapshot.translated, true)
        XCTAssertEqual(f.controller.translationFailure?.reason, .notDownloaded)
        XCTAssertEqual(f.translation.lastFailure?.reason, .notDownloaded)
        try await drain(f)
    }

    func testTheTyprPolicyTranslatesIntoEnglishForAnyOtherTarget() async throws {
        let apple = StandInTranslation()
        apple.replies = [.success("see you tomorrow at the office")]
        let f = try await makeFixture(spoken: "Wir sehen uns morgen im Büro", translate: true, target: "ja",
                                      typrPolicy: true, apple: apple)
        try await dictate(f)
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertEqual(apple.calls.map(\.target), ["en"])
        XCTAssertEqual(f.controller.transcript, "See you tomorrow at the office.")
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
        XCTAssertNil(f.translation.lastFailure)
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
        XCTAssertNil(f.bridge.snapshot().translationFailure)
        XCTAssertNotEqual(f.bridge.snapshot().translated, true)
        try await drain(f)
    }

    func testSettingIsFrozenWhenRecordingStarts() async throws {
        let apple = StandInTranslation()
        let f = try await makeFixture(spoken: "Bis morgen", translate: false, apple: apple)
        f.controller.startRecording(keyboardJobID: UUID().uuidString, styleOverride: .polished, copyToPasteboard: false)
        try await waitForState("recording") { f.controller.phase == .recording }
        f.translation.isEnabled = true
        f.controller.finishRecording()
        try await waitForState("delivered") { f.controller.isIdleForTest }
        XCTAssertTrue(apple.calls.isEmpty)
        XCTAssertEqual(f.controller.transcript, "Bis morgen.")
        try await drain(f)
    }
}

@MainActor
final class KeyboardTranslationNoteTests: XCTestCase {
    private let failure = TranslationFailure(.notDownloaded, source: Locale.Language(identifier: "de"),
                                             target: Locale.Language(identifier: "en"))

    func testNoteHidesByItself() async throws {
        let model = KeyboardViewModel()
        model.translationNoteDuration = 0.05
        model.translationNote = failure
        XCTAssertEqual(model.resultNote, "Couldn't translate, pasted as spoken")
        try await waitForState("note hidden") { model.translationNote == nil }
        XCTAssertNil(model.resultNote)
    }

    func testInKeyboardDictationCarriesItsTranslation() async throws {
        let defaults = isolatedDefaults(self)
        let settings = TyprSettings(defaults: defaults)
        let text = await KeyboardLocalCapture.text(
            from: "Wir sehen uns morgen", style: .polished, settings: settings,
            vocabulary: CustomVocabularySettings(defaults: defaults), learning: DictationLearningStore(defaults: defaults),
            translate: { _ in .translated("see you tomorrow", language: "en") })
        XCTAssertEqual(text, "See you tomorrow.")

        var capture = KeyboardLocalCapture()
        _ = capture.start(jobID: "j", at: 1)
        _ = capture.stop()
        capture.finish(jobID: "j", transcript: "Wir sehen uns morgen.", resultID: "r", translation: .failed(failure))
        let snapshot = try XCTUnwrap(capture.snapshot(now: 2, loudnessDB: -30))
        XCTAssertEqual(snapshot.translationFailure, failure)
        XCTAssertEqual(snapshot.translated, false)
    }
}

@MainActor
final class KeyboardSnapshotTranslationTests: XCTestCase {
    func testSnapshotsCarryWhyATranslationWentInAsSpokenAndOldOnesStillRead() throws {
        let defaults = UserDefaults(suiteName: "translation.bridge.\(UUID().uuidString)")!
        let bridge = KeyboardBridge(defaults: defaults)
        let failure = TranslationFailure(.failed, source: Locale.Language(identifier: "zh-CN"),
                                         target: Locale.Language(identifier: "en"), detail: "TranslationErrorDomain 16")
        bridge.publish(KeyboardSnapshot(state: .ready, heartbeat: 1, expiresAt: 2, resultID: "r",
                                        transcript: "我们明天见。", translationFailure: failure))
        XCTAssertEqual(bridge.snapshot().translationFailure, failure)

        let old = #"{"state":"ready","heartbeat":1,"expiresAt":2,"audioLevel":0,"resultID":"r","transcript":"Hallo"}"#
        let snapshot = try JSONDecoder().decode(KeyboardSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snapshot.translated)
        XCTAssertNil(snapshot.translationFailure)
        XCTAssertEqual(snapshot.transcript, "Hallo")
    }

    func testTranslationSettingsLaunchOpensAPageWithoutAHandoff() {
        let request = KeyboardLaunchRequest.translationSettings
        XCTAssertEqual(request.url.absoluteString, "typr://keyboard/translation")
        XCTAssertEqual(KeyboardLaunchRequest(url: request.url), request)
        XCTAssertNil(request.host)
        XCTAssertFalse(request.isHandoffExpired(at: 1_000_000))
    }
}

@MainActor
private final class StandInSession {
    private(set) var texts: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { gate != nil }

    func release() {
        gate?.resume()
        gate = nil
    }

    func translate(_ text: String, into target: String, holds: Bool) async -> String {
        texts.append(text)
        if holds { await withCheckedContinuation { gate = $0 } }
        return "\(target): \(text)"
    }
}

@MainActor
final class TranslationSessionHostTests: XCTestCase {
    func testReversedPairsBackToBackEachGetTheirOwnSession() async throws {
        let host = TranslationSessionHost()
        let german = Locale.Language(identifier: "de"), english = Locale.Language(identifier: "en")
        let first = Task { try await host.translate("Bis morgen.", from: german, to: english) }
        try await waitForState("first pair asked for") { host.configuration?.target == english }
        let toEnglish = StandInSession()
        let stale = Task { await host.serve(.init(german, english)) { await toEnglish.translate($0, into: "en", holds: true) } }
        try await waitForState("first in the session") { toEnglish.isWaiting }

        let second = Task { try await host.translate("See you tomorrow.", from: english, to: german) }
        try await waitForState("reversed pair asked for") { host.configuration?.target == german }
        toEnglish.release()
        await stale.value
        let firstText = try await first.value
        XCTAssertEqual(firstText, "en: Bis morgen.")
        XCTAssertEqual(toEnglish.texts, ["Bis morgen."], "the German to English session never takes English text")

        let toGerman = StandInSession()
        await host.serve(.init(english, german)) { await toGerman.translate($0, into: "de", holds: false) }
        let secondText = try await second.value
        XCTAssertEqual(secondText, "de: See you tomorrow.")
        XCTAssertEqual(toGerman.texts, ["See you tomorrow."])
    }

    func testTextsLeftForAnotherPairAskForTheirSessionNext() async throws {
        let host = TranslationSessionHost()
        let german = Locale.Language(identifier: "de"), english = Locale.Language(identifier: "en")
        let first = Task { try await host.translate("Bis morgen.", from: german, to: english) }
        try await waitForState("first queued") { host.configuration?.target == english }
        let second = Task { try await host.translate("See you.", from: english, to: german) }
        try await waitForState("second queued") { host.configuration?.target == german }
        let toGerman = StandInSession()
        await host.serve(.init(english, german)) { await toGerman.translate($0, into: "de", holds: false) }
        let secondText = try await second.value
        XCTAssertEqual(secondText, "de: See you.")
        XCTAssertEqual(host.configuration?.target, english, "German to English is asked for again")
        let toEnglish = StandInSession()
        await host.serve(.init(german, english)) { await toEnglish.translate($0, into: "en", holds: false) }
        let firstText = try await first.value
        XCTAssertEqual(firstText, "en: Bis morgen.")
    }
}

@MainActor
final class KeyboardLocalTranslationPlanTests: XCTestCase {
    func testThePlanIsReadWhenTheDictationStarts() {
        let settings = DictationTranslationSettings(defaults: isolatedDefaults(self))
        settings.isEnabled = true
        settings.targetLanguage = "en"
        var capture = KeyboardLocalCapture()
        XCTAssertEqual(capture.start(jobID: "j", at: 1, translation: DictationTranslationPlan(settings: settings, typrPolicy: false)),
                       .begin(jobID: "j"))
        settings.targetLanguage = "de"
        settings.isEnabled = false
        XCTAssertEqual(capture.stop(), "j")
        XCTAssertEqual(capture.translation?.target, "en", "a change while recording applies to the next dictation")
        capture.cancel()
        XCTAssertNil(capture.translation)
    }

    func testAKeptCaptureKeepsThePlanReadAtTouchDown() {
        let settings = DictationTranslationSettings(defaults: isolatedDefaults(self))
        settings.isEnabled = true
        settings.targetLanguage = "de"
        var capture = KeyboardLocalCapture()
        XCTAssertTrue(capture.arm(jobID: "j", at: 1, translation: DictationTranslationPlan(settings: settings, typrPolicy: false)))
        settings.targetLanguage = "en"
        XCTAssertEqual(capture.start(jobID: "other", at: 2, translation: DictationTranslationPlan(settings: settings, typrPolicy: false)),
                       .kept(jobID: "j"))
        XCTAssertEqual(capture.translation?.target, "de")
    }
}
