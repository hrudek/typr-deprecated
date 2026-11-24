import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprLearningHooksTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!
    private var runningSystemMajorVersion = 0
    private var shared: SharedKeyboardLearning!
    private var target: HexFixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var adapter: TyprAutocorrectAdapter!

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "TyprLearningHooksTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        shared = SharedKeyboardLearning { [unowned self] in self.makeSession() }
        makeEngine()
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession() -> KeyboardLearningSession {
        KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
                                defaults: defaults, debounce: .seconds(3600))
    }

    private var learning: KeyboardLearningSession { shared.session(fullAccess: true) }

    private func makeEngine(secure: Bool = false, keyboardType: UIKeyboardType = .default) {
        let typr = TyprAutocorrectEngine(
            checker: Checker(valid: ["hello", "world", "the"], guesses: ["teh": ["the"]]),
            learning: learning, spatialDecoder: nil, contextResources: .init(model: nil))
        adapter = TyprAutocorrectAdapter(engine: typr)
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        target.isSecureTextEntry = secure
        target.keyboardType = keyboardType
        engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        engine.width = 393
        engine.configureForField()
    }

    private func centre(_ kind: KeyKind) throws -> CGPoint {
        let key = try XCTUnwrap(engine.layout.key(kind))
        return CGPoint(x: key.frame.midX, y: key.frame.midY)
    }

    private func tap(_ kind: KeyKind) throws {
        let point = try centre(kind)
        engine.touchBegan(id: 1, at: point)
        engine.touchEnded(id: 1, at: point)
    }

    private func type(_ text: String) throws {
        for character in text {
            if character == " " {
                try tap(.space)
            } else {
                engine.insert(String(character), source: nil, at: try centre(.character(String(character))))
            }
        }
    }

    private func count(_ word: String) -> Int {
        learning.model.lexicon.counts[word] ?? 0
    }

    func testTheNextLetterSettlesTheWordBeforeIt() throws {
        try type("hello ")
        XCTAssertEqual(count("hello"), 0, "not before the next word starts")
        try type("w")
        XCTAssertEqual(count("hello"), 1)
        XCTAssertGreaterThan(learning.diagnostics.acceptedLabels, 0, "its taps teach Typr's touch model")
    }

    func testADeleteBeforeTheNextLetterTeachesNothing() throws {
        try type("hello ")
        try tap(.delete)
        try type(" w")
        XCTAssertEqual(count("hello"), 0)
    }

    func testTheHostEchoingTheKeysTextKeepsTheWordToLearn() throws {
        try type("hello ")
        engine.textDidChange()
        try type("w")
        XCTAssertEqual(count("hello"), 1)
    }

    func testAnEditElsewhereDropsTheWordToLearn() throws {
        try type("hello ")
        target.insertText("hello ")
        engine.textDidChange()
        try type("w")
        XCTAssertEqual(count("hello"), 0)
    }

    func testKeepingWhatWasTypedCountsItOnceAndSurvivesTheHandover() throws {
        try type("teh")
        let keep = try XCTUnwrap(engine.suggestions.first { $0.kind == .keepLiteral })
        engine.acceptSuggestion(keep)
        XCTAssertEqual(target.text, "teh ")
        XCTAssertTrue(learning.protections.isKept("teh"))
        XCTAssertEqual(count("teh"), 1)
        shared.flush()
        XCTAssertTrue(makeSession().protections.isKept("teh"), "the one shared session wrote it")
    }

    func testASpaceTapIsLearnedOnceTheNextWordConfirmsIt() throws {
        try type("hello world ")
        XCTAssertGreaterThan(learning.diagnostics.acceptedBySource[TouchLabelSource.space.rawValue, default: 0], 0)
    }

    func testASecureFieldTeachesNothing() throws {
        makeEngine(secure: true)
        try type("hello w")
        try type("teh")
        engine.suggestions.first { $0.kind == .keepLiteral }.map(engine.acceptSuggestion)
        XCTAssertEqual(count("hello"), 0)
        XCTAssertFalse(learning.protections.isKept("teh"))
        XCTAssertEqual(learning.diagnostics.acceptedLabels, 0)
    }

    func testNoJoinOutsideTextFields() throws {
        for type in [UIKeyboardType.URL, .emailAddress] {
            makeEngine(keyboardType: type)
            _ = adapter.suggestions(beforeInput: "a out", field: type == .URL ? .url : .email, autocorrectionType: .default,
                                    predictionModel: nil, capitalizesNext: false)
            let boundaries = learning.diagnostics[.boundaries]
            XCTAssertNil(adapter.merge(first: "a", firstTaps: [.zero], space: .zero, second: "out", before: "a"))
            XCTAssertEqual(learning.diagnostics[.boundaries], boundaries, "\(type.rawValue): never asked")
        }
    }

    func testHexsOwnAutocorrectIgnoresTheHooks() {
        let hex = AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults))
        hex.isSecureField = true
        XCTAssertFalse(hex.isSecureField)
        hex.typedLetter("a", before: "", after: "a")
        hex.pickedSuggestion(KeyboardSuggestion(displayText: "a", replacement: "a", kind: .keepLiteral), replacing: "a", before: "a")
        hex.tappedSpace(at: .zero, after: "a ")
        hex.textEdited()
    }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    let table: [String: [String]]
    init(valid: Set<String>, guesses: [String: [String]]) { self.valid = valid; table = guesses }
    func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
    func guesses(for word: String) -> [String] { table[word.lowercased()] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
}
