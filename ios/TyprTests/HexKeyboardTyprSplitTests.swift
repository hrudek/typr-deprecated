import UIKit
import XCTest
@testable import Typr

@MainActor
final class HexKeyboardTyprSplitTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var target = HexFixtureTextTarget(text: "one two ")

    override func setUp() async throws {
        suiteName = "HexKeyboardTyprSplitTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var typr: TyprSettings { TyprSettings(defaults: defaults) }
    private var keyboard: TyprFullKeyboardSettings { TyprFullKeyboardSettings(defaults: defaults) }

    func testTheSwitchIsAnOffByDefaultTyprVariant() {
        XCTAssertEqual(ExperimentalSwitch.typrSplitKeyboard.key, "typr.experimental.variant.splitKeyboard")
        XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(.typrSplitKeyboard))
        XCTAssertTrue(ExperimentalSwitch.typrOverrides.contains(.typrSplitKeyboard))
        XCTAssertFalse(typr[experiment: .typrSplitKeyboard])
        XCTAssertFalse(keyboard.splitKeyboard)
        XCTAssertFalse(keyboard.splitColumns)
    }

    func testOffKeepsHexsSplitKeyboard() throws {
        keyboard.splitKeyboard = false
        keyboard.splitColumns = true
        let view = makeDuoView()
        XCTAssertFalse(view.engine.joinsUnfoldedKeyboard)
        XCTAssertNotNil(view.engine.layout.split)
        XCTAssertFalse(view.engine.typrSplitColumns)
        let hex = KeyboardLayout(width: 801, posture: .unfoldedWide, windowInset: 75)
        let off = KeyboardLayout(width: 801, posture: .unfoldedWide, windowInset: 75, typrSplitColumns: false)
        XCTAssertEqual(off.keys, hex.keys)
    }

    func testTyprsSplitSettingDecidesSplitOrJoined() throws {
        typr[experiment: .typrSplitKeyboard] = true
        let joined = makeDuoView()
        XCTAssertTrue(joined.engine.joinsUnfoldedKeyboard, "Typr's Split keyboard is off by default")
        XCTAssertNil(joined.engine.layout.split)
        let height = joined.preferredHeight

        keyboard.splitKeyboard = true
        joined.syncTyprVariants()
        joined.layoutIfNeeded()
        XCTAssertFalse(joined.engine.joinsUnfoldedKeyboard)
        XCTAssertNotNil(joined.engine.layout.split)
        XCTAssertEqual(joined.preferredHeight, height, "splitting keeps the height")

        typr[experiment: .typrSplitKeyboard] = false
        FullKeyboardSettings(defaults: defaults).joinsKeyboardWhenUnfolded = true
        joined.syncTyprVariants()
        XCTAssertTrue(joined.engine.joinsUnfoldedKeyboard, "off, Hex's join experiment decides again")
    }

    func testAlignedColumnsLineTheSplitLettersUp() throws {
        let staggered = KeyboardLayout(width: 801, posture: .unfoldedWide, windowInset: 75)
        let aligned = KeyboardLayout(width: 801, posture: .unfoldedWide, windowInset: 75, typrSplitColumns: true)
        XCTAssertNotNil(aligned.split)
        func x(_ letter: String, _ layout: KeyboardLayout) throws -> CGRect {
            try XCTUnwrap(layout.keys.first { $0.kind == .character(letter) && $0.row >= 0 }?.frame, letter)
        }
        XCTAssertEqual(try x("a", aligned).minX, try x("q", aligned).minX, accuracy: 0.001)
        XCTAssertEqual(try x("z", aligned).minX, try x("w", aligned).minX, accuracy: 0.001)
        XCTAssertEqual(try x("m", aligned).maxX, try x("o", aligned).maxX, accuracy: 0.001)
        let shift = try XCTUnwrap(aligned.key(.shift)).frame
        let delete = try XCTUnwrap(aligned.key(.delete)).frame
        XCTAssertEqual(shift.minX, try x("q", aligned).minX, accuracy: 0.001)
        XCTAssertEqual(shift.width, try x("q", aligned).width, accuracy: 0.001)
        XCTAssertEqual(delete.maxX, try x("p", aligned).maxX, accuracy: 0.001)
        XCTAssertGreaterThan(try x("a", staggered).minX, try x("q", staggered).minX, "Hex's split staggers")

        XCTAssertEqual(aligned.keys.filter { $0.row == 0 }, staggered.keys.filter { $0.row == 0 }, "row 1 stays")
        XCTAssertEqual(aligned.totalHeight, staggered.totalHeight)
        for key in aligned.keys where key.row >= 0 {
            let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
            XCTAssertEqual(aligned.hitTest(center)?.kind, key.kind, "\(key.kind) takes its own taps")
        }
        let numbers = KeyboardLayout(width: 801, layer: .numbers, posture: .unfoldedWide, windowInset: 75, typrSplitColumns: true)
        XCTAssertEqual(numbers.keys, KeyboardLayout(width: 801, layer: .numbers, posture: .unfoldedWide, windowInset: 75).keys)
    }

    func testTheViewTakesAlignedColumnsAndKeepsTheStripAcrossBothHalves() throws {
        typr[experiment: .typrSplitKeyboard] = true
        keyboard.splitKeyboard = true
        keyboard.splitColumns = true
        let view = makeDuoView()
        let layout = view.engine.layout
        let split = try XCTUnwrap(layout.split)
        XCTAssertTrue(view.engine.typrSplitColumns)
        XCTAssertEqual(layout.key(.shift)?.frame.width, SplitGeometry.keyWidth)
        let strip = view.stripView.frame
        XCTAssertLessThan(strip.minX, split.leftEdge, "S2: the strip reaches the left half")
        XCTAssertGreaterThan(strip.maxX, split.rightEdge, "S2: and the right half")
        XCTAssertEqual(strip.minX, layout.horizontalInset, accuracy: 0.5)
    }

    func testFlippingSplitWithTheCompactStripAsksForTheNewHeight() {
        typr[experiment: .typrSplitKeyboard] = true
        typr[experiment: .typrCompactStrip] = true
        typr.hideSuggestionBar = true
        let view = makeDuoView()
        var heightChanges = 0
        view.onPreferredHeightChange = { heightChanges += 1 }
        for (split, expected) in [(true, 1), (false, 2)] {
            keyboard.splitKeyboard = split
            view.syncTyprVariants()
            XCTAssertEqual(heightChanges, expected, "split \(split)")
            XCTAssertEqual(view.preferredHeight, KeyboardLayout.height(
                for: .portrait, posture: .unfoldedWide, showsStrip: false, joinsUnfoldedKeyboard: !split
            ), "split \(split)")
        }
        XCTAssertLessThan(view.preferredHeight, KeyboardLayout.height(for: .portrait, posture: .unfoldedWide), "joined drops the strip")
    }

    func testCombinationsWithBottomRowCompactStripMechanicalAndSliding() {
        keyboard.bottomRow = BottomRow(order: [.space, .period, .typr], periodKey: true)
        typr.hideSuggestionBar = true
        for split in [false, true] {
            for (bottomRow, compact, sliding) in [(false, false, false), (true, false, true), (false, true, false), (true, true, true)] {
                typr[experiment: .typrSplitKeyboard] = true
                keyboard.splitKeyboard = split
                keyboard.splitColumns = split
                typr[experiment: .typrBottomRow] = bottomRow
                typr[experiment: .typrCompactStrip] = compact
                typr[experiment: .typrCursorSliding] = sliding
                typr[experiment: .typrDeleteSliding] = sliding
                typr[experiment: .deleteSlide] = sliding
                let view = makeDuoView()
                view.designOverride = .mechanical
                view.layoutIfNeeded()
                let layout = view.engine.layout
                let label = "split \(split), bottom row \(bottomRow), compact \(compact), sliding \(sliding)"
                XCTAssertEqual(layout.split != nil, split, label)
                XCTAssertTrue(view.palette.mechanical, label)
                XCTAssertEqual(view.engine.slidesCursorByCharacter, sliding, label)
                XCTAssertEqual(view.plane.repeatsHeldDelete, !sliding, "S3, \(label)")
                let typrRows = !split
                XCTAssertEqual(layout.keys.contains { $0.kind == .character(".") && $0.row == 3 }, typrRows && bottomRow, label)
                XCTAssertEqual(layout.metrics.stripHeight == 0, typrRows && compact, label)
                XCTAssertEqual(view.preferredHeight, KeyboardLayout.height(
                    for: .portrait, posture: .unfoldedWide, showsStrip: !compact, joinsUnfoldedKeyboard: !split
                ), label)
            }
        }
    }

    private func makeDuoView() -> FullKeyboardView {
        target = HexFixtureTextTarget(text: "one two ")
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target, defaults: defaults)
        view.hexPlacementOverride = .stripTrailing
        view.engine.showsNumberRow = false
        view.engine.posture = .unfoldedWide
        view.engine.windowInset = 75
        view.syncTyprVariants()
        view.frame = CGRect(x: 0, y: 0, width: 801, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }
}
