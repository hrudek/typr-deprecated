import UIKit
import XCTest
@testable import Typr

@MainActor
final class HexKeyboardTyprBottomRowTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "HexKeyboardTyprBottomRowTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var portraitStripArea: CGFloat { KeyboardMetrics.for(.portrait).stripArea }

    func testSwitchesAreOffByDefaultTyprVariants() {
        XCTAssertEqual(ExperimentalSwitch.typrBottomRow.key, "typr.experimental.variant.bottomRow")
        XCTAssertEqual(ExperimentalSwitch.typrCompactStrip.key, "typr.experimental.variant.compactStrip")
        let typr = TyprSettings(defaults: defaults)
        for item in [ExperimentalSwitch.typrBottomRow, .typrCompactStrip] {
            XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(item), item.key)
            XCTAssertTrue(ExperimentalSwitch.typrOverrides.contains(item), item.key)
            XCTAssertFalse(typr[experiment: item], item.key)
        }
        XCTAssertFalse(typr.hideSuggestionBar)
    }

    func testBothOffLeaveTheHexKeyboardAsItIs() {
        for orientation in [KeyboardOrientation.portrait, .landscape] {
            for field in [KeyboardFieldKind.text, .url, .email] {
                let hex = KeyboardLayout(width: 393, orientation: orientation, field: field, showsGlobe: true, showsEmoji: true)
                let off = KeyboardLayout(width: 393, orientation: orientation, field: field, showsGlobe: true, showsEmoji: true,
                                         typrBottomRow: nil, showsStrip: true)
                XCTAssertEqual(off.keys, hex.keys)
                XCTAssertEqual(off.metrics, hex.metrics)
                XCTAssertEqual(off.hexPlacement, .stripTrailing)
            }
        }

        let view = makeView()
        XCTAssertNil(view.engine.typrBottomRow)
        XCTAssertTrue(view.engine.showsStrip)
        XCTAssertEqual(view.preferredHeight, 253)
        XCTAssertEqual(view.engine.layout.key(.hex)?.row, -1, "the Typr key stays in the strip")
        XCTAssertFalse(view.stripView.clipsToBounds)
    }

    func testBottomRowPutsTheTyprPeriodAndEmojiKeysInTheirOrder() throws {
        let standard = KeyboardLayout(width: 393, showsEmoji: true)
        let row = BottomRow(order: [.space, .period, .typr], periodKey: true, emojiKey: true)
        let layout = KeyboardLayout(width: 393, showsEmoji: true, typrBottomRow: row)
        XCTAssertEqual(bottomKinds(layout), [.layerSwitch(.numbers), .emoji, .space, .character("."), .hex, .returnKey])
        XCTAssertEqual(layout.hexPlacement, .rightOfSpace)
        XCTAssertEqual(layout.totalHeight, 253)
        XCTAssertEqual(layout.keys.filter { $0.row >= 0 && $0.row < 3 }, standard.keys.filter { $0.row >= 0 && $0.row < 3 },
                       "rows 1 to 3 do not move")
        assertTiled(layout)

        let leading = KeyboardLayout(width: 393, typrBottomRow: BottomRow(order: [.typr, .space, .period]))
        XCTAssertEqual(bottomKinds(leading), [.layerSwitch(.numbers), .hex, .space, .returnKey], "no period or emoji key unless set")
        XCTAssertEqual(leading.hexPlacement, .leftOfSpace)

        let globe = KeyboardLayout(width: 393, showsGlobe: true, typrBottomRow: BottomRow(order: [.period, .space, .typr], periodKey: true))
        XCTAssertEqual(bottomKinds(globe), [.layerSwitch(.numbers), .globe, .character("."), .space, .hex, .returnKey])
        assertTiled(globe)
    }

    func testBottomRowKeepsHexsRowsInUrlFieldsAndOnTheDuoAndIPad() {
        let url = KeyboardLayout(width: 393, field: .url, typrBottomRow: BottomRow())
        XCTAssertEqual(bottomKinds(url), [.layerSwitch(.numbers), .space, .character("."), .character("/"), .hex, .returnKey])

        let split = KeyboardLayout(width: 800, posture: .unfoldedWide, typrBottomRow: BottomRow(), showsStrip: false)
        let hexSplit = KeyboardLayout(width: 800, posture: .unfoldedWide)
        XCTAssertEqual(split.keys, hexSplit.keys)
        XCTAssertEqual(split.metrics, hexSplit.metrics)
        XCTAssertEqual(KeyboardLayout.height(for: .portrait, posture: .unfoldedWide, showsStrip: false),
                       KeyboardLayout.height(for: .portrait, posture: .unfoldedWide))
    }

    func testThePeriodKeyTypesAPeriod() throws {
        let view = makeView()
        TyprSettings(defaults: defaults)[experiment: .typrBottomRow] = true
        TyprFullKeyboardSettings(defaults: defaults).bottomRow = BottomRow(order: [.space, .period, .typr], periodKey: true)
        sync(view)
        view.layoutIfNeeded()
        let period = try XCTUnwrap(view.engine.layout.keys.first { $0.row == 3 && $0.kind == .character(".") })
        let point = CGPoint(x: period.frame.midX, y: period.frame.midY)
        view.engine.touchBegan(id: 1, at: point)
        view.engine.touchEnded(id: 1, at: point)
        XCTAssertTrue(target.text.hasSuffix("."), target.text)
        XCTAssertEqual(view.engine.layout.key(.hex)?.row, 3)
        XCTAssertFalse(view.hexKey.inStrip)
        XCTAssertEqual(view.preferredHeight, 253)
    }

    func testTheEmojiKeyFollowsTyprsSettingOnlyInFieldsThatTakeEmoji() {
        let view = makeView()
        view.emojiOverride = false
        TyprSettings(defaults: defaults)[experiment: .typrBottomRow] = true
        TyprFullKeyboardSettings(defaults: defaults).bottomRow = BottomRow(emojiKey: true)
        sync(view)
        XCTAssertTrue(view.engine.layout.keys.contains { $0.kind == .emoji }, "Typr's emoji key, with Hex's Emoji off")

        for type in [UIKeyboardType.emailAddress, .URL, .asciiCapable] {
            target.keyboardType = type
            view.prepareForField()
            sync(view)
            view.refreshEmojiKey()
            XCTAssertFalse(view.engine.layout.keys.contains { $0.kind == .emoji }, "\(type.rawValue)")
        }

        target.keyboardType = .default
        view.prepareForField()
        TyprFullKeyboardSettings(defaults: defaults).bottomRow = BottomRow(emojiKey: false)
        view.emojiOverride = true
        sync(view)
        view.refreshEmojiKey()
        XCTAssertFalse(view.engine.layout.keys.contains { $0.kind == .emoji }, "Typr's setting decides while its row is on")
    }

    func testCompactStripDropsTheStripAndMovesTheTyprKeyBesideSpace() throws {
        let standard = KeyboardLayout(width: 393)
        let compact = KeyboardLayout(width: 393, showsStrip: false)
        let shift = portraitStripArea - 6
        XCTAssertEqual(compact.metrics.stripArea, 0)
        XCTAssertEqual(compact.totalHeight, 253 - shift)
        XCTAssertEqual(KeyboardLayout.height(for: .portrait, showsStrip: false), compact.totalHeight)
        XCTAssertEqual(compact.hexPlacement, .rightOfSpace)
        XCTAssertEqual(compact.key(.hex)?.row, 3)
        for letter in ["q", "a", "z", "p"] {
            let before = try XCTUnwrap(standard.key(.character(letter))).frame
            XCTAssertEqual(compact.key(.character(letter))?.frame, before.offsetBy(dx: 0, dy: -shift), letter)
        }
        assertTiled(compact)

        XCTAssertEqual(KeyboardLayout(width: 393, hexPlacement: .stripLeading, showsStrip: false).hexPlacement, .leftOfSpace)
        let landscape = KeyboardLayout(width: 852, orientation: .landscape, showsStrip: false)
        XCTAssertEqual(landscape.totalHeight, KeyboardLayout.height(for: .landscape) - KeyboardMetrics.for(.landscape).stripArea + 4)
        let numberRow = KeyboardLayout(width: 393, numberRow: true, showsStrip: false)
        XCTAssertEqual(numberRow.totalHeight, KeyboardLayout.height(for: .portrait, numberRow: true) - shift)
    }

    func testCompactStripNeedsTheSwitchAndHideSuggestionBar() {
        let view = makeView()
        var heightChanges = 0
        view.onPreferredHeightChange = { heightChanges += 1 }
        let typr = TyprSettings(defaults: defaults)

        typr.hideSuggestionBar = true
        sync(view)
        XCTAssertEqual(view.preferredHeight, 253, "Hide suggestion bar alone is Typr keyboard's")

        typr[experiment: .typrCompactStrip] = true
        sync(view)
        view.layoutIfNeeded()
        XCTAssertFalse(view.engine.showsStrip)
        XCTAssertEqual(view.preferredHeight, 253 - (portraitStripArea - 6))
        XCTAssertEqual(heightChanges, 1)
        XCTAssertTrue(view.stripView.clipsToBounds)
        XCTAssertEqual(view.stripView.frame.height, 0)
        XCTAssertFalse(view.hexKey.inStrip)
        XCTAssertEqual(view.stripBandMetrics.stripHeight, KeyboardMetrics.typrPortrait.stripHeight)

        typr.hideSuggestionBar = false
        sync(view)
        XCTAssertTrue(view.engine.showsStrip)
        XCTAssertEqual(view.preferredHeight, 253)
        XCTAssertEqual(heightChanges, 2)
        XCTAssertEqual(view.stripBandMetrics, view.engine.layout.metrics)
    }

    func testEmojiPanelAndSearchKeepAStripRowWithoutTheStrip() throws {
        let typr = TyprSettings(defaults: defaults)
        typr[experiment: .typrCompactStrip] = true
        typr.hideSuggestionBar = true
        let view = makeView()
        view.emojiOverride = true
        view.debugOpenEmoji()
        view.layoutIfNeeded()
        let panel = try XCTUnwrap(view.emojiPanel)
        XCTAssertEqual(panel.metrics.stripHeight, KeyboardMetrics.typrPortrait.stripHeight, "the panel's top row keeps its room")
        XCTAssertEqual(panel.metrics.keyHeight, view.engine.layout.metrics.keyHeight)

        view.beginEmojiSearch()
        view.frame.size.height = view.preferredHeight
        view.layoutIfNeeded()
        let row = KeyboardMetrics.typrPortrait.stripHeight
        XCTAssertEqual(view.emojiSearchLift, 2 * row)
        let results = try XCTUnwrap(view.emojiResults).frame
        let field = try XCTUnwrap(view.emojiSearchField).frame
        XCTAssertEqual(results.height, row)
        XCTAssertGreaterThan(field.height, 0)
        XCTAssertGreaterThanOrEqual(field.minY, results.maxY)
        let firstKeyTop = try XCTUnwrap(view.engine.layout.keys.map(\.frame.minY).min()) + view.emojiSearchLift
        XCTAssertLessThanOrEqual(field.maxY, firstKeyTop, "the search field sits above the keys")
    }

    func testCombinationsWithMechanicalSlidingAndSlideDelete() {
        let typr = TyprSettings(defaults: defaults)
        let keyboard = TyprFullKeyboardSettings(defaults: defaults)
        keyboard.bottomRow = BottomRow(order: [.space, .period, .typr], periodKey: true)
        typr.hideSuggestionBar = true
        let compactHeight = 253 - (portraitStripArea - 6)
        for bottomRow in [false, true] {
            for compact in [false, true] {
                for (mechanical, sliding) in [(false, false), (true, true), (true, false), (false, true)] {
                    typr[experiment: .typrBottomRow] = bottomRow
                    typr[experiment: .typrCompactStrip] = compact
                    typr[experiment: .typrCursorSliding] = sliding
                    typr[experiment: .typrDeleteSliding] = sliding
                    typr[experiment: .deleteSlide] = sliding
                    let view = makeView()
                    view.designOverride = mechanical ? .mechanical : .standard
                    sync(view)
                    view.layoutIfNeeded()
                    let label = "bottom row \(bottomRow), compact \(compact), mechanical \(mechanical), sliding \(sliding)"
                    XCTAssertEqual(view.preferredHeight, compact ? compactHeight : 253, label)
                    XCTAssertEqual(view.engine.layout.key(.hex)?.row, bottomRow || compact ? 3 : -1, label)
                    XCTAssertEqual(view.engine.layout.keys.contains { $0.kind == .character(".") && $0.row == 3 }, bottomRow, label)
                    XCTAssertEqual(view.palette.mechanical, mechanical, label)
                    XCTAssertEqual(view.engine.slidesCursorByCharacter, sliding, label)
                    XCTAssertEqual(view.plane.repeatsHeldDelete, !sliding, "S3: slide delete wins, \(label)")
                    assertTiled(view.engine.layout, label)
                }
            }
        }
    }

    func testDrawingNeverMovesTheTyprRows() {
        let view = makeView()
        TyprSettings(defaults: defaults)[experiment: .typrBottomRow] = true
        TyprSettings(defaults: defaults)[experiment: .typrCompactStrip] = true
        TyprSettings(defaults: defaults).hideSuggestionBar = true
        sync(view)
        let frames = view.engine.layout.keys.map(\.frame)
        view.appearanceOverride = true
        view.designOverride = .mechanical
        view.layoutIfNeeded()
        XCTAssertEqual(view.engine.layout.keys.map(\.frame), frames, "drawing never moves the keys")
    }

    func testAppearancePreviewShowsTheTyprRows() {
        var preview = HexKeyboardAppearancePreview.Settings(
            typrKeyOnLeft: false, numberRow: false, isDark: true, container: CGSize(width: 393, height: 852))
        let view = HexKeyboardAppearancePreview.makeKeyboard(preview)
        preview.bottomRow = BottomRow(order: [.typr, .space, .period])
        preview.showsStrip = false
        HexKeyboardAppearancePreview.apply(preview, to: view)
        XCTAssertEqual(view.engine.typrBottomRow, preview.bottomRow)
        XCTAssertFalse(view.engine.showsStrip)
        XCTAssertEqual(view.engine.layout.hexPlacement, .leftOfSpace)
        XCTAssertEqual(preview.height, KeyboardLayout.height(for: .portrait, showsStrip: false))
        XCTAssertTrue(preview.accessibilityLabel.contains("suggestions hidden"), preview.accessibilityLabel)
    }

    private var target = HexFixtureTextTarget(text: "one two ")

    private func makeView() -> FullKeyboardView {
        target = HexFixtureTextTarget(text: "one two ")
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
        view.hexPlacementOverride = .stripTrailing
        view.engine.showsNumberRow = false
        sync(view)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }

    private func sync(_ view: FullKeyboardView) {
        view.syncTyprVariants(TyprSettings(defaults: defaults), keyboard: TyprFullKeyboardSettings(defaults: defaults))
    }

    private func bottomKinds(_ layout: KeyboardLayout) -> [KeyKind] {
        layout.keys.filter { $0.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }.map(\.kind)
    }

    private func assertTiled(_ layout: KeyboardLayout, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let row = layout.keys.filter { $0.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }
        for (a, b) in zip(row, row.dropFirst()) {
            XCTAssertLessThanOrEqual(a.frame.maxX, b.frame.minX + 0.001, "\(a.kind) overlaps \(b.kind) \(label)", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(row.first?.frame.minX ?? -1, 0, label, file: file, line: line)
        XCTAssertLessThanOrEqual(row.last?.frame.maxX ?? .infinity, layout.width + 0.001, label, file: file, line: line)
        XCTAssertTrue(layout.keys.allSatisfy { $0.frame.minY >= 0 }, label, file: file, line: line)
    }
}
