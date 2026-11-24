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

    func testListsFollowHexsFormatting() {
        let pipeline = DictationPipeline(style: .polished, language: .english,
                                         vocabulary: DictationVocabulary(userTerms: []), settings: TyprSettings(defaults: defaults))
        XCTAssertEqual(pipeline.format("Groceries, bullet, eggs, bullet, milk.", language: "en-US"), "Groceries:\n- Eggs.\n- Milk.")
    }

    func testTranslationUsesHexsTranslatorAndTarget() async throws {
        let translation = DictationTranslationSettings(defaults: defaults)
        translation.isEnabled = true
        translation.targetLanguage = "ja"
        let plan = try XCTUnwrap(DictationTranslationPlan(
            settings: translation, typrPolicy: TyprSettings(defaults: defaults)[experiment: .typrTranslationPolicy]
        ))
        let recorder = TargetRecorder()
        let engine = TranslationEngine(
            status: { _, _ in .installed },
            translate: { _, _, target in
                recorder.targets.append(target.minimalIdentifier)
                return "またね。"
            }
        )
        let outcome = await plan.translate("Bis morgen.", source: .german, settings: translation, engine: engine)
        XCTAssertEqual(recorder.targets, ["ja"], "Typr's translator would translate into English")
        XCTAssertEqual(outcome, .translated("またね。"))
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
}

@MainActor
private final class TargetRecorder {
    var targets: [String] = []
}
