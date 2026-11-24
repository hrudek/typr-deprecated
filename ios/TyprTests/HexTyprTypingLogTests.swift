import UIKit
import XCTest
@testable import Typr

/// Typr's typing log on Hex's keyboard with Typr typing on: the words Typr's keyboard records.
@MainActor
final class HexTyprTypingLogTests: XCTestCase {
    private final class Checker: TyprTextChecking {
        func isWordValid(_ word: String) -> Bool { ["the", "hello", "world", "cat", "x", "w"].contains(word) }
        func guesses(for word: String) -> [String] { word == "teh" ? ["the"] : [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var target: HexFixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var written: [TypingLogWord] = []
    private var now: TimeInterval = 100
    private var runningSystemMajorVersion = 0
    private let wall = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suite = "HexTyprTypingLogTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        written = []
        makeEngine()
    }

    override func tearDown() async throws {
        engine = nil
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeEngine(typrTyping: Bool = true, configure: (HexFixtureTextTarget) -> Void = { _ in }) {
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        configure(target)
        let typr = TyprAutocorrectEngine(checker: Checker(), learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        let adapter = typrTyping ? TyprAutocorrectAdapter(engine: typr) : nil
        engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        engine.typrTypingLog = TypingLogRecorder(write: { [unowned self] in self.written.append($0) },
                                                 now: { [unowned self] in self.wall })
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    private func tap(_ kind: KeyKind) {
        let key = engine.layout.key(kind)!
        let at = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: at)
        engine.touchEnded(id: 1, at: at)
        now += 0.1
    }

    private func type(_ text: String) {
        for character in text { tap(character == " " ? .space : .character(String(character))) }
    }

    func testSettledWordRecordsTapsOnTyprsLayout() throws {
        type("hello w")
        XCTAssertEqual(written.count, 1)
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.meant, "hello")
        XCTAssertEqual(word.literal, "hello")
        XCTAssertEqual(word.end, " ")
        XCTAssertEqual(word.commit, .init(kind: .literal, text: "hello"))
        XCTAssertEqual(word.languages, ["en"])
        XCTAssertEqual(word.taps.map(\.key), ["h", "e", "l", "l", "o"])
        XCTAssertEqual(word.taps.map(\.t), [0, 100, 200, 300, 400])
        let typrLayout = TyprKeyboardLayout(width: 393)
        XCTAssertEqual(word.layout, TypingLogLayout(typrLayout))
        let tap = try XCTUnwrap(word.taps.first)
        let point = CGPoint(x: try XCTUnwrap(tap.x), y: try XCTUnwrap(tap.y))
        XCTAssertTrue(typrLayout.key(.character("h"))!.hitFrame.contains(point), "\(point)")
    }

    func testAutocorrectionThenRevertRecordsBothAndTheRestoredWord() throws {
        type("teh ")
        XCTAssertEqual(target.text, "the ")
        tap(.delete)
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "teh")
        type(" x")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.commit?.kind, .autocorrect)
        XCTAssertEqual(word.commit?.text, "the")
        XCTAssertEqual(word.corrections, [.init(kind: .undo, from: "the", to: "teh")])
        XCTAssertEqual(word.meant, "teh")
    }

    func testAcceptedAutocorrectionIsTheMeantWord() throws {
        type("teh x")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.literal, "teh")
        XCTAssertEqual(word.meant, "the")
    }

    func testBackspaceRetypeKeepsErasedTaps() throws {
        type("hrl")
        tap(.delete)
        tap(.delete)
        type("ello x")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.meant, "hello")
        XCTAssertEqual(word.literal, "hello")
        XCTAssertEqual(word.corrections.map(\.kind), [.backspace])
        XCTAssertEqual(word.corrections.first?.erased?.map(\.text), ["r", "l"])
    }

    func testPickingWhatWasTypedIsAKeepPick() throws {
        type("teh")
        XCTAssertEqual(engine.suggestions.first?.kind, .keepLiteral)
        engine.acceptSuggestion(engine.suggestions[0])
        type("x ")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.meant, "teh")
        XCTAssertEqual(word.commit?.kind, .pick)
        XCTAssertEqual(word.corrections, [.init(kind: .pick, from: "teh", to: "teh", chip: "keep")])
    }

    func testFieldChangeSettlesTheOpenWord() {
        type("cat")
        engine.configureForField()
        XCTAssertEqual(written.map(\.meant), ["cat"])
        XCTAssertEqual(written.first?.end, "field")
    }

    func testSecureURLEmailAndNoAutocorrectFieldsRecordNothing() {
        let fields: [(HexFixtureTextTarget) -> Void] = [
            { $0.isSecureTextEntry = true },
            { $0.keyboardType = .URL },
            { $0.keyboardType = .emailAddress },
            { $0.autocorrectionType = .no },
        ]
        for configure in fields {
            makeEngine(configure: configure)
            type("hello w")
            engine.configureForField()
        }
        XCTAssertEqual(written, [])
    }

    func testNothingIsRecordedWhileLearningIsOff() {
        TyprSettings(defaults: defaults).personalLearning = false
        makeEngine()
        type("hello world ")
        engine.configureForField()
        XCTAssertEqual(written, [])
    }

    func testHexTypingRecordsNothing() {
        makeEngine(typrTyping: false)
        type("hello world ")
        engine.configureForField()
        XCTAssertEqual(written, [])
    }
}
