import XCTest
@testable import Typr

final class TwoLanguageDictationTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "TwoLanguageDictationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testIsAHexExperimentOffByDefaultUnderHexsKey() {
        XCTAssertEqual(TwoLanguageDictationSettings.enabledKey, "experiments.twoLanguageDictation")
        XCTAssertTrue(ExperimentalSwitch.hexExperiments.contains(.twoLanguageDictation))
        XCTAssertFalse(ExperimentalSwitch.typrVariants.contains(.twoLanguageDictation))
        let settings = TwoLanguageDictationSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        TyprSettings(defaults: defaults)[experiment: .twoLanguageDictation] = true
        XCTAssertTrue(settings.isEnabled, "the Experimental toggle and dictation read the same key")
    }

    @available(iOS 26.0, *)
    func testTheSecondLanguageIsTheOtherOfGermanAndEnglish() {
        let settings = LanguageSettings(defaults: defaults)
        settings.supportedDictationLanguages = ["de-DE", "de-AT", "en-US", "en-GB", "fr-FR"]
        XCTAssertEqual(
            DictationLanguage(identifier: AppleSpeechTwoLanguage.secondaryLanguage(forPrimary: "de", settings: settings)),
            .english
        )
        XCTAssertEqual(
            DictationLanguage(identifier: AppleSpeechTwoLanguage.secondaryLanguage(forPrimary: "en", settings: settings)),
            .german
        )
        for other in ["fr", "es", "ko", ""] {
            XCTAssertNil(AppleSpeechTwoLanguage.secondaryLanguage(forPrimary: other, settings: settings), other)
        }
    }

    func testKeyboardDictatesItselfInOneLanguageWithTheExperimentOn() {
        TwoLanguageDictationSettings(defaults: defaults).isEnabled = true
        XCTAssertTrue(KeyboardDictationRoute.keyboardAllowed(
            fullAccess: true,
            settings: TyprSettings(defaults: defaults),
            multilingual: MultilingualParakeetSettings(defaults: defaults)
        ))
        XCTAssertTrue(ExperimentalSwitch.twoLanguageDictation.detail.contains("Keyboard dictation stays in one language"))
    }
}
