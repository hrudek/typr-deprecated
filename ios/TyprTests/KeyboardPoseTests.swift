import CoreGraphics
import UIKit
import XCTest
@testable import Typr

/// The keyboard for each iPhone Duo pose, picked from the display's size: outer display 466 × 678 pt, inner
/// display 669 × 951 pt. Keyboard widths include what iOS gives a third-party keyboard there (452 outer upright,
/// 528 outer sideways, 801 inner sideways; iikb docs/design.md) and the whole display, as the settings preview uses.
final class KeyboardPoseTests: XCTestCase {
    private let outerPortrait = CGSize(width: 466, height: 678)
    private let outerLandscape = CGSize(width: 678, height: 466)
    private let innerPortrait = CGSize(width: 669, height: 951)
    private let innerLandscape = CGSize(width: 951, height: 669)

    func testTheDisplaySizeAlonePicksThePose() {
        XCTAssertEqual(TyprKeyboardOrientation(container: outerPortrait), .portrait)
        XCTAssertEqual(TyprKeyboardOrientation(container: outerLandscape), .landscape)
        XCTAssertEqual(TyprKeyboardOrientation(container: innerPortrait), .widePortrait)
        XCTAssertEqual(TyprKeyboardOrientation(container: innerLandscape), .wideLandscape)
        for phone in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 440, height: 956)] {
            XCTAssertEqual(TyprKeyboardOrientation(container: phone), .portrait, "\(phone)")
            XCTAssertEqual(TyprKeyboardOrientation(container: CGSize(width: phone.height, height: phone.width)), .landscape)
        }
    }

    func testTheOuterDisplayKeepsTodaysIPhoneKeyboard() {
        for width: CGFloat in [452, 466] {
            let layout = TyprKeyboardLayout(width: width, orientation: TyprKeyboardOrientation(container: outerPortrait))
            XCTAssertEqual(layout.metrics, TyprKeyboardLayout(width: 440).metrics, "width \(width)")
            XCTAssertEqual(layout.totalHeight, TyprKeyboardLayout.height(for: .portrait))
        }
        for width: CGFloat in [528, 678] {
            let layout = TyprKeyboardLayout(width: width, orientation: TyprKeyboardOrientation(container: outerLandscape))
            XCTAssertEqual(layout.metrics, TyprKeyboardMetrics.landscape, "width \(width)")
            XCTAssertEqual(layout.totalHeight, TyprKeyboardLayout.height(for: .landscape))
        }
    }

    func testInnerPortraitLeavesTheTextVisibleWithKeysInTheNorm() {
        let orientation = TyprKeyboardOrientation(container: innerPortrait)
        for layout in variants(width: innerPortrait.width, orientation: orientation) {
            XCTAssertLessThanOrEqual(layout.totalHeight, 0.36 * innerPortrait.height, describe(layout))
            assertKeysInTheNorm(layout)
            XCTAssertNotNil(layout.balloon(for: layout.key(.character("g"))!), describe(layout))
        }
        XCTAssertGreaterThan(TyprKeyboardLayout(width: 669, orientation: orientation).letterWidth, TyprKeyboardLayout(width: 440).letterWidth)
    }

    func testInnerLandscapeFullLeavesTheTextVisibleWithKeysCentred() {
        let orientation = TyprKeyboardOrientation(container: innerLandscape)
        for width: CGFloat in [801, innerLandscape.width] {
            for layout in variants(width: width, orientation: orientation) {
                XCTAssertLessThanOrEqual(layout.totalHeight, 0.45 * innerLandscape.height, describe(layout))
                assertKeysInTheNorm(layout)
                XCTAssertEqual(layout.letterWidth, TyprKeyboardMetrics.maxWideLetterWidth, accuracy: 0.001, describe(layout))
                let q = layout.key(.character("q"))!
                let p = layout.key(.character("p"))!
                XCTAssertEqual(q.frame.minX, layout.width - p.frame.maxX, accuracy: 0.001, describe(layout))
                XCTAssertGreaterThan(q.frame.minX, TyprKeyboardMetrics.wideLandscape.side, describe(layout))
                XCTAssertEqual(q.hitFrame.minX, 0, "the side padding still types q")
                XCTAssertEqual(layout.key(.returnKey)!.frame.maxX, p.frame.maxX, accuracy: 0.001, describe(layout))
            }
        }
    }

    func testWideLayoutsRoundTripThroughTheTypingLogAndLearning() {
        for layout in [
            TyprKeyboardLayout(width: 669, orientation: .widePortrait),
            TyprKeyboardLayout(width: 801, orientation: .wideLandscape, numberRow: true),
            TyprKeyboardLayout(width: 801, orientation: .splitLandscape),
            TyprKeyboardLayout(width: 801, orientation: .splitLandscape, splitColumns: true),
        ] {
            XCTAssertEqual(TypingLogLayout(layout).keyboardLayout, layout)
            XCTAssertEqual(KeyboardLayoutSignature(layout).orientation, layout.orientation.rawValue)
            XCTAssertNotEqual(KeyboardLayoutSignature(layout), KeyboardLayoutSignature(TyprKeyboardLayout(width: layout.width)))
        }
    }

    func testTheSplitSettingOnlySplitsTheOpenDuoSideways() {
        XCTAssertEqual(TyprKeyboardOrientation(container: innerLandscape, split: true), .splitLandscape)
        XCTAssertEqual(TyprKeyboardOrientation(container: innerLandscape, split: false), .wideLandscape)
        for display in [outerPortrait, outerLandscape, innerPortrait, CGSize(width: 852, height: 393)] {
            XCTAssertEqual(TyprKeyboardOrientation(container: display, split: true), TyprKeyboardOrientation(container: display))
        }
        XCTAssertTrue(TyprKeyboardOrientation.splitLandscape.isLandscape)
        XCTAssertFalse(TyprKeyboardOrientation.splitLandscape.allowsSplit)
    }

    func testSplitHalvesSitAtTheEdgesWithTheFoldBetween() {
        let left = Set("qwertasdfgzxcv".map(String.init))
        let right = Set("yuiopghjklvbnm".map(String.init))
        let phoneLetter = TyprKeyboardLayout(width: outerPortrait.width).letterWidth
        for width: CGFloat in [801, innerLandscape.width] {
            for layout in variants(width: width, orientation: .splitLandscape) {
                let name = describe(layout)
                let full = TyprKeyboardLayout(width: width, orientation: .wideLandscape,
                                          numberRow: layout.numberRow, showsStrip: layout.showsStrip)
                XCTAssertLessThanOrEqual(layout.totalHeight, full.totalHeight, name)
                XCTAssertGreaterThanOrEqual(layout.letterWidth, phoneLetter, name)
                XCTAssertLessThanOrEqual(layout.letterWidth, TyprKeyboardMetrics.maxWideLetterWidth, name)
                assertKeysInTheNorm(layout)

                XCTAssertEqual(layout.key(.shift)!.frame.minX, layout.metrics.side, accuracy: 0.001, name)
                XCTAssertEqual(layout.key(.delete)!.frame.maxX, width - layout.metrics.side, accuracy: 0.001, name)

                let leftKeys = layout.keys.filter { $0.frame.midX < width / 2 }
                let rightKeys = layout.keys.filter { $0.frame.midX > width / 2 }
                XCTAssertEqual(Set(leftKeys.compactMap(\.character)).intersection(left.union(right)), left, name)
                XCTAssertEqual(Set(rightKeys.compactMap(\.character)).intersection(left.union(right)), right, name)
                XCTAssertTrue(layout.keys.allSatisfy { $0.frame.maxX < width / 2 || $0.frame.minX > width / 2 },
                              "no key crosses the middle: \(name)")
                XCTAssertLessThanOrEqual(leftKeys.map(\.frame.maxX).max()!, 0.4 * width + 0.001, name)
                XCTAssertLessThanOrEqual(width - rightKeys.map(\.frame.minX).min()!, 0.4 * width + 0.001, name)

                XCTAssertEqual(leftKeys.filter { $0.kind == .space }.count, 1, name)
                XCTAssertEqual(rightKeys.filter { $0.kind == .space }.count, 1, name)
                for kind in [TyprKeyKind.shift, .layerSwitch(.numbers), .globe] {
                    XCTAssertTrue(leftKeys.contains { $0.kind == kind }, "\(kind) on the left: \(name)")
                }
                for kind in [TyprKeyKind.delete, .returnKey, .typr] {
                    XCTAssertTrue(rightKeys.contains { $0.kind == kind }, "\(kind) on the right: \(name)")
                }
                for key in layout.keys {
                    XCTAssertEqual(layout.hitTest(CGPoint(x: key.frame.midX, y: key.frame.midY)), key, name)
                }
                assertTheGapTypesNothingPastHalfAKey(layout)
            }
        }
    }

    func testTheSplitGapTypesNothingPastHalfAKeyOnEveryLayer() {
        for width: CGFloat in [801, innerLandscape.width] {
            for layer in [TyprKeyboardLayer.numbers, .symbols] {
                for field in [TyprKeyboardFieldKind.text, .url, .email] {
                    for showsStrip in [true, false] {
                        assertTheGapTypesNothingPastHalfAKey(TyprKeyboardLayout(
                            width: width, orientation: .splitLandscape, layer: layer, field: field,
                            showsGlobe: true, showsStrip: showsStrip
                        ))
                    }
                }
            }
        }
    }

    func testTheJoinedSpaceAndTyprKeycapTakesOnlyTheRightSpaceBarWhenSplit() throws {
        for width: CGFloat in [801, innerLandscape.width] {
            let layout = TyprKeyboardLayout(width: width, orientation: .splitLandscape)
            let spaces = layout.keys.filter { $0.kind == .space }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertEqual(spaces.count, 2)
            let joined = try XCTUnwrap(JoinedSpaceKeycap(layout: layout))
            XCTAssertEqual(joined.space, spaces[1].frame, "width \(width)")
            XCTAssertNotEqual(joined.space, spaces[0].frame, "the left space bar keeps its own keycap")
        }
    }

    func testTheOuterDisplayKeepsTodaysIPhoneGlyphs() {
        XCTAssertEqual(TyprKeyboardOrientation(container: outerPortrait).glyphs, KeyGlyphSizes(
            letter: 22.5, capital: 21, widePunctuation: 21, letterLift: 1,
            symbol: 18, returnSymbol: 17.5, label: 15.5, balloonLetter: 33
        ))
        XCTAssertEqual(TyprKeyboardOrientation(container: outerLandscape).glyphs, KeyGlyphSizes(
            letter: 19, capital: 18, widePunctuation: 19, letterLift: 0.5,
            symbol: 16, returnSymbol: 15.5, label: 14.5, balloonLetter: 33
        ))
    }

    func testInnerDisplayGlyphsGrowWithTheKeysAsApplesDo() {
        let phone = TyprKeyboardOrientation.portrait.glyphs
        let inner: [(TyprKeyboardOrientation, ClosedRange<CGFloat>)] = [
            (TyprKeyboardOrientation(container: innerPortrait), 27...28),
            (TyprKeyboardOrientation(container: innerLandscape), 27.5...28.5),
            (TyprKeyboardOrientation(container: innerLandscape, split: true), 27.5...28.5),
        ]
        for (orientation, apple) in inner {
            let glyphs = orientation.glyphs
            XCTAssertTrue(apple.contains(glyphs.letter), "\(orientation) letters \(glyphs.letter)")
            for (size, phoneSize) in [
                (glyphs.capital, phone.capital), (glyphs.widePunctuation, phone.widePunctuation),
                (glyphs.symbol, phone.symbol), (glyphs.returnSymbol, phone.returnSymbol), (glyphs.label, phone.label),
            ] {
                XCTAssertGreaterThan(size, phoneSize, "\(orientation)")
                XCTAssertEqual(size / phoneSize, glyphs.letter / phone.letter, accuracy: 0.05, "\(orientation)")
            }
        }
        XCTAssertEqual(TyprKeyboardOrientation.splitLandscape.glyphs, TyprKeyboardOrientation.wideLandscape.glyphs)
    }

    func testInnerDisplayGlyphsFitTheirKeys() {
        let layouts = [
            TyprKeyboardLayout(width: innerPortrait.width, orientation: .widePortrait),
            TyprKeyboardLayout(width: 801, orientation: .wideLandscape),
            TyprKeyboardLayout(width: 801, orientation: .splitLandscape),
        ]
        for layout in layouts {
            let glyphs = layout.orientation.glyphs
            let key = layout.key(.character("w"))!.frame
            let capital = ("W" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: glyphs.capital)])
            XCTAssertLessThan(capital.width, key.width - 8, describe(layout))
            XCTAssertLessThan(capital.height, key.height, describe(layout))
            let balloon = ("W" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: glyphs.balloonLetter, weight: .light)])
            XCTAssertLessThanOrEqual(balloon.height, TyprKeyBalloon.bubbleHeight, describe(layout))
        }
    }

    /// The keyboard extension and the settings preview both hand `TyprFullKeyboardView` a display size.
    @MainActor
    func testTheKeyboardViewTakesItsGeometryFromTheDisplaySize() {
        let poses: [(CGSize, TyprKeyboardOrientation)] = [
            (outerPortrait, .portrait), (outerLandscape, .landscape),
            (innerPortrait, .widePortrait), (innerLandscape, .wideLandscape),
        ]
        for (display, orientation) in poses {
            let view = KeyboardAppearancePreview.makeKeyboard(KeyboardAppearancePreview.Settings(
                design: .standard, showsSuggestionBar: true, globeKey: .switches,
                bottomRow: BottomRow(), numberRow: false, isDark: false, container: display
            ))
            XCTAssertEqual(view.orientation, orientation, "\(display)")
            XCTAssertEqual(view.preferredHeight, TyprKeyboardLayout.height(for: orientation), "\(display)")
            view.frame = CGRect(x: 0, y: 0, width: display.width, height: view.preferredHeight)
            view.layoutIfNeeded()
            XCTAssertEqual(view.engine.layout.orientation, orientation, "\(display)")
        }
    }

    private func assertTheGapTypesNothingPastHalfAKey(_ layout: TyprKeyboardLayout, file: StaticString = #filePath, line: UInt = #line) {
        let name = describe(layout)
        let reach = layout.letterWidth / 2
        for row in 0...layout.bottomRowIndex {
            let keys = layout.keys.filter { $0.row == row }.sorted { $0.frame.minX < $1.frame.minX }
            let leftHalf = keys.filter { $0.frame.maxX < layout.width / 2 }
            let rightHalf = keys.filter { $0.frame.minX > layout.width / 2 }
            for half in [leftHalf, rightHalf] {
                for (a, b) in zip(half, half.dropFirst()) {
                    XCTAssertEqual(a.hitFrame.maxX, b.hitFrame.minX, accuracy: 0.0001, "row \(row) tiles: \(name)", file: file, line: line)
                }
            }
            let inner = (leftHalf.last!, rightHalf.first!)
            let y = inner.0.frame.midY
            XCTAssertEqual(layout.hitTest(CGPoint(x: inner.0.frame.maxX + reach - 0.5, y: y)), inner.0, name, file: file, line: line)
            XCTAssertEqual(layout.hitTest(CGPoint(x: inner.1.frame.minX - reach + 0.5, y: y)), inner.1, name, file: file, line: line)
            XCTAssertNil(layout.hitTest(CGPoint(x: inner.0.frame.maxX + reach + 0.5, y: y)), "row \(row): \(name)", file: file, line: line)
            XCTAssertNil(layout.hitTest(CGPoint(x: inner.1.frame.minX - reach - 0.5, y: y)), "row \(row): \(name)", file: file, line: line)
            XCTAssertNil(layout.hitTest(CGPoint(x: layout.width / 2, y: y)), "row \(row): \(name)", file: file, line: line)
        }
    }

    private func variants(width: CGFloat, orientation: TyprKeyboardOrientation) -> [TyprKeyboardLayout] {
        [true, false].flatMap { showsStrip in
            [false, true].map { numberRow in
                TyprKeyboardLayout(width: width, orientation: orientation, showsGlobe: true, numberRow: numberRow, showsStrip: showsStrip)
            }
        }
    }

    /// Letters at least as easy to hit as on an iPhone, at most about an iPad's, and Apple's 44 pt tall targets.
    private func assertKeysInTheNorm(_ layout: TyprKeyboardLayout, file: StaticString = #filePath, line: UInt = #line) {
        let g = layout.key(.character("g"))!
        XCTAssertGreaterThanOrEqual(g.hitFrame.width, 30, describe(layout), file: file, line: line)
        XCTAssertLessThanOrEqual(g.frame.width, 60, describe(layout), file: file, line: line)
        XCTAssertGreaterThanOrEqual(g.hitFrame.height, 44, describe(layout), file: file, line: line)
    }

    private func describe(_ layout: TyprKeyboardLayout) -> String {
        "\(layout.width)pt \(layout.orientation) strip=\(layout.showsStrip) numbers=\(layout.numberRow)"
    }
}
