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

    func testPreferencesLinkToTheExperimentalPage() async throws {
        XCTAssertEqual(SettingsDestination.experimental.title, "Experimental")
        let host = mount(NavigationStack { SettingsPreferences() })
        try await waitForState("Preferences list Experimental") { labels(in: host).contains("Experimental") }
    }

    func testPageShowsEachSwitchWithItsStoredValue() async throws {
        let other = ExperimentalSwitch(name: "other", title: "Other experiment", detail: "Also only in tests.")
        TyprSettings(defaults: defaults)[experiment: other] = true
        let host = mount(ExperimentalSettingsCard(switches: [experiment, other], defaults: defaults))
        try await waitForState("the page shows two switches") { switchesTopToBottom(in: host).count == 2 }
        XCTAssertEqual(switchesTopToBottom(in: host).map(\.isOn), [false, true])
        for text in [experiment.title, experiment.detail, other.title, other.detail] {
            XCTAssertTrue(labels(in: host).contains(text), "\(text) missing from \(labels(in: host))")
        }
    }

    func testPageWithoutSwitchesSaysSo() async throws {
        let host = mount(ExperimentalSettingsCard(switches: [], defaults: defaults))
        try await waitForState("the empty notice is shown") {
            labels(in: host).contains(ExperimentalSettingsCard.emptyNotice)
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

    private func labels(in host: UIViewController) -> [String] {
        host.view.layoutIfNeeded()
        return Self.subviews(of: host.view).compactMap { ($0 as? UILabel)?.text }
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
