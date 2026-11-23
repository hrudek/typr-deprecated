import XCTest
@testable import Typr

final class HexLanguageSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "HexLanguageSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToAutomaticWithoutTouchingTyprsLanguage() {
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertNil(settings.dictationLanguage)
        XCTAssertFalse(settings.dictationFollowsKeyboard)
        settings.chooseDictationLanguage("de-AT")
        XCTAssertEqual(settings.dictationLanguage, "de-AT")
        XCTAssertNil(defaults.string(forKey: "typr.dictationLanguage"))
    }

    func testChoosingAVariantReplacesTheOtherVariantInRecents() {
        let settings = LanguageSettings(defaults: defaults)
        settings.chooseDictationLanguage("es-ES")
        settings.chooseDictationLanguage("de-DE")
        settings.chooseDictationLanguage("es-US")
        XCTAssertEqual(settings.recentDictationLanguages, ["es-US", "de-DE"])
    }

    func testAutomaticFollowsTheKeyboardsCurrentLanguage() {
        let settings = LanguageSettings(defaults: defaults)
        settings.supportedDictationLanguages = ["de-DE", "de-AT", "en-US", "en-GB"]
        let keyboard = ["de-DE", "en-US"]
        XCTAssertEqual(settings.keyboardDictationLanguage(keyboard: keyboard, current: "en-US", preferred: ["en-GB", "de-AT"]), "en-GB")
        XCTAssertEqual(settings.keyboardDictationLanguage(keyboard: keyboard, current: "de-DE", preferred: ["en-GB", "de-AT"]), "de-AT")
        XCTAssertEqual(settings.keyboardDictationLanguage(keyboard: keyboard, current: "fr-FR", preferred: ["en-GB"]), "de-DE")
        XCTAssertEqual(settings.effectiveDictationLanguage(keyboard: keyboard, current: "en-US"), settings.keyboardDictationLanguage(keyboard: keyboard, current: "en-US"))
    }

    func testKeyboardIsNotFollowedWithOneLanguageOrAnExplicitChoice() {
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertNil(settings.keyboardDictationLanguage(keyboard: ["de-DE"], current: "de-DE", preferred: ["de-DE"]))
        settings.dictationLanguage = "en-US"
        XCTAssertNil(settings.keyboardDictationLanguage(keyboard: ["de-DE", "en-US"], current: "de-DE", preferred: ["de-DE"]))
        XCTAssertEqual(settings.effectiveDictationLanguage(keyboard: ["de-DE", "en-US"], current: "de-DE"), "en-US")
    }

    func testIPhoneLanguageWithoutKeyboardLayoutIsKeptUnlessFollowingIsOn() {
        let settings = LanguageSettings(defaults: defaults)
        let keyboard = ["de-DE", "en-US"]
        XCTAssertNil(settings.keyboardDictationLanguage(keyboard: keyboard, current: "en-US", preferred: ["he-IL"]))
        settings.dictationFollowsKeyboard = true
        XCTAssertEqual(settings.keyboardDictationLanguage(keyboard: keyboard, current: "en-US", preferred: ["he-IL"]), "en-US")
    }

    func testIPhoneLanguageWithAHexLayoutFollowsTheKeyboard() {
        let settings = LanguageSettings(defaults: defaults)
        settings.supportedDictationLanguages = ["de-DE", "en-US"]
        XCTAssertEqual(settings.keyboardDictationLanguage(keyboard: ["de-DE", "en-US"], current: "en-US", preferred: ["fr-FR"]), "en-US")
        XCTAssertTrue(LanguageSettings.hexHasLayout("sr-Latn-RS"))
        XCTAssertFalse(LanguageSettings.hexHasLayout("sr-Cyrl-RS"))
        XCTAssertFalse(LanguageSettings.hexHasLayout("ko-KR"))
    }

    func testCanadianAndSwissFrenchKeepTheirOwnRegion() {
        let settings = LanguageSettings(defaults: defaults)
        settings.supportedDictationLanguages = ["fr-FR", "fr-CA", "fr-CH"]
        XCTAssertEqual(settings.dictationLanguage(forKeyboard: "fr-CA", preferred: ["fr-FR"]), "fr-CA")
        XCTAssertEqual(settings.dictationLanguage(forKeyboard: "fr-CH", preferred: ["fr-FR"]), "fr-CH")
        XCTAssertEqual(settings.dictationLanguage(forKeyboard: "fr-FR", preferred: ["fr-CA"]), "fr-CA")
        settings.supportedDictationLanguages = ["fr-FR"]
        XCTAssertNil(settings.dictationLanguage(forKeyboard: "fr-CA", preferred: ["fr-FR"]))
    }

    func testSerbianDictatesNothingBeforeSpeechListsItsLanguages() {
        XCTAssertNil(LanguageSettings(defaults: defaults).dictationLanguage(forKeyboard: "sr-Latn-RS", preferred: []))
    }

    func testKeyboardLanguageApplesSpeechLacksDictatesNothing() {
        let settings = LanguageSettings(defaults: defaults)
        settings.supportedDictationLanguages = ["en-US", "de-DE"]
        XCTAssertNil(settings.dictationLanguage(forKeyboard: "sr-Latn-RS", preferred: []))
    }

    func testExplicitLanguageUsesSpeechThenDictationModule() async {
        let picked = await SpeechLanguagePicker.pick(
            explicit: "nb-NO",
            candidates: ["en-US"],
            speech: { $0.identifier(.bcp47) == "en-US" ? $0 : nil },
            dictation: { $0.identifier(.bcp47) == "nb-NO" ? $0 : nil }
        )
        XCTAssertEqual(picked?.identifier, "nb-NO")
        XCTAssertEqual(picked?.module, .dictation)
    }

    func testUnsupportedExplicitLanguageFallsBackToAutomaticCandidates() async {
        let candidates = SpeechLanguagePicker.automaticCandidates(preferred: ["de-DE"], current: "de_DE")
        XCTAssertEqual(candidates, ["de-DE", "en-US"])
        let picked = await SpeechLanguagePicker.pick(
            explicit: "xx-XX",
            candidates: candidates,
            speech: { ["de-DE", "en-US"].contains($0.identifier(.bcp47)) ? $0 : nil },
            dictation: { _ in nil }
        )
        XCTAssertEqual(picked?.identifier, "de-DE")
        XCTAssertEqual(picked?.module, .speech)
    }

    func testNoSupportedLanguageResolvesToNil() async {
        let picked = await SpeechLanguagePicker.pick(
            explicit: "xx-XX",
            candidates: ["yy-YY"],
            speech: { _ in nil },
            dictation: { _ in nil }
        )
        XCTAssertNil(picked)
    }

    func testAutomaticSkipsSetAsideLanguageButNeverGivesUpOnTheOnlyOne() async {
        let speech: (Locale) async -> Locale? = { ["de-DE", "en-US"].contains($0.identifier(.bcp47)) ? $0 : nil }
        let skipGerman = await SpeechLanguagePicker.pick(
            explicit: nil, candidates: ["de-DE", "en-US"], speech: speech, dictation: { _ in nil },
            skip: { $0.identifier(.bcp47) == "de-DE" }
        )
        XCTAssertEqual(skipGerman?.identifier, "en-US")
        let skipAll = await SpeechLanguagePicker.pick(
            explicit: nil, candidates: ["de-DE", "en-US"], speech: speech, dictation: { _ in nil },
            skip: { _ in true }
        )
        XCTAssertEqual(skipAll?.identifier, "de-DE")
    }

    func testSpeechModuleFailureSetsALanguageAsideOnTheSecondStrike() {
        let settings = LanguageSettings(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        settings.noteSpeechModuleFailure("de-DE", at: now)
        XCTAssertFalse(settings.speechModuleFailed("de-DE", now: now))
        settings.noteSpeechModuleFailure("de-DE", at: now)
        XCTAssertTrue(settings.speechModuleFailed("de-DE", now: now))
        XCTAssertFalse(settings.speechModuleFailed("de-DE", now: now + LanguageSettings.setAsideDuration))
    }

    func testSpanishFollowsTheIPhonesRegion() {
        XCTAssertEqual(DictationLanguageSwitch.spanishCandidates(for: "es", region: "MX"), ["es-MX", "es-US", "es-ES"])
        XCTAssertEqual(DictationLanguageSwitch.supportedMatch(for: "es-AR", in: ["es-ES", "es-US"]), "es-US")
        XCTAssertEqual(DictationLanguageSwitch.supportedMatch(for: "nn-NO", in: ["nb-NO", "en-US"]), "nb-NO")
    }
}

extension TyprSettings {
    /// Settings › Language's choice, into the store the switch selects.
    func chooseDictationLanguage(_ language: DictationLanguage) {
        hexLanguage.chooseTyprDictationLanguage(language, typr: self)
    }
}

final class TyprDictationLanguageTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "TyprDictationLanguageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testGermanOrEnglishFromAnIdentifier() {
        XCTAssertEqual(DictationLanguage(identifier: "de-AT"), .german)
        XCTAssertEqual(DictationLanguage(identifier: "en-GB"), .english)
        XCTAssertEqual(DictationLanguage(identifier: "fr-FR"), .automatic)
        XCTAssertEqual(DictationLanguage(identifier: nil), .automatic)
    }

    func testTheChoiceIsHexsSettingAndAutomaticFollowsTheKeyboard() {
        let typr = TyprSettings(defaults: defaults)
        let settings = typr.hexLanguage
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .automatic)
        settings.keyboardLanguages = [.german, .english]
        settings.currentKeyboardLanguage = .english
        XCTAssertEqual(settings.typrDictationChoice(typr: typr), .automatic)
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .english)
        settings.currentKeyboardLanguage = .german
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .german)

        typr.chooseDictationLanguage(.english)
        XCTAssertEqual(settings.dictationLanguage, "en-US")
        XCTAssertEqual(typr.dictationLanguage, .automatic, "Typr's own choice is left alone")
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .english, "a language picked by hand stays")
    }

    func testOneKeyboardLanguageLeavesAutomatic() {
        let typr = TyprSettings(defaults: defaults)
        typr.hexLanguage.keyboardLanguages = [.german]
        typr.hexLanguage.currentKeyboardLanguage = .german
        XCTAssertEqual(typr.hexLanguage.typrDictationLanguage(typr: typr), .automatic)
    }

    func testTyprFixedDictationLanguageUsesTyprsChoiceOnly() {
        let typr = TyprSettings(defaults: defaults)
        let settings = typr.hexLanguage
        settings.keyboardLanguages = [.german, .english]
        settings.currentKeyboardLanguage = .english
        settings.dictationLanguage = "fr-FR"
        typr[experiment: .typrFixedDictationLanguage] = true
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .automatic, "doesn't follow the keyboard")
        XCTAssertNil(settings.explicitDictationLanguage(typr: .automatic))
        typr.chooseDictationLanguage(.german)
        XCTAssertEqual(typr.dictationLanguage, .german)
        XCTAssertEqual(settings.dictationLanguage, "fr-FR", "Hex's setting is left alone")
        XCTAssertEqual(settings.typrDictationLanguage(typr: typr), .german)
    }
}
