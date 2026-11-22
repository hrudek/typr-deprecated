import XCTest
@testable import Typr

final class SpokenCleanupTests: XCTestCase {
    private func assertCleans(_ cases: [(String, String)], language: DictationLanguage,
                              file: StaticString = #filePath, line: UInt = #line) {
        for (spoken, expected) in cases {
            XCTAssertEqual(SpokenCleanup.clean(spoken, language: language), expected, spoken, file: file, line: line)
        }
    }

    func testGermanRemovesHesitationsStuttersAndExplicitRepairs() {
        assertCleans([
            ("Äh, das ist eh egal.", "Das ist eh egal."),
            ("Ich ähm ich habe Hunger.", "Ich habe Hunger."),
            ("Öh, hm, wir gehen.", "Wir gehen."),
            ("Danke, äh. Bis dann.", "Danke. Bis dann."),
            ("Ich weiß nicht, ähm.", "Ich weiß nicht."),
            ("ich ich habe keine Zeit", "ich habe keine Zeit"),
            ("Ich, ich habe keine Zeit.", "Ich habe keine Zeit."),
            ("Am Dienstag, ich meine, Mittwoch.", "Am Mittwoch."),
            ("Dienstag, nein, Mittwoch.", "Mittwoch."),
            ("Wir treffen uns um 3, nein, um 4.", "Wir treffen uns um 4."),
            ("Ich komme am Montag, ich meine, am Dienstag.", "Ich komme am Dienstag."),
            ("Wir sehen uns morgen, nein, übermorgen.", "Wir sehen uns übermorgen."),
            ("Treffen mit Anna, ich meine, mit Paul.", "Treffen mit Paul."),
            ("Am Dienstag, äh, ich meine, Mittwoch.", "Am Mittwoch."),
        ], language: .german)
    }

    func testGermanGuardsKeepWhatWasMeant() {
        assertCleans([
            ("Das ist eh egal.", "Das ist eh egal."),
            ("Ich komme um 13 Uhr.", "Ich komme um 13 Uhr."),
            ("Hm? Was meinst du?", "Hm? Was meinst du?"),
            ("Das ist sehr sehr gut.", "Das ist sehr sehr gut."),
            ("Ich weiß, dass das das Beste ist.", "Ich weiß, dass das das Beste ist."),
            ("Die Frau, die die Tür öffnet.", "Die Frau, die die Tür öffnet."),
            ("Nein, ich meine das ernst.", "Nein, ich meine das ernst."),
            ("Kommst du am Montag? Nein, am Dienstag.", "Kommst du am Montag? Nein, am Dienstag."),
            ("Er sagte, nein, er kommt nicht.", "Er sagte, nein, er kommt nicht."),
            ("Ich mag das nicht, nein, wirklich nicht.", "Ich mag das nicht, nein, wirklich nicht."),
            ("Sag Anna, nein, das geht nicht.", "Sag Anna, nein, das geht nicht."),
            ("Das ist teuer, ich meine, wirklich teuer.", "Das ist teuer, ich meine, wirklich teuer."),
            ("Ich war müde, ich meine, ich habe nicht geschlafen.", "Ich war müde, ich meine, ich habe nicht geschlafen."),
            ("Das ist teuer, ich meine, das ist zu viel.", "Das ist teuer, ich meine, das ist zu viel."),
            ("Wir können gehen, ich meine, wir müssen nicht bleiben.", "Wir können gehen, ich meine, wir müssen nicht bleiben."),
            ("Die Tür ist zu, zu spät.", "Die Tür ist zu, zu spät."),
        ], language: .german)
    }

    func testEnglishRemovesHesitationsStuttersAndExplicitRepairs() {
        assertCleans([
            ("Um, I think so.", "I think so."),
            ("I, um, I think we should go.", "I think we should go."),
            ("the the meeting is uh at noon", "the meeting is at noon"),
            ("Let's meet on Tuesday, I mean, Wednesday.", "Let's meet on Wednesday."),
            ("Meet at 3, no, at 4.", "Meet at 4."),
        ], language: .english)
    }

    func testEnglishGuardsKeepWhatWasMeant() {
        assertCleans([
            ("It is very very good.", "It is very very good."),
            ("I know that that works.", "I know that that works."),
            ("No, I mean it.", "No, I mean it."),
            ("I was tired, I mean, I didn't sleep.", "I was tired, I mean, I didn't sleep."),
            ("I said no, not today.", "I said no, not today."),
            ("Is it Monday? No, it is Tuesday.", "Is it Monday? No, it is Tuesday."),
        ], language: .english)
    }

    func testAutomaticKeepsGermanUmAndTrimsEnglishUm() {
        assertCleans([
            ("Um 13 Uhr, äh, im Büro.", "Um 13 Uhr, im Büro."),
            ("Um, I think so.", "I think so."),
        ], language: .automatic)
    }

    func testOnByDefault() {
        let suite = "spoken.cleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.cleanUpWhatISay)
        settings.cleanUpWhatISay = false
        XCTAssertFalse(TyprSettings(defaults: defaults).cleanUpWhatISay)
    }
}

@MainActor
private final class SpokenAudio: AudioManaging {
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?
    func requestPermission() async -> Bool { true }
    func startKeepalive(microphone: MicrophoneChoice) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }
    func beginCapture(at url: URL, maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ActiveAudioCapture {
        SpokenCapture(url: url)
    }
}

@MainActor
private final class SpokenCapture: ActiveAudioCapture {
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

private actor SpokenASR: LocalTranscribing {
    nonisolated let displayName = "Test ASR"
    let languageName = "German"
    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {}
    func transcribe(_ url: URL) async throws -> String { "Am Dienstag, äh, ich meine, Mittwoch" }
}

@MainActor
final class SpokenCleanupPipelineTests: XCTestCase {
    /// The rules run on the transcript before AI cleanup sees it, and Verbatim or the switch
    /// turned off skips them.
    func testRulesRunBeforeAICleanupAndVerbatimBypasses() async throws {
        let cases: [(Bool, Bool, DictationStyle, String, String?)] = [
            (true, true, .polished, "Am Mittwoch.", "Am Mittwoch"),
            (true, false, .polished, "Am Mittwoch.", nil),
            (true, true, .verbatim, "Am Dienstag, äh, ich meine, Mittwoch", nil),
            (false, false, .polished, "Am Dienstag, ich meine, Mittwoch.", nil),
        ]
        for (switchOn, aiOn, style, delivered, modelInput) in cases {
            let suite = "spoken.cleanup.pipeline.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = TyprSettings(defaults: defaults)
            settings.dictationLanguage = .german
            settings.cleanUpWhatISay = switchOn
            let model = CleanupTestSession()
            model.result = "Am Mittwoch."
            let clock = CleanupTestSleeper()
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model),
                background: CleanupTestBackground(), isEnabled: { aiOn }, sleep: clock.sleep)
            let asr = SpokenASR()
            let controller = DictationController(audio: SpokenAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
                transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false, cleanup: deps,
                languageSettings: settings)
            controller.prepareModel()
            try await waitForState("model ready") { controller.phase == .ready }
            controller.startRecording(keyboardJobID: "job", styleOverride: style, copyToPasteboard: false)
            try await waitForState("recording") { controller.phase == .recording }
            controller.finishRecording()
            try await waitForState("delivered") { controller.isIdleForTest }

            XCTAssertEqual(controller.transcript, delivered, "\(switchOn) \(aiOn) \(style)")
            if let modelInput {
                XCTAssertEqual(model.prompts.count, 1)
                XCTAssertTrue(model.prompts[0].contains(modelInput))
                XCTAssertFalse(model.prompts[0].contains("Dienstag"))
            } else {
                XCTAssertTrue(model.prompts.isEmpty)
            }
            controller.cancelCurrentJob()
            clock.fire()
            try await waitForState("idle") { controller.isIdleForTest && model.cleansInFlight == 0 }
            await mainActorBarrier()
        }
    }
}
