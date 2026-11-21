import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardLetterLayoutTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "KeyboardLetterLayoutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testGermanAndEnglishDefaultToTheUnchangedQwertyKeys() {
        let settings = FullKeyboardSettings(defaults: defaults)
        XCTAssertEqual(settings.letters(for: .german), .qwerty)
        XCTAssertEqual(settings.letters(for: .english), .qwerty)
        XCTAssertEqual(settings.letters, .qwerty)
        let rows = KeyboardLayout(width: 393).keys.filter { $0.character != nil && $0.row < 3 }
        XCTAssertEqual(rows.map { $0.character! }.joined(), "qwertyuiopasdfghjklzxcvbnm")
        XCTAssertEqual(KeyboardLayout(width: 393), KeyboardLayout(width: 393, letters: .qwerty))
    }

    func testEveryLayoutDrawsTheAlphabetInsideTheKeyboardWithoutOverlaps() {
        let poses: [(CGFloat, KeyboardOrientation, CGFloat)] = [
            (320, .portrait, 0), (393, .portrait, 0), (440, .portrait, 0), (852, .landscape, 0),
            (669, .widePortrait, 0), (951, .wideLandscape, 0), (801, .splitLandscape, 20),
        ]
        for letters in KeyboardLetterLayout.allCases {
            for (width, orientation, inset) in poses {
                for numberRow in [false, true] {
                    for splitColumns in [false, true] {
                        let layout = KeyboardLayout(width: width, orientation: orientation, numberRow: numberRow,
                                                    splitColumns: splitColumns, letters: letters, horizontalInset: inset)
                        let name = "\(letters) \(orientation) \(width) number row \(numberRow) aligned \(splitColumns)"
                        let alphabet = Set(layout.keys.compactMap(\.character).filter { $0.first!.isLetter })
                        XCTAssertEqual(alphabet.count, 26, name)
                        XCTAssertEqual(layout.keys.filter { $0.kind == .delete }.count, 1, name)
                        XCTAssertNotNil(layout.key(.shift), name)
                        for key in layout.keys {
                            XCTAssertGreaterThanOrEqual(key.frame.minX, -0.01, name)
                            XCTAssertLessThanOrEqual(key.frame.maxX, width + 0.01, name)
                        }
                        for (index, key) in layout.keys.enumerated() {
                            for other in layout.keys[(index + 1)...] {
                                XCTAssertFalse(key.frame.insetBy(dx: 0.01, dy: 0.01).intersects(other.frame),
                                               "\(name): \(key.label) overlaps \(other.label)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testQwertzSwapsYAndZAndAzertyMovesA() {
        let qwerty = KeyboardLayout(width: 393)
        let qwertz = KeyboardLayout(width: 393, letters: .qwertz)
        let azerty = KeyboardLayout(width: 393, letters: .azerty)
        XCTAssertEqual(qwertz.key(.character("z"))?.frame, qwerty.key(.character("y"))?.frame)
        XCTAssertEqual(qwertz.key(.character("y"))?.frame, qwerty.key(.character("z"))?.frame)
        XCTAssertEqual(azerty.key(.character("a"))?.frame, qwerty.key(.character("q"))?.frame)
        XCTAssertEqual(KeyboardLayout(width: 393, letters: .dvorak).key(.delete)?.row, 0)
    }

    func testTypingFollowsTheChosenLayout() {
        let target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let autocorrect = AutocorrectEngine(learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        autocorrect.isEnabled = false
        let engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = 393
        engine.configureForField()
        let qwertyY = KeyboardLayout(width: 393).key(.character("y"))!.frame
        engine.letters = .qwertz
        engine.touchBegan(id: 1, at: CGPoint(x: qwertyY.midX, y: qwertyY.midY))
        engine.touchEnded(id: 1, at: CGPoint(x: qwertyY.midX, y: qwertyY.midY))
        XCTAssertEqual(target.text, "z")
        XCTAssertEqual(engine.autocorrect.letters, .qwertz)
        XCTAssertEqual(SwipeLayout(layout: engine.layout)?.centers, SwipeLayout(layout: KeyboardLayout(width: 393, letters: .qwertz))?.centers)
    }

    func testNeighbouringKeysFollowTheLayout() {
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("t", "y", on: .qwerty))
        XCTAssertFalse(AutocorrectEngine.areAdjacentKeys("t", "z", on: .qwerty))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("t", "z", on: .qwertz))
        XCTAssertFalse(AutocorrectEngine.areAdjacentKeys("t", "y", on: .qwertz))
        let onQwertz = AutocorrectEngine.singleEditKeyboardCost(from: "tu", to: "zu", on: .qwertz)!
        let onQwerty = AutocorrectEngine.singleEditKeyboardCost(from: "tu", to: "zu", on: .qwerty)!
        XCTAssertLessThan(onQwertz, onQwerty)
    }

    func testLearnedTouchesAndTypingLogsKeepTheLayout() throws {
        let qwerty = KeyboardLayoutSignature(KeyboardLayout(width: 393))
        let qwertz = KeyboardLayoutSignature(KeyboardLayout(width: 393, letters: .qwertz))
        XCTAssertNotEqual(qwerty.id, qwertz.id)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardLayoutSignature.self, from: JSONEncoder().encode(qwertz)), qwertz)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(qwerty), as: UTF8.self).contains("letters"))
        XCTAssertNil(TypingLogLayout(KeyboardLayout(width: 393)).letters)
        XCTAssertEqual(TypingLogLayout(KeyboardLayout(width: 393, letters: .dvorak)).keyboardLayout?.letters, .dvorak)
    }

    func testEachLanguageStoresItsLayoutAndTheFirstSelectedLanguageShowsIt() {
        let settings = FullKeyboardSettings(defaults: defaults)
        let typr = TyprSettings(defaults: defaults)
        settings.setLetters(.qwertz, for: .german)
        settings.setLetters(.dvorak, for: .english)
        XCTAssertEqual(settings.letters(for: .german), .qwertz)
        XCTAssertEqual(settings.letters(for: .english), .dvorak)
        XCTAssertEqual(settings.letters, .qwertz)
        typr.autocorrectLanguageOrder = [.english, .german]
        XCTAssertEqual(settings.letters, .dvorak)
        typr.autocorrectEnglish = false
        XCTAssertEqual(settings.letters, .qwertz)
        typr.autocorrectGerman = false
        XCTAssertEqual(settings.letters, .dvorak)
    }
}
