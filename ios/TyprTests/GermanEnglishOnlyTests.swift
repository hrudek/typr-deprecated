import UIKit
import XCTest
@testable import Typr

/// Typr offers German and English only: every language Settings and the keyboard menus offer is
/// one of the two, and another language stored before is read as the German or English default
/// without being rewritten.
@MainActor
final class GermanEnglishOnlyTests: XCTestCase {
    private let offered: Set<String> = ["de", "en"]

    private func isolatedDefaults() -> UserDefaults {
        let suite = "german-english-only.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    private func codes(_ identifiers: [String]) -> Set<String> {
        Set(identifiers.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 })
    }

    func testKeyboardLanguagesPageOffersGermanAndEnglish() {
        XCTAssertEqual(KeyboardLanguage.selectable(), [.german, .english])
        let onPhone = KeyboardLanguagesPage.onThisIPhone(
            inputModes: ["fr-FR", "ko-KR", "en-GB", "emoji"],
            preferred: ["es-ES", "nb-NO", "de-DE", "el-GR"]
        )
        XCTAssertEqual(onPhone, [.english, .german])
    }

    func testLayoutRowsOfferGermanAndEnglish() {
        let defaults = isolatedDefaults()
        defaults.set(["fr", "es", "ko"], forKey: "settings.keyboardLanguages")
        let settings = LanguageSettings(defaults: defaults)
        settings.dictationLanguage = "fr-FR"
        let automatic = automaticKeyboardLanguage(settings: settings)
        XCTAssertEqual(automatic, .english)
        let arranged = KeyboardLanguagesPage.arranged(chosen: settings.keyboardLanguages, automatic: automatic)
        XCTAssertTrue(Set(arranged).isSubset(of: KeyboardLanguage.selectable()), "\(arranged)")
        XCTAssertFalse(arranged.isEmpty)
    }

    func testStoredOtherKeyboardLanguagesReadAsGermanOrEnglishWithoutRewriting() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: KoreanKeyboardExperiment.key)
        defaults.set(["fr", "ko", "de", "nb"], forKey: "settings.keyboardLanguages")
        defaults.set("ko", forKey: "settings.keyboardLanguages.current")
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.keyboardLanguages, [.german])
        XCTAssertNil(settings.currentKeyboardLanguage)
        XCTAssertEqual(defaults.stringArray(forKey: "settings.keyboardLanguages"), ["fr", "ko", "de", "nb"])
        XCTAssertEqual(defaults.string(forKey: "settings.keyboardLanguages.current"), "ko")

        defaults.set(["es", "ko"], forKey: "settings.keyboardLanguages")
        XCTAssertEqual(settings.keyboardLanguages, [], "nothing offered left: Automatic")
    }

    func testTheKeyboardTypesGermanOrEnglishWithAnotherLanguageStored() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: KoreanKeyboardExperiment.key)
        defaults.set(["ko", "fr"], forKey: "settings.keyboardLanguages")
        let settings = LanguageSettings(defaults: defaults)
        settings.dictationLanguage = "fr-FR"
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(text: ""), defaults: defaults)
        view.languageSettings = settings
        XCTAssertEqual(view.languages, KeyboardLanguageList(languages: [.english], current: .english))

        settings.dictationLanguage = "de-AT"
        view.languageSettings = settings
        XCTAssertEqual(view.languages, KeyboardLanguageList(languages: [.german], current: .german))
    }

    func testDictationAndTranslationOfferGermanAndEnglish() {
        XCTAssertEqual(DictationLanguage.allCases, [.automatic, .german, .english])
        XCTAssertEqual(codes(LanguageSettings.typrDictationLanguages), offered)
        for other in ["es-ES", "nb-NO", "fr-FR", "ko-KR"] {
            XCTAssertEqual(DictationLanguage(identifier: other), .automatic, other)
        }
        let translation = DictationTranslationSettings(defaults: isolatedDefaults())
        translation.targetLanguage = "fr"
        XCTAssertEqual(translation.targetLanguage, "en")
    }

    func testExperimentsOfferNoOtherLanguage() {
        XCTAssertFalse(ExperimentalSwitch.all.map(\.key).contains(KoreanKeyboardExperiment.key))
    }
}
