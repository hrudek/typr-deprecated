import SwiftUI
import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardSettingsHubTests: XCTestCase {
    func testTypingSceneOpensTheKeyboardPageWithTheSwipeNotice() {
        XCTAssertEqual(SettingsDestination.snapshotDestination(arguments: ["Typr", "--snap-state", "settings-keyboard-typing"]),
                       .keyboard)
        XCTAssertEqual(KeyboardSettingsCard.swipeNotice, "Swipe typing powered by FUTO Swipe.")
    }

    func testHubShowsTypingAssistanceWithoutAFullKeyboardSwitch() async throws {
        let suite = "typr.tests.keyboard-hub.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "experiments.fullKeyboard")
        let stored = defaults.persistentDomain(forName: suite) as NSDictionary?

        let switches = try await mountedSwitches(KeyboardSettingsCard(defaults: defaults), count: 8)
        XCTAssertEqual(switches.map(\.isOn), [true, true, true, false, true, true, true, true],
                       "Hex's keyboard: Auto-capitalization, Autocorrect, Spatial autocorrect, Suggest swear words, Swipe typing, Key pop-ups, Haptics, Emoji")
        XCTAssertTrue(switches.allSatisfy(\.isEnabled), "a retired Full keyboard value disables nothing")
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, stored, "opening the page writes nothing")
    }

    func testTyprKeyboardShowsTyprsTypingAssistance() async throws {
        let suite = "typr.tests.keyboard-hub.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        TyprSettings(defaults: defaults)[experiment: .typrKeyboard] = true

        let switches = try await mountedSwitches(KeyboardSettingsCard(defaults: defaults), count: 3)
        XCTAssertEqual(switches.map(\.isOn), [true, false, true], "Autocorrect, Suggest swear words, Swipe typing")
    }

    func testWordsAndPrivacyHoldsLearningAndBothImports() async throws {
        let suite = "typr.tests.keyboard-hub.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        TyprSettings(defaults: defaults)[experiment: .typrKeyboard] = true
        let switches = try await mountedSwitches(KeyboardWordsPrivacyCard(defaults: defaults), count: 3)
        XCTAssertEqual(switches.map(\.isOn), [TyprSettings(defaults: defaults).personalLearning,
                                              PersonalLexiconImporter.shared.contactsEnabled,
                                              PersonalLexiconImporter.shared.vocabularyEnabled],
                       "Learn from my typing, Import contacts, Import dictation words")
        XCTAssertTrue(switches.allSatisfy(\.isEnabled))
    }

    func testWordsAndPrivacyLeadsWithHexLearningOnTheHexKeyboard() async throws {
        let suite = "typr.tests.keyboard-hub.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        TypingJournalSettings(defaults: defaults).isEnabled = false
        TyprSettings(defaults: defaults).personalLearning = true
        let switches = try await mountedSwitches(KeyboardWordsPrivacyCard(defaults: defaults), count: 4)
        XCTAssertEqual(switches.map(\.isOn), [false, true,
                                              PersonalLexiconImporter.shared.contactsEnabled,
                                              PersonalLexiconImporter.shared.vocabularyEnabled],
                       "Learn how I type, Learn from my typing, Import contacts, Import dictation words")
    }

    func testDeleteImportedWordsAsksForConfirmation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: PersonalLexiconSettingsCard(confirmDelete: true))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitForState("the confirmation is presented") { host.presentedViewController != nil }
        let texts = Self.texts(in: try XCTUnwrap(host.presentedViewController))
        for text in [PersonalLexiconSettingsCard.deleteTitle, PersonalLexiconSettingsCard.deleteMessage,
                     "Delete imported words", "Cancel"] {
            XCTAssertTrue(texts.contains(text), "\(text) missing from \(texts)")
        }
    }

    private func mountedSwitches(_ page: some View, count: Int) async throws -> [UISwitch] {
        let host = UIHostingController(rootView: NavigationStack { ScrollView { page } })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 2_400))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitForState("the page shows \(count) switches") {
            host.view.layoutIfNeeded()
            return Self.subviews(of: host.view).filter { $0 is UISwitch }.count == count
        }
        return Self.subviews(of: host.view).compactMap { $0 as? UISwitch }
            .sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
    }

    private static func texts(in controller: UIViewController) -> [String] {
        if let alert = controller as? UIAlertController {
            return [alert.title, alert.message].compactMap { $0 } + alert.actions.compactMap(\.title)
        }
        return subviews(of: controller.view).compactMap { ($0 as? UILabel)?.text }
    }

    private static func subviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(subviews(of:))
    }
}
