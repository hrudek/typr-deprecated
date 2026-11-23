import SwiftUI
import UIKit
import XCTest
@testable import Typr

@MainActor
final class ExperimentalSettingsTests: XCTestCase {
    private let experiment = ExperimentalSwitch(name: "test", title: "Test experiment", detail: "Only in tests.")
    private var suite = ""
    private var defaults: UserDefaults!
    private var windows: [UIWindow] = []

    override func setUp() async throws {
        suite = "ExperimentalSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        for window in windows {
            window.isHidden = true
            window.rootViewController = nil
        }
        windows = []
        defaults.removePersistentDomain(forName: suite)
    }

    func testSwitchIsOffByDefaultAndRoundTripsFromAppToKeyboardDefaults() throws {
        XCTAssertEqual(experiment.key, "typr.experimental.test")
        XCTAssertFalse(TyprSettings(defaults: defaults)[experiment: experiment])

        TyprSettings(defaults: defaults)[experiment: experiment] = true
        let keyboardDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(TyprSettings(defaults: keyboardDefaults)[experiment: experiment])

        TyprSettings(defaults: defaults)[experiment: experiment] = false
        XCTAssertFalse(TyprSettings(defaults: keyboardDefaults)[experiment: experiment])
    }

    func testPreferencesLinkToTheExperimentalPage() {
        XCTAssertEqual(SettingsDestination.experimental.title, "Experimental")
        let links = Self.descendants(of: SettingsPreferences().body).compactMap { $0 as? SettingsLink }
        XCTAssertTrue(links.contains { $0.title == "Experimental" }, "\(links.map(\.title))")
    }

    func testPageShowsEachSwitchWithItsStoredValue() async throws {
        let other = ExperimentalSwitch(name: "other", title: "Other experiment", detail: "Also only in tests.")
        TyprSettings(defaults: defaults)[experiment: other] = true
        let host = mount(ExperimentalSettingsCard(hexExperiments: [experiment], hexKeyboardExperiments: [], typrVariants: [other], defaults: defaults))
        try await waitForState("the page shows two switches") { switchesTopToBottom(in: host).count == 2 }
        XCTAssertEqual(switchesTopToBottom(in: host).map(\.isOn), [false, true])
        for item in [experiment, other] {
            let row = Self.descendants(of: ExperimentalToggle(experiment: item, settings: TyprSettings(defaults: defaults)).body)
                .compactMap { $0 as? SettingsToggle }
            XCTAssertEqual(row.map(\.title), [item.title])
            XCTAssertEqual(row.map(\.detail), [item.detail])
        }
    }

    func testPageWithoutSwitchesSaysSo() {
        let card = ExperimentalSettingsCard(hexExperiments: [], hexKeyboardExperiments: [], typrVariants: [], defaults: defaults)
        XCTAssertTrue(Self.descendants(of: card.body).contains { $0 as? String == ExperimentalSettingsCard.emptyNotice })
        XCTAssertTrue(switchesTopToBottom(in: mount(card)).isEmpty)
    }

    func testPageGroupsHexExperimentsBeforeTyprVariants() {
        let strings = Self.descendants(of: ExperimentalSettingsCard(defaults: defaults).body).compactMap { $0 as? String }
        let hex = strings.firstIndex(of: ExperimentalSettingsCard.hexTitle)
        let keyboard = strings.firstIndex(of: ExperimentalSettingsCard.hexKeyboardTitle)
        let typr = strings.firstIndex(of: ExperimentalSettingsCard.typrTitle)
        XCTAssertNotNil(hex)
        XCTAssertNotNil(keyboard)
        XCTAssertNotNil(typr)
        XCTAssertLessThan(hex ?? .max, keyboard ?? .min)
        XCTAssertLessThan(keyboard ?? .max, typr ?? .min)
    }

    func testExistingTyprSwitchesAreTyprVariantsWithTheirKeys() {
        XCTAssertEqual(ExperimentalSwitch.typrVariants.map(\.key), [
            "typr.experimental.variant.exclusiveAudioSession", "typr.experimental.variant.keepSelectedWarmMicrophone",
            "typr.experimental.variant.audioActivationRetries", "typr.experimental.variant.strictDictationLanguage",
            "typr.experimental.variant.fixedDictationLanguage",
            "typr.experimental.variant.germanFormattingRules", "typr.experimental.variant.conservativeSpokenCleanup",
            "typr.experimental.spokenPunctuation", "typr.experimental.variant.typrKeyboard",
            "typr.experimental.variant.typrTyping", "typr.experimental.variant.cursorSliding", "typr.experimental.variant.deleteSliding",
            "typr.experimental.variant.bottomRow", "typr.experimental.variant.compactStrip",
            "typr.experimental.variant.splitKeyboard",
            "typr.experimental.spaceTrackpad",
            "typr.experimental.formatLists", "typr.experimental.deleteSlide", "typr.experimental.learnFromEdits",
            "typr.experimental.wordsFromContext", "typr.experimental.variant.translationPolicy",
            "typr.experimental.variant.alwaysDictateInApp",
            "typr.experimental.variant.automaticHostReturn", "typr.experimental.variant.liveActivityForAllDictations",
            "typr.experimental.learnEachLanguage",
        ])
        XCTAssertEqual(ExperimentalSwitch.all, ExperimentalSwitch.hexExperiments + ExperimentalSwitch.hexKeyboardExperiments + ExperimentalSwitch.typrVariants)
    }

    func testTyprOverridesAreOffDistinctAndListedOnlyOnceTheirAreaIsHex() {
        let overrides = ExperimentalSwitch.typrOverrides
        XCTAssertEqual(Set(overrides.map(\.key)).count, overrides.count)
        let audio: [ExperimentalSwitch] = [.typrExclusiveAudioSession, .typrKeepSelectedWarmMicrophone, .typrAudioActivationRetries]
        let formatting: [ExperimentalSwitch] = [.typrGermanFormattingRules, .typrConservativeSpokenCleanup]
        XCTAssertEqual(overrides.filter { ExperimentalSwitch.all.contains($0) }, audio + [.typrStrictDictationLanguage, .typrFixedDictationLanguage] + formatting + [.typrTranslationPolicy, .typrAlwaysDictateInApp, .typrAutomaticHostReturn, .typrLiveActivityForAllDictations, .typrKeyboard, .typrTyping, .typrCursorSliding, .typrDeleteSliding, .typrBottomRow, .typrCompactStrip, .typrSplitKeyboard])
        XCTAssertFalse(ExperimentalSwitch.all.contains(.warmMicOnIPhone), "retired by Typr keep selected warm microphone")
        XCTAssertFalse(ExperimentalSwitch.all.contains(.mixWithOtherAudio), "retired by Typr exclusive audio session")
        XCTAssertFalse(ExperimentalSwitch.all.contains(.cleanUpWhatISay), "retired by Clean up what I say in Dictation")
        XCTAssertFalse(ExperimentalSwitch.all.contains(.keyboardDictation), "retired by Typr always dictate in app")
        let settings = TyprSettings(defaults: defaults)
        for override in overrides {
            XCTAssertTrue(override.key.hasPrefix("typr.experimental.variant."), override.key)
            XCTAssertTrue(override.title.hasPrefix("Typr "), override.title)
            XCTAssertFalse(settings[experiment: override], override.key)
        }
    }

    private func mount(_ view: some View) -> UIViewController {
        let host = UIHostingController(rootView: ScrollView { view })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1_200))
        window.rootViewController = host
        window.isHidden = false
        windows.append(window)
        return host
    }

    /// SwiftUI draws `Text` without a `UILabel`, so copy is read from the view values instead.
    private static func descendants(of value: Any, depth: Int = 0) -> [Any] {
        guard depth < 30 else { return [] }
        var found: [Any] = []
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            for child in current.children { found += [child.value] + descendants(of: child.value, depth: depth + 1) }
            mirror = current.superclassMirror
        }
        return found
    }

    private func switchesTopToBottom(in host: UIViewController) -> [UISwitch] {
        host.view.layoutIfNeeded()
        return Self.subviews(of: host.view).compactMap { $0 as? UISwitch }
            .sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
    }

    private static func subviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(subviews(of:))
    }
}
