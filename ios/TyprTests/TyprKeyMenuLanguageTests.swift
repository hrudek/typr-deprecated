import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprKeyMenuLanguageTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "typr-key-menu.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    private func rows(of view: UIView) -> [UIControl] {
        view.subviews.flatMap { subview -> [UIControl] in
            let own = (subview as? UIControl).flatMap { $0.isAccessibilityElement ? [$0] : nil } ?? []
            return own + rows(of: subview)
        }
    }

    private func row(_ title: String, in menu: HexStyleMenuView) -> UIControl? {
        rows(of: menu).first { $0.accessibilityLabel?.hasPrefix(title) == true }
    }

    private func languageMenu(removes: Bool) -> HexStyleMenuView {
        let menu = HexStyleMenuView(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        if removes { menu.onRemoveLanguage = { _ in } }
        menu.dictationLanguage = nil
        menu.automaticLanguage = "de-DE"
        menu.languageChoices = LanguageSettings.typrDictationLanguages
        menu.show(page: .languages)
        menu.layoutIfNeeded()
        return menu
    }

    func testTheLanguagePageOffersAutomaticGermanAndEnglishWithoutRemove() throws {
        let menu = languageMenu(removes: false)
        XCTAssertNotNil(row("Automatic", in: menu))
        let names = DictationLanguageSwitch.nativeNames(for: LanguageSettings.typrDictationLanguages, supported: [])
        for id in LanguageSettings.typrDictationLanguages {
            let language = try XCTUnwrap(row(try XCTUnwrap(names[id]), in: menu), id)
            XCTAssertTrue(language.accessibilityCustomActions?.isEmpty ?? true, "\(id): no Remove action")
            XCTAssertFalse(language.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } ?? false,
                           "\(id): a long press offers no Remove")
        }
        XCTAssertNil(row("More languages", in: menu))
    }

    func testRemoveIsOfferedWithAHandler() throws {
        let menu = languageMenu(removes: true)
        let name = try XCTUnwrap(DictationLanguageSwitch.nativeNames(for: ["de-DE"], supported: [])["de-DE"])
        let german = try XCTUnwrap(row(name, in: menu))
        XCTAssertEqual(german.accessibilityCustomActions?.map(\.name), ["Remove"])
        XCTAssertTrue(german.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } ?? false)
    }

    func testTheStylesPageOffersTranslateToTheTarget() {
        let menu = HexStyleMenuView(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        menu.languageChoices = LanguageSettings.typrDictationLanguages
        menu.translationTarget = "de"
        menu.translationTargets = ["de", "en"]
        menu.show(page: .styles)
        menu.layoutIfNeeded()
        XCTAssertNotNil(row("Translate to", in: menu))
        menu.translationTarget = nil
        menu.layoutIfNeeded()
        XCTAssertNil(row("Translate to", in: menu), "no target, no Translate row")
    }

    private func switchingKeyboard(fixed: Bool) -> [String?] {
        let defaults = isolatedDefaults()
        let settings = LanguageSettings(defaults: defaults)
        settings.keyboardLanguages = [.german, .english]
        settings.currentKeyboardLanguage = .german
        settings.dictationFollowsKeyboard = true
        settings.dictationLanguage = "de-DE"
        TyprSettings(defaults: defaults)[experiment: .typrFixedDictationLanguage] = fixed
        let model = KeyboardViewModel()
        model.hasFullAccess = true
        var selected: [String?] = []
        model.onLanguageSelected = { selected.append($0) }
        let view = FullKeyboardView(model: model, target: HexFixtureTextTarget(text: ""), defaults: defaults)
        view.languageSettings = settings
        view.switchLanguage(by: 1)
        XCTAssertEqual(settings.currentKeyboardLanguage, .english, "the keyboard switched")
        return selected
    }

    func testTheSpaceBarMovesAHandPickedLanguageBackToAutomatic() {
        XCTAssertEqual(switchingKeyboard(fixed: false), [nil])
    }

    func testTheSpaceBarLeavesTyprsFixedLanguageAlone() {
        XCTAssertEqual(switchingKeyboard(fixed: true), [])
    }
}
