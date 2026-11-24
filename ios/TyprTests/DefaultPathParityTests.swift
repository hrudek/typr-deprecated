import UIKit
import XCTest
@testable import Typr

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

    func testTheKeyboardIsHexsViewWithHexsAutocorrect() {
        let settings = TyprSettings(defaults: defaults)
        let surface = KeyboardSurfaceChoice.surface(
            isPhone: true, compactChosen: KeyboardSurfaceChoice(defaults: defaults).showsCompactBar, settings: settings
        )
        XCTAssertEqual(surface, .hex)

        let backend = FullKeyboardView.typrTypingBackend(settings) {
            XCTFail("no Typr engine is built")
            return TyprAutocorrectEngine(learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        }
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(), autocorrect: backend, defaults: defaults)
        XCTAssertTrue(view.engine.autocorrect is AutocorrectEngine)
    }

    func testKeyboardDictationRecordsInTheKeyboard() {
        XCTAssertTrue(KeyboardDictationRoute.keyboardAllowed(
            fullAccess: true, settings: TyprSettings(defaults: defaults), multilingual: MultilingualParakeetSettings(defaults: defaults)
        ))
    }

    func testCleanupKeepsRepairsAndRemovesHesitationsAsHexDoes() async {
        let pipeline = DictationPipeline(style: .polished, language: .german,
                                         vocabulary: DictationVocabulary(userTerms: []), settings: TyprSettings(defaults: defaults))
        let stages = await pipeline.run("Am Dienstag, äh, ich meine, Mittwoch.")
        XCTAssertEqual(stages.tagged, HexSpokenHesitations.remove(from: stages.spelled, language: pipeline.language))
        XCTAssertFalse(stages.tagged.contains("äh"))
        XCTAssertTrue(stages.tagged.contains("Dienstag"), "Typr's conservative cleanup would drop the repair")
    }

    func testVocabularyMatchesOnlyTheTermsAsHexDoes() async {
        let settings = TyprSettings(defaults: defaults)
        settings.chooseDictationLanguage(.german)
        let vocabulary = CustomVocabularySettings(defaults: defaults)
        vocabulary.isEnabled = true
        vocabulary.terms = ["herdr", "GitHub"]
        vocabulary.setSoundsLike(["Herder"], for: "herdr")
        let learning = DictationLearningStore(defaults: defaults)
        let heard = "Öffne den Herder und einen Pulrequest auf github"

        let hex = await KeyboardLocalCapture.text(from: heard, style: .verbatim, settings: settings,
                                                  vocabulary: vocabulary, learning: learning)
        XCTAssertTrue(hex.contains("den Herder und einen Pulrequest auf GitHub"), hex)
        XCTAssertEqual(DictationVocabulary(settings: vocabulary).speechHints, ["herdr", "GitHub"])

        settings[experiment: .typrVocabularyMatching] = true
        let typr = await KeyboardLocalCapture.text(from: heard, style: .verbatim, settings: settings,
                                                   vocabulary: vocabulary, learning: learning)
        XCTAssertTrue(typr.contains("den herdr und einen Pull Request auf GitHub"), typr)
    }

    func testListsFollowHexsFormatting() {
        let pipeline = DictationPipeline(style: .polished, language: .english,
                                         vocabulary: DictationVocabulary(userTerms: []), settings: TyprSettings(defaults: defaults))
        XCTAssertEqual(pipeline.format("Groceries, bullet, eggs, bullet, milk.", language: "en-US"), "Groceries:\n- Eggs.\n- Milk.")
    }

    func testTranslationUsesHexsTranslator() async throws {
        let translation = DictationTranslationSettings(defaults: defaults)
        translation.isEnabled = true
        let plan = try XCTUnwrap(DictationTranslationPlan(
            settings: translation, typrPolicy: TyprSettings(defaults: defaults)[experiment: .typrTranslationPolicy]
        ))
        let engine = TranslationEngine(status: { _, _ in .unsupported }, translate: { _, _, _ in "" })
        let outcome = await plan.translate("Bis morgen.", source: .german, settings: translation, engine: engine)
        XCTAssertEqual(outcome.failure?.reason, .unsupported, "Typr's translator reports an unsupported pair as failed")
        XCTAssertEqual(translation.lastFailure?.reason, .unsupported)
    }

    func testDictationLanguageFollowsTheKeyboard() {
        let settings = TyprSettings(defaults: defaults)
        let language = settings.hexLanguage
        language.keyboardLanguages = [.german, .english]
        language.currentKeyboardLanguage = .english
        XCTAssertEqual(language.typrDictationLanguage(typr: settings), .english)
        language.currentKeyboardLanguage = .german
        XCTAssertEqual(language.typrDictationLanguage(typr: settings), .german)
    }

    func testDictationBarAutoStartsOnlyOnSwitchBackByDefault() {
        let setting = FullKeyboardSettings(defaults: defaults).dictationBarAutoStart
        XCTAssertEqual(setting, .whenSwitching, "Hex's default")
        XCTAssertTrue(setting.startsDictation(
            onDictationBar: true, isSwitchBack: true, hasFullAccess: true, isIdle: true, route: KeyboardFieldRouting.route(for: .default)
        ))
        XCTAssertFalse(setting.startsDictation(
            onDictationBar: true, isSwitchBack: false, hasFullAccess: true, isIdle: true, route: KeyboardFieldRouting.route(for: .default)
        ))
    }

    func testDictationBarAutoStartNeedsAnIdleBarWithFullAccessOutsideHandOffFields() {
        func starts(
            _ choice: DictationBarAutoStart, bar: Bool = true, switchBack: Bool = false, access: Bool = true,
            idle: Bool = true, route: KeyboardFieldRoute = KeyboardFieldRouting.route(for: .default)
        ) -> Bool {
            choice.startsDictation(
                onDictationBar: bar, isSwitchBack: switchBack, hasFullAccess: access, isIdle: idle, route: route
            )
        }
        XCTAssertTrue(starts(.always))
        XCTAssertFalse(starts(.never, switchBack: true), "Never leaves Dictate to a tap")
        XCTAssertFalse(starts(.always, bar: false), "Never on the full keyboard")
        XCTAssertFalse(starts(.always, access: false))
        XCTAssertFalse(starts(.always, idle: false))
        XCTAssertFalse(starts(.always, route: KeyboardFieldRouting.route(for: .numberPad)))
    }
}
