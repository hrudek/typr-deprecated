import SwiftUI
import UIKit
import XCTest
@testable import Typr

/// The keyboard cutover (K9): Hex's keyboard is the default, Typr keyboard brings Typr's back,
/// Slide delete to remove words acts on Hex's key plane, and the settings that reach Hex's
/// keyboard (languages and letter layouts, Spatial autocorrect, Typr key side, live preview).
@MainActor
final class HexKeyboardCutoverTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "HexKeyboardCutoverTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeView(width: CGFloat = 393, landscape: Bool = false) -> FullKeyboardView {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(text: "one two"))
        view.hexPlacementOverride = .stripTrailing
        if landscape { view.orientationOverride = .landscape }
        view.frame = CGRect(x: 0, y: 0, width: width, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }

    // MARK: - Typr keyboard override

    func testTyprKeyboardIsAnOffByDefaultTyprVariant() {
        let typrKeyboard = ExperimentalSwitch.typrKeyboard
        XCTAssertEqual(typrKeyboard.key, "typr.experimental.variant.typrKeyboard")
        XCTAssertEqual(typrKeyboard.title, "Typr keyboard")
        XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(typrKeyboard))
        XCTAssertTrue(ExperimentalSwitch.typrOverrides.contains(typrKeyboard))
        XCTAssertFalse(TyprSettings(defaults: defaults)[experiment: typrKeyboard], "off: Hex's keyboard")
        for onlyTypr in [ExperimentalSwitch.spaceTrackpad, .learnFromEdits, .wordsFromContext, .learnEachLanguage] {
            XCTAssertTrue(onlyTypr.detail.hasPrefix("Only with Typr keyboard."), onlyTypr.key)
        }
        XCTAssertFalse(ExperimentalSwitch.deleteSlide.detail.hasPrefix("Only"), "acts on both keyboards")
    }

    // MARK: - Slide delete to remove words (S3)

    func testSlideDeleteVariantStopsHexHoldRepeatInEveryLayout() {
        let settings = TyprSettings(defaults: defaults)
        for view in [makeView(), makeView(width: 874, landscape: true)] {
            view.syncTyprVariants(settings)
            XCTAssertTrue(view.plane.repeatsHeldDelete, "off: Hex's hold-to-repeat")
            settings[experiment: .deleteSlide] = true
            view.syncTyprVariants(settings)
            XCTAssertFalse(view.plane.repeatsHeldDelete, "on: a held delete never repeats")
            settings[experiment: .deleteSlide] = false
            view.syncTyprVariants(settings)
            XCTAssertTrue(view.plane.repeatsHeldDelete)
        }
    }

    func testHeldDeleteWithTheVariantRemovesOneLetterOnTheComposedKeyboard() async throws {
        let target = HexFixtureTextTarget(text: "one two")
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .deleteSlide] = true
        view.syncTyprVariants(settings)
        let key = try XCTUnwrap(view.engine.layout.key(.delete))
        let delete = TypingLogTouchSample(point: CGPoint(x: key.frame.midX, y: key.frame.midY), timestamp: 0)
        view.plane.began(id: 1, sample: delete)
        defer { view.plane.cancelAllTouches() }
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(target.text, "one tw", "a hold past the repeat delay still deletes one letter")
    }

    // MARK: - Languages and letter layouts

    func testKeyboardLanguagesAndLetterLayoutsRoundTripUnderHexKeys() {
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.keyboardLanguages, [], "Automatic")
        settings.keyboardLanguages = [.german, .english, .german]
        XCTAssertEqual(settings.keyboardLanguages, [.german, .english])
        XCTAssertEqual(defaults.stringArray(forKey: "settings.keyboardLanguages"), ["de", "en"])

        XCTAssertTrue(KeyboardLanguage.english.letterLayouts.contains(.dvorak), "Dvorak is offered for English")
        settings.setLetterLayout(.dvorak, for: .english)
        XCTAssertEqual(settings.letterLayout(for: .english), .dvorak)
        XCTAssertEqual(settings.letterLayouts["en"], "dvorak")
        XCTAssertNil(defaults.object(forKey: "settings.keyboardLayout"), "no legacy key written")
    }

    func testLanguagesPageOffersEachTypingLanguagesLayoutsAndKeepsAutomaticsLanguage() {
        XCTAssertEqual(KeyboardLanguagesPage.toggled(.english, in: [], automatic: .german), [.german, .english])
        XCTAssertEqual(KeyboardLanguagesPage.toggled(.german, in: [], automatic: .german), [.german])
        XCTAssertEqual(KeyboardLanguagesPage.toggled(.german, in: [.german, .english], automatic: .german), [.english])
        XCTAssertEqual(KeyboardLanguagesPage.toggled(.english, in: [.english], automatic: .german), [], "back to Automatic")

        XCTAssertTrue(KeyboardLanguagesPage.arranged(chosen: [], automatic: .english).contains(.english))
        let both = KeyboardLanguagesPage.arranged(chosen: [.german, .english], automatic: .german)
        XCTAssertTrue(both.contains(.english), "English's Dvorak is reachable beside German")
        XCTAssertEqual(KeyboardLanguagesRow.summary(chosen: [], automatic: .german), "Deutsch, same as dictation")
    }

    func testDvorakChosenInSettingsReachesTheHexKeys() throws {
        let settings = LanguageSettings(defaults: defaults)
        settings.keyboardLanguages = [.english]
        settings.setLetterLayout(.dvorak, for: .english)
        let view = makeView()
        view.languageSettings = settings
        view.layoutIfNeeded()
        let top = view.engine.layout.keys.filter { $0.row == 0 }.compactMap { key -> String? in
            if case .character(let letter) = key.kind { return letter }
            return nil
        }
        XCTAssertEqual(Array(top.prefix(3)), ["p", "y", "f"], "\(top)")
    }

    // MARK: - Settings pages

    func testHexKeyboardSettingsNameSpatialAutocorrectAndWriteHexKeys() {
        XCTAssertEqual(ExperimentalSwitch.hexGermanSpatialAutocorrect.detail, "Needs Spatial autocorrect.")
        let card = KeyboardSettingsCard(defaults: defaults)
        let titles = Self.descendants(of: card.body).compactMap { ($0 as? SettingsToggle)?.title }
        XCTAssertTrue(titles.contains("Spatial autocorrect"), "\(titles)")
        XCTAssertTrue(titles.contains("Auto-capitalization"), "\(titles)")
        XCTAssertFalse(Self.descendants(of: card.body).contains { $0 as? String == KeyboardSettingsCard.swipeNotice },
                       "no FUTO notice: Hex's swipe typing has no FUTO model")

        TyprSettings(defaults: defaults)[experiment: .typrKeyboard] = true
        let typr = KeyboardSettingsCard(defaults: defaults)
        let typrTitles = Self.descendants(of: typr.body).compactMap { ($0 as? SettingsToggle)?.title }
        XCTAssertFalse(typrTitles.contains("Spatial autocorrect"), "\(typrTitles)")
        XCTAssertTrue(Self.descendants(of: typr.body).contains { $0 as? String == KeyboardSettingsCard.swipeNotice })
    }

    func testAppearancePreviewIsTheHexKeyboardAndFollowsItsSettingsLive() {
        let settings = FullKeyboardSettings()
        let wasLeft = settings.hexKeyOnLeft
        let wasNumberRow = settings.numberRow
        defer {
            settings.hexKeyOnLeft = wasLeft
            settings.numberRow = wasNumberRow
        }
        settings.hexKeyOnLeft = false
        settings.numberRow = false
        var preview = HexKeyboardAppearancePreview.Settings(
            typrKeyOnLeft: false, numberRow: false, isDark: true, container: CGSize(width: 393, height: 852))
        let view = HexKeyboardAppearancePreview.makeKeyboard(preview)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertEqual(view.preferredHeight, preview.height)
        XCTAssertEqual(view.preferredHeight, 253, "Typr's compact height")
        XCTAssertEqual(view.engine.hexPlacement, .stripTrailing)

        settings.hexKeyOnLeft = true
        settings.numberRow = true
        preview.typrKeyOnLeft = true
        preview.numberRow = true
        HexKeyboardAppearancePreview.apply(preview, to: view)
        XCTAssertEqual(view.engine.hexPlacement, .stripLeading)
        XCTAssertTrue(view.engine.hasNumberRow)
        XCTAssertEqual(view.preferredHeight, preview.height)
        XCTAssertGreaterThan(preview.height, 253)
    }

    func testAppearancePageShowsTheHexPreviewAndItsControlsByDefault() async throws {
        let typr = TyprSettings()
        let wasTyprKeyboard = typr[experiment: .typrKeyboard]
        typr[experiment: .typrKeyboard] = false
        let host = UIHostingController(rootView: NavigationStack { KeyboardAppearancePage() })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1_200))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            typr[experiment: .typrKeyboard] = wasTyprKeyboard
        }
        try await waitForState("the page mounts the Hex preview") {
            host.view.layoutIfNeeded()
            return Self.subviews(of: host.view).contains { $0 is FullKeyboardView }
        }
        let views = Self.subviews(of: host.view)
        XCTAssertFalse(views.contains { $0 is TyprFullKeyboardView })
        XCTAssertEqual(views.compactMap { $0 as? UISegmentedControl }.map(\.numberOfSegments), [2], "Typr key side")
        XCTAssertEqual(views.filter { $0 is UISwitch }.count, 1, "number row")
    }

    private static func subviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { subviews(of: $0) }
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
}
