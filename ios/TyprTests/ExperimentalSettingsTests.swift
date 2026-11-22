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
        let host = mount(ExperimentalSettingsCard(switches: [experiment, other], defaults: defaults))
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
        let card = ExperimentalSettingsCard(switches: [], defaults: defaults)
        XCTAssertTrue(Self.descendants(of: card.body).contains { $0 as? String == ExperimentalSettingsCard.emptyNotice })
        XCTAssertTrue(switchesTopToBottom(in: mount(card)).isEmpty)
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
