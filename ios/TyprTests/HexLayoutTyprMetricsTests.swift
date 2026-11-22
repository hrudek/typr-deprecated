import CoreGraphics
import XCTest
@testable import Typr

/// Hex's layout path on an iPhone draws Typr's compact keys (`KeyboardMetrics.typrPortrait`,
/// `typrLandscape`): the same heights, rows and letter keys as `TyprKeyboardLayout`, on every
/// iPhone size and iOS version. The Duo and the iPad keep Hex's rows.
final class HexLayoutTyprMetricsTests: XCTestCase {
    private let portraitWidths: [CGFloat] = [320, 375, 393, 402, 430, 440]
    private let landscapeWidths: [CGFloat] = [667, 844, 874, 932, 956]
    private let letters = Array("qwertyuiopasdfghjklzxcvbnm").map(String.init)
    private var runningSystemMajorVersion = 0

    override func setUp() {
        super.setUp()
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
    }

    override func tearDown() {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        super.tearDown()
    }

    func testIPhoneHeightsAreTyprsOnEverySizeAndVersion() {
        for version in [18, 26, 27] {
            KeyboardLanguage.systemMajorVersion = version
            for size in [KeyboardPhoneSize.homeButton, .regular, .large] {
                let label = "iOS \(version) \(size)"
                XCTAssertEqual(KeyboardLayout.height(for: .portrait, phoneSize: size), 253, label)
                XCTAssertEqual(KeyboardLayout.height(for: .landscape, phoneSize: size), 176, label)
                for width in portraitWidths {
                    let layout = KeyboardLayout(width: width, phoneSize: size)
                    XCTAssertEqual(layout.totalHeight, 253, "\(label) \(width)")
                    XCTAssertEqual(layout.stripFrame.height, 33, "\(label) \(width)")
                    XCTAssertEqual(layout.metrics.stripArea, 35, "\(label) \(width)")
                    let q = layout.key(.character("q"))!.frame
                    XCTAssertEqual(q.minY, 35, accuracy: 0.001, "\(label) \(width)")
                    XCTAssertEqual(q.height, 45, "\(label) \(width)")
                    XCTAssertEqual(layout.key(.character("a"))!.frame.minY - q.minY, 56, accuracy: 0.001, "\(label) \(width)")
                    XCTAssertEqual(layout.key(.space)!.frame.height, 45, "\(label) \(width)")
                    XCTAssertEqual(layout.totalHeight - layout.key(.space)!.frame.maxY, 5, accuracy: 0.001, "\(label) \(width)")
                }
                let hex = layout(402, size).key(.hex)!
                XCTAssertEqual(hex.frame.height, TyprKeyboardMetrics.stripPillHeight, label)
                XCTAssertEqual(hex.frame.midY, 16.5, accuracy: 0.001, label)
                XCTAssertLessThanOrEqual(hex.hitFrame.maxY, layout(402, size).key(.character("q"))!.hitFrame.minY + 0.001, label)
                let turned = KeyboardLayout(width: 874, orientation: .landscape, horizontalInset: 62, phoneSize: size)
                XCTAssertEqual(turned.totalHeight, 176, label)
                XCTAssertEqual(turned.key(.character("q"))!.frame.height, 27.5, label)
                XCTAssertEqual(turned.key(.character("q"))!.frame.minY, 39, accuracy: 0.001, label)
            }
        }
    }

    func testIPhoneMetricsMatchTyprsLayoutMetrics() {
        for width in portraitWidths {
            assertSameRows(KeyboardMetrics.for(.portrait, innerWidth: width), TyprKeyboardMetrics.for(.portrait, innerWidth: width), "\(width)")
            XCTAssertEqual(KeyboardLayout(width: width).totalHeight, TyprKeyboardLayout(width: width).totalHeight, "\(width)")
        }
        assertSameRows(KeyboardMetrics.for(.landscape), TyprKeyboardMetrics.for(.landscape), "landscape")
        XCTAssertEqual(KeyboardLayout.height(for: .portrait), TyprKeyboardLayout.height(for: .portrait))
        XCTAssertEqual(KeyboardLayout.height(for: .landscape), TyprKeyboardLayout.height(for: .landscape))
    }

    /// Every letter key sits where Typr's does, and a touch anywhere across a row's letters (gaps
    /// between letters included) lands on the same letter in both layouts, so touch and decoder
    /// coordinates carry over unchanged. The gap beside shift and delete is Hex's to split.
    func testLetterKeysAndTouchesAgreeWithTyprsLayout() {
        var cases: [(KeyboardLayout, TyprKeyboardLayout, String)] = portraitWidths.map {
            (KeyboardLayout(width: $0), TyprKeyboardLayout(width: $0), "\($0)pt portrait")
        }
        for width in landscapeWidths {
            cases.append((
                KeyboardLayout(width: width, orientation: .landscape, horizontalInset: 62),
                TyprKeyboardLayout(width: width, orientation: .landscape, horizontalInset: 62),
                "\(width)pt landscape"
            ))
        }
        for (hex, typr, label) in cases {
            XCTAssertEqual(hex.stripFrame.minY, typr.stripFrame.minY, label)
            XCTAssertEqual(hex.stripFrame.height, typr.stripFrame.height, label)
            for letter in letters {
                let hexKey = hex.key(.character(letter))!
                let typrKey = typr.key(.character(letter))!
                assertEqual(hexKey.frame, typrKey.frame, "\(label) \(letter)")
                let centre = CGPoint(x: hexKey.frame.midX, y: hexKey.frame.midY)
                XCTAssertEqual(hex.hitTest(centre)?.kind, .character(letter), "\(label) \(letter)")
                XCTAssertTrue(hexKey.hitFrame.minX <= hexKey.frame.minX && hexKey.hitFrame.maxX >= hexKey.frame.maxX, "\(label) \(letter)")
                XCTAssertTrue(hexKey.hitFrame.minY <= hexKey.frame.minY && hexKey.hitFrame.maxY >= hexKey.frame.maxY, "\(label) \(letter)")
            }
            for row in 0..<3 {
                let rowKeys = typr.keys.filter { $0.row == row && letters.contains($0.character ?? "") }
                let span = rowKeys.map(\.frame).reduce(rowKeys[0].frame) { $0.union($1) }
                var y = span.minY
                while y <= span.maxY {
                    var x = span.minX
                    while x <= span.maxX {
                        let point = CGPoint(x: x, y: y)
                        let expected = typr.hitTest(point)?.character
                        XCTAssertNotNil(expected, "\(label) at \(point)")
                        XCTAssertEqual(hex.hitTest(point)?.kind, expected.map { .character($0) }, "\(label) at \(point)")
                        x += 2
                    }
                    y += 2
                }
            }
        }
    }

    /// The Duo and the iPad keep Hex's rows.
    func testDuoAndPadKeepHexsRows() {
        let cover = KeyboardMetrics.for(.portrait, posture: .cover)
        XCTAssertEqual(cover.keyHeight, 45)
        XCTAssertEqual(cover.stripHeight, KeyboardMetrics.coverStripHeight)
        let tall = KeyboardMetrics.for(.portrait, posture: .unfoldedTall)
        XCTAssertEqual(tall.keyHeight, 46)
        XCTAssertEqual(tall.stripHeight, KeyboardMetrics.insetStripHeight)
        XCTAssertEqual(KeyboardMetrics.for(.landscape, posture: .unfoldedWide).keyHeight, KeyboardMetrics.landscape.keyHeight)
        for placement in [KeyboardPadPlacement.docked(.mini), .docked(.large), .floating] {
            XCTAssertEqual(KeyboardMetrics.for(.portrait, pad: placement), .pad(placement, orientation: .portrait), "\(placement)")
            XCTAssertEqual(KeyboardMetrics.for(.portrait, pad: placement).stripHeight, KeyboardMetrics.insetStripHeight, "\(placement)")
        }
    }

    /// Each language offers Hex's arrangements: QWERTZ beside German's own, AZERTY for French,
    /// Dvorak for English.
    func testLanguagesOfferHexsLetterArrangements() {
        XCTAssertEqual(KeyboardLanguage.german.letterLayouts.first, .own)
        XCTAssertTrue(KeyboardLanguage.german.letterLayouts.contains(.qwertz))
        XCTAssertTrue(KeyboardLanguage.german.letterLayouts.contains(.qwerty))
        XCTAssertTrue(KeyboardLanguage.english.letterLayouts.contains(.dvorak))
        XCTAssertEqual(
            KeyboardLayout.characterRows(for: .letters, language: .french).first?.joined(),
            "azertyuiop"
        )
        for language in KeyboardLanguage.allCases {
            for arrangement in language.letterLayouts {
                let layout = KeyboardLayout(width: 393, language: language, letters: arrangement)
                XCTAssertEqual(layout.totalHeight, 253, "\(language) \(arrangement)")
            }
        }
    }

    private func layout(_ width: CGFloat, _ size: KeyboardPhoneSize) -> KeyboardLayout {
        KeyboardLayout(width: width, phoneSize: size)
    }

    private func assertSameRows(_ hex: KeyboardMetrics, _ typr: TyprKeyboardMetrics, _ label: String) {
        XCTAssertEqual(hex.side, typr.side, label)
        XCTAssertEqual(hex.gap, typr.gap, label)
        XCTAssertEqual(hex.rowGap, typr.rowGap, label)
        XCTAssertEqual(hex.keyHeight, typr.keyHeight, label)
        XCTAssertEqual(hex.stripTop, typr.stripTop, label)
        XCTAssertEqual(hex.stripHeight, typr.stripHeight, label)
        XCTAssertEqual(hex.stripBottom, typr.stripBottom, label)
        XCTAssertEqual(hex.keysTop, typr.keysTop, label)
        XCTAssertEqual(hex.keysBottom, typr.keysBottom, label)
        XCTAssertEqual(hex.totalHeight, typr.stripArea + typr.keysArea, label)
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, _ label: String) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.001, label)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.001, label)
        XCTAssertEqual(a.width, b.width, accuracy: 0.001, label)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001, label)
    }
}
