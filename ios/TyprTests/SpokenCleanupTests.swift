import XCTest
@testable import Typr

final class SpokenCleanupTests: XCTestCase {
    private func assertCleans(_ cases: [(String, String)], language: DictationLanguage,
                              file: StaticString = #filePath, line: UInt = #line) {
        for (spoken, expected) in cases {
            XCTAssertEqual(SpokenCleanup.clean(spoken, language: language), expected, spoken, file: file, line: line)
        }
    }

    private func assertUnchanged(_ prose: [String], language: DictationLanguage,
                                 file: StaticString = #filePath, line: UInt = #line) {
        assertCleans(prose.map { ($0, $0) }, language: language, file: file, line: line)
    }

    static let germanCleanups: [(String, String)] = [
        ("Äh, das ist eh egal.", "Das ist eh egal."),
        ("Ich ähm habe Hunger.", "Ich habe Hunger."),
        ("Öh, hm, wir gehen.", "Wir gehen."),
        ("Danke, äh. Bis dann.", "Danke. Bis dann."),
        ("Ich weiß nicht, ähm.", "Ich weiß nicht."),
        ("Brot und und Butter.", "Brot und Butter."),
        ("Ich komme, weil weil es regnet.", "Ich komme, weil es regnet."),
        ("Am Dienstag, ich meine, Mittwoch.", "Am Mittwoch."),
        ("Dienstag, nein, Mittwoch.", "Mittwoch."),
        ("Wir treffen uns um 3, nein, um 4.", "Wir treffen uns um 4."),
        ("Wir treffen uns um 3, nein, um 4 Uhr.", "Wir treffen uns um 4 Uhr."),
        ("Ich komme am Montag, ich meine, am Dienstag.", "Ich komme am Dienstag."),
        ("Wir sehen uns morgen, nein, übermorgen.", "Wir sehen uns übermorgen."),
        ("Der Termin ist im März, besser gesagt, im April.", "Der Termin ist im April."),
        ("Am Dienstag, äh, ich meine, Mittwoch.", "Am Mittwoch."),
        ("Montag, nein, Dienstag, nein, Mittwoch.", "Mittwoch."),
        ("Er kommt morgen.\nSie bleibt, äh, hier.", "Er kommt morgen.\nSie bleibt, hier."),
        ("Er kommt morgen.\r\n\r\nSie bleibt, äh, hier.", "Er kommt morgen.\r\n\r\nSie bleibt, hier."),
        ("Er kommt morgen.\u{2028}Sie bleibt, äh, hier.", "Er kommt morgen.\u{2028}Sie bleibt, hier."),
        ("Er kommt morgen.\rSie bleibt, äh, hier.\u{2029}Gut.", "Er kommt morgen.\rSie bleibt, hier.\u{2029}Gut."),
    ]

    func testGermanRemovesHesitationsStuttersAndExplicitRepairs() {
        assertCleans(Self.germanCleanups, language: .german)
    }

    /// Prose that must come back exactly as said: explanations, answers, negation, names,
    /// emphatic and grammatical repeats, quotes, line breaks and repairs that do not end
    /// their clause.
    static let germanProse: [String] = [
        "Das ist eh egal.",
        "Ich komme um 13 Uhr.",
        "Hm? Was meinst du?",
        "Das ist sehr sehr gut.",
        "Ich weiß, dass das das Beste ist.",
        "Die Frau, die die Tür öffnet, ist meine Schwester.",
        "Wenn sie sie sieht, freut sie sich.",
        "Der der das sagt, lügt.",
        "Das, das ist es.",
        "Nein, ich meine das ernst.",
        "Ich meine, das ist richtig.",
        "Was ich meine, ist etwas anderes.",
        "Er meinte, ich meine es nicht ernst.",
        "Kommst du am Montag? Nein, am Dienstag.",
        "Er sagte, nein, er kommt nicht.",
        "Ich mag das nicht, nein, wirklich nicht.",
        "Ich glaube, nein, ich weiß es.",
        "Sag Anna, nein, das geht nicht.",
        "Treffen mit Anna, ich meine, mit Paul.",
        "Mein Name ist Hans, nein, nicht Hans Müller.",
        "Das ist teuer, ich meine, wirklich teuer.",
        "Ich war müde, ich meine, ich habe nicht geschlafen.",
        "Das ist teuer, ich meine, das ist zu viel.",
        "Wir können gehen, ich meine, wir müssen nicht bleiben.",
        "Ich arbeite am Montag nicht, ich meine, Montag ist mein freier Tag.",
        "Das ist für Anna, ich meine, Anna braucht das dringend.",
        "Ich komme am Montag. Ich meine, Montag ist ein guter Tag.",
        "Ich komme am Montag, ich meine, Dienstag ist besser.",
        "Wir gehen am Freitag ins Kino, ich meine, Freitag ist gut.",
        "Wir gehen um acht. Nein, um neun.",
        "Das Meeting ist morgen, nein?",
        "Ich habe drei Kinder, nein, vier Enkel.",
        "Die Zahl 3, nein, die Zahl 4 ist richtig.",
        "Um 3, nein, um 4 Uhr geht es nicht.",
        "Heute, nein, morgen wird es regnen.",
        "Morgen, nein, heute ist der Tag.",
        "Ich hab heute, nein, ich hab gestern angerufen.",
        "Am 3. Mai, nein, das war der 4. Mai.",
        "Er ist zwei, nein, er ist drei Jahre alt.",
        "Er hat 2, nein, 3 Kinder.",
        "Die Antwort ist zwei, nein, nicht drei.",
        "Kommt sie heute, nein, oder morgen?",
        "Seit Montag, nein, seit Wochen geht das so.",
        "Wir treffen uns im Mai, nein, im Juni geht es nicht.",
        "Am Montag, sorry, am Dienstag kann ich nicht.",
        "Er hat gestern, entschuldigung, gestern Abend angerufen.",
        "Sie sagte: „Am Montag, nein, am Dienstag.“",
        "Die Tür ist zu, zu spät.",
        "Was mir wichtig ist, ist Ruhe.",
        "Was es ist ist gut.",
        "Und, und dann?",
        "Immer nur ich ich ich.",
        "Ich ich bin's.",
        "Ich, ich, ich – immer geht es nur um dich.",
        "Du, du bist gemeint.",
        "Ja, ja, ich komme.",
        "Nein, nein, nein!",
        "Und und und, das hört nie auf.",
        "Bla bla bla.",
        "Wir sprechen über das Wort „ich ich“.",
        "„Und und“, sagte er.",
        "Das steht da (mit mit) doppelt.",
        "Ich komme mit mit dem Rad.",
        "Er passt auf auf das Kind.",
        "Aber aber, wer wird denn weinen?",
        "Er schaltet ein ein Gerät nach dem anderen.",
        "Wenn wenn das Wörtchen wenn nicht wär.",
        "Das kostet zwei, nein, drei Euro.",
        "Ich ruf dich heute, nein, morgen an.",
        "Er wurde am 3. Mai, nein, am 4. Mai geboren.",
        "Wählen Sie 1, nein, 2 oder 3.",
        "Zwölf, nein, zwölf Uhr.",
        "Er hat gesagt, dass dass nicht geht.",
        "Ich komme nicht am Montag, nein, am Dienstag.",
        "Nicht heute, nein, morgen.",
        "Ich habe keine Zeit am Montag, ich meine, Dienstag.",
        "Er kommt nie am Freitag, sorry, am Samstag.",
        "Ich bringe dem einen einen Kaffee und dem anderen einen Tee.",
        "Ich sah, wie die eine eine Tasche trug.",
        "Ich habe einen einen Hund.",
        "Ich suche Noten für Für Elise.",
        "Und und dann gehen wir.",
        "Weil weil er krank ist.",
        "Er kommt morgen.\r\n\r\nSie bleibt hier.",
        "Er kommt morgen.\u{2028}Sie bleibt hier.",
        "Weil, weil er krank ist.",
        "Die Familie Freitag, nein, die Familie Samstag.",
        "Er sagte äh-ja.",
        "Sie wohnt in Öhringen.",
        "Mit Ach und Krach.",
        "Er zählte: eins, zwei, drei, vier.",
        "Er kommt morgen.\nSie bleibt hier.",
        "Die Sitzung ist heute.\n\nMorgen fahre ich weg.",
    ]

    func testGermanProseStaysAsSaid() {
        assertUnchanged(Self.germanProse, language: .german)
    }

    func testEnglishRemovesHesitationsStuttersAndExplicitRepairs() {
        assertCleans([
            ("Um, I think so.", "I think so."),
            ("the the meeting is uh at noon", "the meeting is at noon"),
            ("Let's meet on Tuesday, I mean, Wednesday.", "Let's meet on Wednesday."),
            ("Meet at 3, no, at 4.", "Meet at 4."),
            ("Meet at 3, no, at 4 pm.", "Meet at 4 pm."),
        ], language: .english)
    }

    func testEnglishProseStaysAsSaid() {
        assertUnchanged([
            "It is very very good.",
            "I know that that works.",
            "What it is is a mess.",
            "No, I mean it.",
            "I mean, Tuesday is fine.",
            "I said no, not today.",
            "Is it Monday? No, it is Tuesday.",
            "I was tired, I mean, I didn't sleep.",
            "Meet on Monday, no, Monday works.",
            "I, I, I always get blamed.",
            "No, no, no!",
            "The word \"the the\" is a typo.",
            "Not Monday, I mean, Tuesday.",
            "I don't work Monday, I mean, Tuesday.",
            "I bought tickets for For All Mankind.",
            "The The is a band.",
        ], language: .english)
    }

    func testAutomaticKeepsGermanUmAndTrimsEnglishUm() {
        assertCleans([
            ("Um 13 Uhr, äh, im Büro.", "Um 13 Uhr, im Büro."),
            ("Um, I think so.", "I think so."),
        ], language: .automatic)
    }

    @MainActor
    func testCleanUpWhatISayIsOnByDefaultAndTheOldSwitchIsRetired() {
        let suite = "spoken.cleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .cleanUpWhatISay] = false
        XCTAssertTrue(settings.dictationSpokenCleanup)
        XCTAssertFalse(ExperimentalSwitch.all.contains(.cleanUpWhatISay))
        XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(.typrConservativeSpokenCleanup))
        XCTAssertFalse(settings[experiment: .typrConservativeSpokenCleanup])
        let pipeline = DictationPipeline(style: .polished, language: .german, vocabulary: DictationVocabulary(userTerms: []),
                                         settings: settings)
        XCTAssertTrue(pipeline.spokenCleanup)
        XCTAssertFalse(pipeline.typrSpokenCleanup)
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
    var text = "Am Dienstag, äh, ich meine, Mittwoch"
    func say(_ spoken: String) { text = spoken }
    func transcribe(_ url: URL) async throws -> String { text }
}

@MainActor
final class SpokenCleanupPipelineTests: XCTestCase {
    /// Hex's hesitation rule runs on the transcript before AI cleanup sees it, the correction
    /// stays as said, and Verbatim or the switch turned off skips the rule.
    func testRulesRunBeforeAICleanupAndVerbatimBypasses() async throws {
        let cases: [(Bool, Bool, DictationStyle, String, String?)] = [
            (true, true, .polished, "Am Mittwoch.", "Am Dienstag, ich meine, Mittwoch"),
            (true, false, .polished, "Am Dienstag, ich meine, Mittwoch.", nil),
            (true, true, .verbatim, "Am Dienstag, äh, ich meine, Mittwoch", nil),
            (false, false, .polished, "Am Dienstag, ich meine, Mittwoch.", nil),
        ]
        for (switchOn, aiOn, style, delivered, modelInput) in cases {
            let suite = "spoken.cleanup.pipeline.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = TyprSettings(defaults: defaults)
            settings.chooseDictationLanguage(.german)
            settings.dictationSpokenCleanup = switchOn
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
                XCTAssertFalse(model.prompts[0].contains("äh"))
            } else {
                XCTAssertTrue(model.prompts.isEmpty)
            }
            controller.cancelCurrentJob()
            clock.fire()
            try await waitForState("idle") { controller.isIdleForTest && model.cleansInFlight == 0 }
            await mainActorBarrier()
        }
    }

    /// On by default, Clean up what I say removes hesitations with Hex's rule for German, Spanish
    /// and Norwegian, leaves spoken corrections and English as heard; Typr conservative spoken
    /// cleanup runs Typr's German and English rules instead; off or Verbatim skips both. AI
    /// cleanup gets the cleaned text, and the style trims no hesitation Hex's rule kept.
    func testDefaultRemovesHexHesitationsAndTheOverrideRunsTyprRules() async {
        let correction = "Wir kommen am Montag. Nein, am Dienstag."
        let cases: [(cleanup: Bool, typr: Bool, style: DictationStyle, language: String, heard: String, tagged: String, delivered: String)] = [
            (true, false, .polished, "de", correction, correction, correction),
            (true, false, .polished, "de", "Am Dienstag, äh, ich meine, Mittwoch.", "Am Dienstag, ich meine, Mittwoch.",
             "Am Dienstag, ich meine, Mittwoch."),
            (true, false, .polished, "de", "Ich kann am Montag äh. Nein, Dienstag passt besser.",
             "Ich kann am Montag. Nein, Dienstag passt besser.", "Ich kann am Montag. Nein, Dienstag passt besser."),
            (true, false, .polished, "es-ES", "Gracias, eh. Hasta luego.", "Gracias. Hasta luego.", "Gracias. Hasta luego."),
            (true, false, .polished, "nb-NO", "Jeg kommer på mandag, nei, på tirsdag.", "Jeg kommer på mandag, nei, på tirsdag.",
             "Jeg kommer på mandag, nei, på tirsdag."),
            (true, false, .polished, "de", "Brot und und Butter.", "Brot und und Butter.", "Brot und und Butter."),
            (true, false, .polished, "de", "äh. Danke.", "Danke.", "Danke."),
            (true, false, .polished, "de", "Danke\näh\nBis dann.", "Danke\nBis dann.", "Danke.\nBis dann."),
            (true, false, .polished, "de", "Sie sagte: « äh. » Danach schwieg sie.", "Sie sagte: « äh. » Danach schwieg sie.",
             "Sie sagte: « äh. » Danach schwieg sie."),
            (true, false, .polished, "en-US", "On Tuesday, I mean, Wednesday.", "On Tuesday, I mean, Wednesday.",
             "On Tuesday, I mean, Wednesday."),
            (true, false, .polished, "en-US", "Thanks, um. See you.", "Thanks, um. See you.", "Thanks. See you."),
            (true, true, .polished, "de", "Brot und und Butter.", "Brot und Butter.", "Brot und Butter."),
            (true, true, .polished, "en-US", "On Tuesday, I mean, Wednesday.", "On Wednesday.", "On Wednesday."),
            (true, false, .verbatim, "de", "Danke\näh\nBis dann.", "Danke\näh\nBis dann.", "Danke\näh\nBis dann."),
            (false, false, .polished, "de", "äh. Danke.", "äh. Danke.", ". Danke."),
        ]
        for (cleanup, typr, style, language, heard, tagged, delivered) in cases {
            let suite = "spoken.cleanup.default.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = TyprSettings(defaults: defaults)
            if !cleanup { settings.dictationSpokenCleanup = false }
            settings[experiment: .typrConservativeSpokenCleanup] = typr
            var pipeline = DictationPipeline(style: style, language: .automatic, vocabulary: DictationVocabulary(userTerms: []),
                                             settings: settings)
            pipeline.language = language
            var refined: [String] = []
            let stages = await pipeline.run(heard, refine: { text, _ in
                refined.append(text)
                return text
            })
            let label = "\(cleanup) \(typr) \(style) \(language) \(heard)"
            XCTAssertEqual(Array(stages.tagged.utf8), Array(tagged.utf8), label)
            XCTAssertEqual(refined, [tagged], label)
            XCTAssertEqual(Array(stages.formatted.utf8), Array(delivered.utf8), label)
        }
    }

    // Observed Hex output, with Typr's fixes on the Hex base (`TranscriptFormatterTyprFixTests`).
    static let hexPolishedWithoutCleanup: [String] = [
        "Das ist eh egal.",
        "Ich habe Hunger.",
        "Wir gehen.",
        "Danke. Bis dann.",
        "Ich weiß nicht.",
        "Brot und und Butter.",
        "Ich komme, weil weil es regnet.",
        "Am Dienstag, ich meine, Mittwoch.",
        "Dienstag, nein, Mittwoch.",
        "Wir treffen uns um 3, nein, um 4.",
        "Wir treffen uns um 3, nein, um 4 Uhr.",
        "Ich komme am Montag, ich meine, am Dienstag.",
        "Wir sehen uns morgen, nein, übermorgen.",
        "Der Termin ist im März, besser gesagt, im April.",
        "Am Dienstag, ich meine, Mittwoch.",
        "Montag, nein, Dienstag, nein, Mittwoch.",
        "Er kommt morgen.\nSie bleibt, hier.",
        "Er kommt morgen.\r\n\r\nSie bleibt, hier.",
        "Er kommt morgen.\u{2028}Sie bleibt, hier.",
        "Er kommt morgen.\rSie bleibt, hier.\u{2029}Gut.",
        "Das ist eh egal.",
        "Ich komme um 13 Uhr.",
        "? Was meinst du?",
        "Das ist sehr sehr gut.",
        "Ich weiß, dass das das Beste ist.",
        "Die Frau, die die Tür öffnet, ist meine Schwester.",
        "Wenn sie sie sieht, freut sie sich.",
        "Der der das sagt, lügt.",
        "Das, das ist es.",
        "Nein, ich meine das ernst.",
        "Ich meine, das ist richtig.",
        "Was ich meine, ist etwas anderes.",
        "Er meinte, ich meine es nicht ernst.",
        "Kommst du am Montag? Nein, am Dienstag.",
        "Er sagte, nein, er kommt nicht.",
        "Ich mag das nicht, nein, wirklich nicht.",
        "Ich glaube, nein, ich weiß es.",
        "Sag Anna, nein, das geht nicht.",
        "Treffen mit Anna, ich meine, mit Paul.",
        "Mein Name ist Hans, nein, nicht Hans Müller.",
        "Das ist teuer, ich meine, wirklich teuer.",
        "Ich war müde, ich meine, ich habe nicht geschlafen.",
        "Das ist teuer, ich meine, das ist zu viel.",
        "Wir können gehen, ich meine, wir müssen nicht bleiben.",
        "Ich arbeite am Montag nicht, ich meine, Montag ist mein freier Tag.",
        "Das ist für Anna, ich meine, Anna braucht das dringend.",
        "Ich komme am Montag. Ich meine, Montag ist ein guter Tag.",
        "Ich komme am Montag, ich meine, Dienstag ist besser.",
        "Wir gehen am Freitag ins Kino, ich meine, Freitag ist gut.",
        "Wir gehen um acht. Nein, um neun.",
        "Das Meeting ist morgen, nein?",
        "Ich habe drei Kinder, nein, vier Enkel.",
        "Die Zahl 3, nein, die Zahl 4 ist richtig.",
        "Um 3, nein, um 4 Uhr geht es nicht.",
        "Heute, nein, morgen wird es regnen.",
        "Morgen, nein, heute ist der Tag.",
        "Ich hab heute, nein, ich hab gestern angerufen.",
        "Am 3. Mai, nein, das war der 4. Mai.",
        "Er ist zwei, nein, er ist drei Jahre alt.",
        "Er hat 2, nein, 3 Kinder.",
        "Die Antwort ist zwei, nein, nicht drei.",
        "Kommt sie heute, nein, oder morgen?",
        "Seit Montag, nein, seit Wochen geht das so.",
        "Wir treffen uns im Mai, nein, im Juni geht es nicht.",
        "Am Montag, sorry, am Dienstag kann ich nicht.",
        "Er hat gestern, entschuldigung, gestern Abend angerufen.",
        "Sie sagte: „Am Montag, nein, am Dienstag.“",
        "Die Tür ist zu, zu spät.",
        "Was mir wichtig ist, ist Ruhe.",
        "Was es ist ist gut.",
        "Und, und dann?",
        "Immer nur ich ich ich.",
        "Ich ich bin's.",
        "Ich, ich, ich – immer geht es nur um dich.",
        "Du, du bist gemeint.",
        "Ja, ja, ich komme.",
        "Nein, nein, nein!",
        "Und und und, das hört nie auf.",
        "Bla bla bla.",
        "Wir sprechen über das Wort „ich ich“.",
        "„Und und“, sagte er.",
        "Das steht da (mit mit) doppelt.",
        "Ich komme mit mit dem Rad.",
        "Er passt auf auf das Kind.",
        "Aber aber, wer wird denn weinen?",
        "Er schaltet ein ein Gerät nach dem anderen.",
        "Wenn wenn das Wörtchen wenn nicht wär.",
        "Das kostet zwei, nein, drei Euro.",
        "Ich ruf dich heute, nein, morgen an.",
        "Er wurde am 3. Mai, nein, am 4. Mai geboren.",
        "Wählen Sie 1, nein, 2 oder 3.",
        "Zwölf, nein, zwölf Uhr.",
        "Er hat gesagt, dass dass nicht geht.",
        "Ich komme nicht am Montag, nein, am Dienstag.",
        "Nicht heute, nein, morgen.",
        "Ich habe keine Zeit am Montag, ich meine, Dienstag.",
        "Er kommt nie am Freitag, sorry, am Samstag.",
        "Ich bringe dem einen einen Kaffee und dem anderen einen Tee.",
        "Ich sah, wie die eine eine Tasche trug.",
        "Ich habe einen einen Hund.",
        "Ich suche Noten für Für Elise.",
        "Und und dann gehen wir.",
        "Weil weil er krank ist.",
        "Er kommt morgen.\r\n\r\nSie bleibt hier.",
        "Er kommt morgen.\u{2028}Sie bleibt hier.",
        "Weil, weil er krank ist.",
        "Die Familie Freitag, nein, die Familie Samstag.",
        "Er sagte ja.",
        "Sie wohnt in Öhringen.",
        "Mit Ach und Krach.",
        "Er zählte: eins, zwei, drei, vier.",
        "Er kommt morgen.\nSie bleibt hier.",
        "Die Sitzung ist heute.\n\nMorgen fahre ich weg.",
    ]

    func testSwitchOffDeliversHexPolishedForTheCorpus() async throws {
        let suite = "spoken.cleanup.off.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        settings.chooseDictationLanguage(.german)
        settings.dictationSpokenCleanup = false
        let asr = SpokenASR()
        let controller = DictationController(audio: SpokenAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
            transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false,
            customVocabularySettings: CustomVocabularySettings(defaults: defaults), languageSettings: settings)
        controller.prepareModel()
        try await waitForState("model ready") { controller.phase == .ready }
        var delivered: [String] = []
        let corpus = SpokenCleanupTests.germanCleanups.map(\.0) + SpokenCleanupTests.germanProse
        for (index, spoken) in corpus.enumerated() {
            await asr.say(spoken)
            controller.startRecording(keyboardJobID: "off-\(index)", styleOverride: .polished, copyToPasteboard: false)
            try await waitForState("recording \(index)") { controller.phase == .recording }
            controller.finishRecording()
            try await waitForState("delivered \(index)") { controller.isIdleForTest }
            delivered.append(controller.transcript)
        }
        XCTAssertEqual(delivered, Self.hexPolishedWithoutCleanup)
    }
}

/// Typr fixes on the Hex base: defects Hex's `TranscriptFormatter` (0c1c13d7) has too.
final class TranscriptFormatterTyprFixTests: XCTestCase {
    private func polished(_ text: String, _ language: String) -> String {
        TranscriptFormatter.format(text, style: .polished, language: language)
    }

    func testFillerEndingASentenceTakesItsCommaAlong() {
        XCTAssertEqual(polished("Danke, äh. Bis dann.", "de-DE"), "Danke. Bis dann.")
        XCTAssertEqual(polished("Ich weiß nicht, ähm.", "de-DE"), "Ich weiß nicht.")
        XCTAssertEqual(polished("Ich weiß nicht, ähm", "de-DE"), "Ich weiß nicht.")
        XCTAssertEqual(polished("Kommst du, äh?", "de-DE"), "Kommst du?")
        XCTAssertEqual(polished("Danke, äh, bis dann.", "de-DE"), "Danke, bis dann.")
        XCTAssertEqual(polished("Thanks, um. See you.", "en-US"), "Thanks. See you.")
        XCTAssertEqual(polished("I don't know, uh", "en-US"), "I don't know.")
        XCTAssertEqual(polished("Thanks, um, see you.", "en-US"), "Thanks, see you.")
        XCTAssertEqual(polished("Hallo Anna,\nähm\nbis morgen.", "de-DE"), "Hallo Anna,\nBis morgen.")
        XCTAssertEqual(polished("Hallo Anna,\nähm, bis morgen.", "de-DE"), "Hallo Anna,\nBis morgen.")
        XCTAssertEqual(polished("Hi Sarah,\num", "en-US"), "Hi Sarah,")
        XCTAssertEqual(polished("Hi Sarah,\num\nsee you.", "en-US"), "Hi Sarah,\nSee you.")
    }

    func testNoFullStopAfterAClosingQuoteThatFollowsASentenceMark() {
        XCTAssertEqual(polished("Sie sagte: „Bis Dienstag.“", "de-DE"), "Sie sagte: „Bis Dienstag.“")
        XCTAssertEqual(polished("Sie fragte: „Kommst du?“", "de-DE"), "Sie fragte: „Kommst du?“")
        XCTAssertEqual(polished("Er sagte „Hallo“", "de-DE"), "Er sagte „Hallo“.")
        XCTAssertEqual(polished("She said “See you.”", "en-US"), "She said “See you.”")
        XCTAssertEqual(polished("She said ‘go!’", "en-US"), "She said ‘go!’")
    }

    func testWindowsLineBreaksGetNoStrayFullStops() {
        XCTAssertEqual(polished("Er kommt morgen.\r\n\r\nSie bleibt hier", "de-DE"), "Er kommt morgen.\r\n\r\nSie bleibt hier.")
        XCTAssertEqual(polished("See you tomorrow\r\nBye", "en-US"), "See you tomorrow.\r\nBye.")
    }
}

@MainActor
private final class StubAppleCleaner: TranscriptCleaning {
    var isAvailable = true
    var supportedLanguage: String? = "de"
    var answer: String? = "Am Donnerstag"
    private(set) var inputs: [String] = []

    func supports(language: String) -> Bool { language == supportedLanguage }

    func clean(_ text: String) async -> String? {
        inputs.append(text)
        return answer
    }
}

@MainActor
final class AppleIntelligenceDictationTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: TyprSettings!

    override func setUp() async throws {
        suite = "apple.intelligence.dictation.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = TyprSettings(defaults: defaults)
        settings.chooseDictationLanguage(.german)
        settings.dictationSpokenCleanup = false
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func deliver(using apple: StubAppleCleaner, typrModel: CleanupTestSession = CleanupTestSession(),
                         style: DictationStyle = .polished) async throws -> String {
        let settings = settings!
        let cleanup = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: typrModel),
            background: CleanupTestBackground(), isEnabled: { settings.aiCleanup })
        let asr = SpokenASR()
        let controller = DictationController(audio: SpokenAudio(), keyboardBridge: KeyboardBridge(defaults: defaults),
            transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false,
            customVocabularySettings: CustomVocabularySettings(defaults: defaults), cleanup: cleanup,
            appleIntelligenceCleaner: apple, transcriptionBackground: CleanupTestBackground(), languageSettings: settings)
        controller.prepareModel()
        try await waitForState("model ready") { controller.phase == .ready }
        controller.startRecording(keyboardJobID: "job", styleOverride: style, copyToPasteboard: false)
        try await waitForState("recording") { controller.phase == .recording }
        controller.finishRecording()
        try await waitForState("delivered") { controller.isIdleForTest }
        return controller.transcript
    }

    func testExperimentRunsAfterExistingSpokenCleanupAndSkipsVerbatim() async throws {
        let apple = StubAppleCleaner()
        let disabled = try await deliver(using: apple)
        XCTAssertEqual(disabled, "Am Dienstag, ich meine, Mittwoch.")
        XCTAssertTrue(apple.inputs.isEmpty)

        settings[experiment: .appleIntelligenceCleanup] = true
        settings.dictationSpokenCleanup = true
        let enabled = try await deliver(using: apple)
        XCTAssertEqual(enabled, "Am Donnerstag.")
        XCTAssertEqual(apple.inputs, ["Am Dienstag, ich meine, Mittwoch"])

        let verbatim = try await deliver(using: apple, style: .verbatim)
        XCTAssertEqual(verbatim, "Am Dienstag, äh, ich meine, Mittwoch")
        XCTAssertEqual(apple.inputs, ["Am Dienstag, ich meine, Mittwoch"])
    }

    func testExperimentKeepsTheTextIfTheModelCannotCleanIt() async throws {
        let apple = StubAppleCleaner()
        let typrModel = CleanupTestSession()
        settings[experiment: .appleIntelligenceCleanup] = true
        settings.dictationSpokenCleanup = true
        settings.aiCleanup = true

        apple.isAvailable = false
        let unavailable = try await deliver(using: apple, typrModel: typrModel)
        XCTAssertEqual(unavailable, "Am Dienstag, ich meine, Mittwoch.")
        XCTAssertTrue(apple.inputs.isEmpty)

        apple.isAvailable = true
        apple.supportedLanguage = "en"
        let unsupported = try await deliver(using: apple, typrModel: typrModel)
        XCTAssertEqual(unsupported, "Am Dienstag, ich meine, Mittwoch.")
        XCTAssertTrue(apple.inputs.isEmpty)

        apple.supportedLanguage = "de"
        apple.answer = nil
        let noAnswer = try await deliver(using: apple, typrModel: typrModel)
        XCTAssertEqual(noAnswer, "Am Dienstag, ich meine, Mittwoch.")
        XCTAssertEqual(apple.inputs, ["Am Dienstag, ich meine, Mittwoch"])
        XCTAssertEqual(typrModel.prepareCount, 0)
        XCTAssertEqual(typrModel.cleanCount, 0)

        settings[experiment: .appleIntelligenceCleanup] = false
        typrModel.result = "Am Freitag"
        let restored = try await deliver(using: apple, typrModel: typrModel)
        XCTAssertEqual(restored, "Am Freitag.")
        XCTAssertEqual(apple.inputs, ["Am Dienstag, ich meine, Mittwoch"])
        XCTAssertEqual(typrModel.cleanCount, 1)
        XCTAssertTrue(settings.aiCleanup)
    }
}
