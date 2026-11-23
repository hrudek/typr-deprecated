import SwiftUI
import UIKit
import XCTest
@testable import Typr

@MainActor
final class HexKeyboardTyprLookTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "HexKeyboardTyprLookTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStandardPaletteIsUnchangedAndMechanicalTakesTyprsColours() {
        for isDark in [false, true] {
            let standard = FullKeyboardPalette(isDark: isDark)
            XCTAssertFalse(standard.mechanical)
            assertSameColor(standard.keyInk, standard.textBase)
            XCTAssertEqual(standard.inkFrame(CGRect(x: 0, y: 0, width: 33, height: 45)), CGRect(x: 0, y: 0, width: 33, height: 45))

            let mechanical = FullKeyboardPalette(isDark: isDark, mechanical: true)
            let typr = TyprFullKeyboardPalette(isDark: isDark, design: .mechanical)
            assertSameColor(mechanical.keyFill, typr.keyFill)
            for held in [mechanical.keyPressedFill, mechanical.keyHeldFill, mechanical.functionHeldFill, mechanical.spaceHeldFill] {
                assertSameColor(held, typr.keyPressedFill)
            }
            assertSameColor(mechanical.keyInk, typr.keyLabel)
            let cap = CGRect(x: 10, y: 20, width: 33, height: 45)
            XCTAssertEqual(mechanical.inkFrame(cap), MechanicalKeycap(isDark: isDark).faceRect(cap))
        }
    }

    func testMechanicalPaletteNeverCarriesATheme() {
        for theme in KeyboardTheme.allCases {
            let palette = FullKeyboardPalette(isDark: false, theme: theme, mechanical: true)
            XCTAssertEqual(palette.theme, .automatic, theme.rawValue)
            XCTAssertFalse(palette.drawsOwnBackground, theme.rawValue)
        }
    }

    func testDesignDefaultsToStandard() {
        XCTAssertEqual(FullKeyboardView.typrKeyboardDesign(defaults: defaults), .standard)
        TyprFullKeyboardSettings(defaults: defaults).design = .mechanical
        XCTAssertEqual(FullKeyboardView.typrKeyboardDesign(defaults: defaults), .mechanical)
    }

    func testTheHexKeyboardDrawsMechanicalKeysWithTheSameGeometry() throws {
        let typr = TyprFullKeyboardSettings()
        let hex = FullKeyboardSettings()
        let was = (typr.design, hex.numberRow, hex.keyboardThemesEnabled, hex.keyboardTheme)
        defer {
            typr.design = was.0
            hex.numberRow = was.1
            hex.keyboardThemesEnabled = was.2
            hex.keyboardTheme = was.3
        }
        for (numberRow, themed) in [(false, false), (true, false), (false, true), (true, true)] {
            typr.design = .standard
            hex.numberRow = numberRow
            hex.keyboardThemesEnabled = themed
            hex.keyboardTheme = .navy
            let view = makeView()
            let label = "number row \(numberRow), themed \(themed)"
            XCTAssertFalse(view.palette.mechanical, label)
            let height = view.preferredHeight
            if !numberRow { XCTAssertEqual(height, 253, label) }
            let frames = view.engine.layout.keys.map(\.frame)
            let standardImage = render(view.plane)

            typr.design = .mechanical
            view.syncSettings()
            view.layoutIfNeeded()
            XCTAssertTrue(view.palette.mechanical, label)
            XCTAssertEqual(view.palette.theme, .automatic, label)
            XCTAssertTrue(view.themePanel.isHidden, label)
            XCTAssertEqual(view.preferredHeight, height, label)
            XCTAssertEqual(view.engine.layout.keys.map(\.frame), frames, label)
            XCTAssertNotEqual(render(view.plane), standardImage, "the keys are drawn differently, \(label)")

            typr.design = .standard
            view.syncSettings()
            XCTAssertFalse(view.palette.mechanical, label)
            XCTAssertEqual(view.palette.theme, themed ? .navy : .automatic, label)
        }
    }

    func testAppearancePreviewFollowsTheDesign() {
        let typr = TyprFullKeyboardSettings()
        let was = typr.design
        defer { typr.design = was }
        typr.design = .standard
        var preview = HexKeyboardAppearancePreview.Settings(
            design: .standard, typrKeyOnLeft: false, numberRow: false, isDark: true, container: CGSize(width: 393, height: 852))
        let view = HexKeyboardAppearancePreview.makeKeyboard(preview)
        XCTAssertFalse(view.palette.mechanical)

        typr.design = .mechanical
        preview.design = .mechanical
        HexKeyboardAppearancePreview.apply(preview, to: view)
        XCTAssertTrue(view.palette.mechanical)
        XCTAssertEqual(view.preferredHeight, 253)
        XCTAssertTrue(preview.accessibilityLabel.contains("Mechanical"), preview.accessibilityLabel)
    }

    func testKeysSectionShowsHexRowsOnlyOnTheHexKeyboard() {
        let card = KeyboardSettingsCard(defaults: defaults)
        XCTAssertTrue(Self.descendants(of: card.body).contains { $0 is HexKeyboardKeysSection })
        let titles = Self.descendants(of: HexKeyboardKeysSection(defaults: defaults).body)
            .compactMap { ($0 as? SettingsToggle)?.title }
        XCTAssertEqual(Set(titles), ["Key pop-ups", "Haptics", "Emoji"])

        TyprSettings(defaults: defaults)[experiment: .typrKeyboard] = true
        let typr = KeyboardSettingsCard(defaults: defaults)
        XCTAssertFalse(Self.descendants(of: typr.body).contains { $0 is HexKeyboardKeysSection })
    }

    func testHapticStrengthTitles() {
        XCTAssertEqual(KeyHapticStrength.allCases.map(\.title), ["Light", "Medium", "Strong"])
    }

    func testAdaptiveTouchStatusFollowsFullAccessAndTheKeyboardsSummary() {
        XCTAssertEqual(HexKeyboardLearningSection.status(defaults: defaults), .sessionOnly)
        KeyboardBridge(defaults: defaults).fullAccessSeenAt = 1
        XCTAssertEqual(HexKeyboardLearningSection.status(defaults: defaults), .learning(taps: 0))
        AdaptiveTouchSettings(defaults: defaults).summary = (taps: 120, active: false)
        XCTAssertEqual(HexKeyboardLearningSection.status(defaults: defaults), .learning(taps: 120))
        AdaptiveTouchSettings(defaults: defaults).summary = (taps: 500, active: true)
        XCTAssertEqual(HexKeyboardLearningSection.status(defaults: defaults), .active)
        AdaptiveTouchSettings(defaults: defaults).requestReset()
        XCTAssertEqual(HexKeyboardLearningSection.status(defaults: defaults), .learning(taps: 0))

        XCTAssertEqual(HexKeyboardLearningSection.statusText(.sessionOnly), "Without Full Access, resets when the keyboard closes.")
        XCTAssertEqual(HexKeyboardLearningSection.statusText(.learning(taps: 120)),
                       "Learning: 120 of \(AdaptiveTouchModel.activeTaps) taps.")
        XCTAssertEqual(HexKeyboardLearningSection.statusText(.active), "Active, using your own key centers.")
    }

    private func makeView() -> FullKeyboardView {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(text: "one two"))
        view.hexPlacementOverride = .stripTrailing
        view.appearanceOverride = false
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }

    private func render(_ view: UIView) -> Data? {
        view.setNeedsDisplay()
        view.layer.displayIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }.pngData()
    }

    private func assertSameColor(_ lhs: UIColor, _ rhs: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        XCTAssertTrue(lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la), file: file, line: line)
        XCTAssertTrue(rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra), file: file, line: line)
        XCTAssertEqual([lr, lg, lb, la], [rr, rg, rb, ra], file: file, line: line)
    }

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
