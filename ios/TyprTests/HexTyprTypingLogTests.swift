import UIKit
import XCTest
@testable import Typr

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
        type("hello w ")
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
        type(" x ")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.commit?.kind, .autocorrect)
        XCTAssertEqual(word.commit?.text, "the")
        XCTAssertEqual(word.corrections, [.init(kind: .undo, from: "the", to: "teh")])
        XCTAssertEqual(word.meant, "teh")
    }

    func testAcceptedAutocorrectionIsTheMeantWord() throws {
        type("teh x ")
        let word = try XCTUnwrap(written.first)
        XCTAssertEqual(word.literal, "teh")
        XCTAssertEqual(word.meant, "the")
    }

    func testBackspaceRetypeKeepsErasedTaps() throws {
        type("hrl")
        tap(.delete)
        tap(.delete)
        type("ello x ")
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

    func testEmojiSearchRecordsNothing() {
        let document = HexFixtureTextTarget()
        document.autocapitalizationType = UITextAutocapitalizationType.none
        let routed = EmojiRoutedTarget(document: document)
        let typr = TyprAutocorrectEngine(checker: Checker(), learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        engine = FullKeyboardEngine(target: routed, autocorrect: TyprAutocorrectAdapter(engine: typr))
        engine.typrTypingLog = TypingLogRecorder(write: { [unowned self] in self.written.append($0) },
                                                 now: { [unowned self] in self.wall })
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        routed.query = ""
        engine.configureForField()
        type("hello world ")
        routed.query = nil
        engine.configureForField()
        XCTAssertEqual(written, [])
        type("cat")
        engine.configureForField()
        XCTAssertEqual(written.map(\.meant), ["cat"])
    }

    func testAJoinIsOneWordWithBothWordsAndTheSpaceAndExportsForReplay() throws {
        let sources = try XCTUnwrap(BundledKeyboardData.lexicons)
        let typr = TyprAutocorrectEngine(
            checker: KeyboardBoundaryDecoderTests.Checker(sources[.english], trusted: []),
            learning: KeyboardLearningSession(defaults: defaults),
            spatialDecoder: SpatialWordDecoder(lexicons: sources),
            contextResources: KeyboardContextResources(model: BundledKeyboardData.contextModel))
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        engine = FullKeyboardEngine(target: target, autocorrect: TyprAutocorrectAdapter(engine: typr))
        engine.typrTypingLog = TypingLogRecorder(write: { [unowned self] in self.written.append($0) },
                                                 now: { [unowned self] in self.wall })
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()

        let grid = TyprKeyboardLayout(width: 393)
        let typrSpace = try XCTUnwrap(grid.key(.space)).frame
        let typrV = try XCTUnwrap(grid.key(.character("v"))).frame
        let hexSpace = try XCTUnwrap(engine.layout.key(.space)).frame
        let straySpace = CGPoint(x: hexSpace.midX + (typrV.midX - typrSpace.midX) / typrSpace.width * hexSpace.width,
                                 y: hexSpace.minY + 1)
        func letters(_ word: String) throws {
            for letter in word {
                let key = try XCTUnwrap(engine.layout.key(.character(String(letter))))
                engine.insert(String(letter), source: "key", at: CGPoint(x: key.frame.midX, y: key.frame.midY))
                now += 0.1
            }
        }
        func space(at point: CGPoint) {
            engine.touchBegan(id: 1, at: point)
            engine.touchEnded(id: 1, at: point)
            now += 0.1
        }
        let centredSpace = try XCTUnwrap(engine.layout.key(.space)).frame
        try letters("think")
        space(at: CGPoint(x: centredSpace.midX, y: centredSpace.midY))
        try letters("obser")
        space(at: straySpace)
        try letters("e")
        space(at: CGPoint(x: centredSpace.midX, y: centredSpace.midY))
        XCTAssertEqual(target.text, "think observe ")
        engine.configureForField()

        XCTAssertEqual(written.map(\.meant), ["think", "observe"])
        let joined = try XCTUnwrap(written.last)
        XCTAssertEqual(joined.literal, "obser e")
        XCTAssertEqual(joined.taps.map(\.text), ["o", "b", "s", "e", "r", " ", "e"])
        XCTAssertEqual(joined.taps.map(\.t), [0, 100, 200, 300, 400, 500, 600])
        XCTAssertFalse(joined.taps.contains { $0.x == nil || $0.y == nil })
        XCTAssertEqual(joined.commit?.kind, .autocorrect)
        XCTAssertEqual(joined.commit?.text, "observe")
        XCTAssertEqual(joined.end, " ")
        XCTAssertEqual(joined.corrections, [])
        XCTAssertEqual(joined.layout, TypingLogLayout(grid))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TyprTypingLogStore(directory: directory)
        written.forEach(store.append)
        store.waitForWrites()
        let file = try store.export(learning: typr.learning.model.state, protectedWords: [], appBuild: "hex-join-test",
                                    into: directory, now: wall)
        let data = try Data(contentsOf: file)
        XCTAssertEqual(try TypingLogExport.decoder().decode(TypingLogExport.self, from: data).words, written)
        print("HEX-TYPING-LOG-EXPORT " + data.base64EncodedString())
    }

    func testHexWritesWhatTyprsKeyboardWritesForTheSameTyping() throws {
        type("teh hrl")
        tap(.delete)
        tap(.delete)
        type("ello x ")
        engine.configureForField()
        let hex = written

        written = []
        let typrTarget = FixtureTextTarget()
        typrTarget.autocapitalizationType = UITextAutocapitalizationType.none
        let typr = TyprFullKeyboardEngine(
            target: typrTarget,
            autocorrect: TyprAutocorrectEngine(checker: Checker(), learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil),
            typingLog: TypingLogRecorder(write: { [unowned self] in self.written.append($0) }, now: { [unowned self] in self.wall }))
        typr.width = 393
        typr.clock = { [unowned self] in self.now }
        typr.configureForField()
        func press(_ kind: TyprKeyKind) {
            let frame = typr.layout.key(kind)!.frame
            let point = CGPoint(x: frame.midX, y: frame.midY)
            typr.touchBegan(id: 1, at: point)
            typr.touchEnded(id: 1, at: point)
            now += 0.1
        }
        func typeOnTypr(_ text: String) {
            for character in text { press(character == " " ? .space : .character(String(character))) }
        }
        typeOnTypr("teh hrl")
        press(.delete)
        press(.delete)
        typeOnTypr("ello x ")
        typr.configureForField()

        XCTAssertEqual(hex.map(\.meant), ["the", "hello", "x"])
        func shape(_ word: TypingLogWord) -> String {
            "\(word.meant)|\(word.literal)|\(word.end)|\(String(describing: word.commit))|\(word.languages)|"
                + "\(word.taps.map(\.text))|\(word.taps.map(\.key))|\(word.taps.map(\.t))|"
                + "\(word.corrections.map { "\($0.kind)\($0.erased?.map(\.text) ?? [])\($0.from ?? "")\($0.to ?? "")\($0.chip ?? "")" })"
        }
        XCTAssertEqual(hex.map(shape), written.map(shape))
    }
}
