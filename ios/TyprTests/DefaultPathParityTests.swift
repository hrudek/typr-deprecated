import XCTest
@testable import Typr

/// With every Typr variant off, each area takes Hex's path. The controller-level parts (audio
/// session, Live Activity, host return) are pinned in DictationAudioSessionTests and
/// DictationControllerTests (`testHexDefaultSessionMixes…`, `testOnlyCopyingDictationsShowALiveActivity`,
/// `testHexDefaultNeverOpensTheHostAfterAColdStart`).
@MainActor
final class DefaultPathParityTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "DefaultPathParityTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testEveryTyprVariantIsOffAndEveryTyprOverrideIsListed() {
        let settings = TyprSettings(defaults: defaults)
        for variant in ExperimentalSwitch.typrVariants {
            XCTAssertFalse(settings[experiment: variant], variant.key)
        }
        for item in ExperimentalSwitch.hexExperiments + ExperimentalSwitch.hexKeyboardExperiments {
            XCTAssertFalse(settings[experiment: item], "Hex's default: \(item.key)")
        }
        let listed = Set(ExperimentalSwitch.typrVariants)
        for override in ExperimentalSwitch.typrOverrides {
            XCTAssertTrue(listed.contains(override), "\(override.key) is reachable in Settings")
        }
    }

    func testWithAllTyprVariantsOffEachAreaTakesHexsPath() {
        let settings = TyprSettings(defaults: defaults)
        for variant in ExperimentalSwitch.typrVariants { settings[experiment: variant] = false }

        XCTAssertTrue(KeyboardSurfaceChoice.wantsFullKeyboard(
            isPhone: true, compactChosen: KeyboardSurfaceChoice(defaults: defaults).showsCompactBar
        ), "keyboard view: Hex's full keyboard")
        XCTAssertFalse(settings[experiment: .typrKeyboard], "keyboard view: not Typr's keyboard")

        XCTAssertNil(FullKeyboardView.typrTypingBackend(settings) {
            XCTFail("engine: Hex's autocorrect, no Typr engine built")
            return TyprAutocorrectEngine(learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        })

        XCTAssertTrue(KeyboardDictationRoute.keyboardAllowed(
            fullAccess: true, settings: settings, multilingual: MultilingualParakeetSettings(defaults: defaults)
        ), "handoff: Hex's in-keyboard dictation")

        let pipeline = DictationPipeline(style: .polished, language: .german,
                                         vocabulary: DictationVocabulary(userTerms: []), settings: settings)
        XCTAssertFalse(pipeline.typrFormattingRules, "formatting: Hex's lists and punctuation")
        XCTAssertFalse(pipeline.typrSpokenCleanup, "cleanup: Hex's hesitation rule")
        XCTAssertTrue(pipeline.spokenCleanup, "Clean up what I say: on, as in Hex")
        XCTAssertTrue(pipeline.formatLists)
        XCTAssertTrue(pipeline.spokenPunctuation)
        XCTAssertTrue(pipeline.endsWithPeriod)
        XCTAssertFalse(pipeline.lowercase)
        XCTAssertFalse(settings[experiment: .appleIntelligenceCleanup], "Apple Intelligence cleanup: off, as in Hex")
        XCTAssertFalse(settings.aiCleanup, "Typr's AI cleanup is opt-in")

        let translation = DictationTranslationSettings(defaults: defaults)
        XCTAssertNil(DictationTranslationPlan(settings: translation, typrPolicy: settings[experiment: .typrTranslationPolicy]))
        translation.isEnabled = true
        let plan = DictationTranslationPlan(settings: translation, typrPolicy: settings[experiment: .typrTranslationPolicy])
        XCTAssertEqual(plan?.typrPolicy, false, "translation: Hex's translator")

        let language = settings.hexLanguage
        language.keyboardLanguages = [.german, .english]
        language.currentKeyboardLanguage = .english
        XCTAssertEqual(language.typrDictationLanguage(typr: settings), .english, "language: follows the keyboard")
        language.currentKeyboardLanguage = .german
        XCTAssertEqual(language.typrDictationLanguage(typr: settings), .german)
    }
}
