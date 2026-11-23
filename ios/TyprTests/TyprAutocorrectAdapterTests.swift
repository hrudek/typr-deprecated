import UIKit
import XCTest
@testable import Typr

/// Typr's autocorrect behind Hex's `FullKeyboardEngine`, typed on Hex's keys.
@MainActor
final class TyprAutocorrectAdapterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var target: HexFixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var adapter: TyprAutocorrectAdapter!
    private var now: TimeInterval = 100
    private var runningSystemMajorVersion = 0

    private static let english: Set<String> = [
        "the", "its", "it's", "a", "nice", "day", "i", "like", "die", "well", "see",
    ]
    private static let german: Set<String> = ["für", "über", "die", "dich", "ich", "bin", "alles"]

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "TyprAutocorrectAdapterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        makeEngine()
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeEngine(contextWords: Bool = false) {
        let typr = TyprAutocorrectEngine(
            checker: Checker(valid: Self.english, guesses: ["teh": ["the"]]),
            learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil,
            contextResources: .init(model: BundledKeyboardData.contextModel))
        typr.choosesWordsFromContext = contextWords
        adapter = TyprAutocorrectAdapter(engine: typr) {
            GermanAutocorrect(checker: Checker(valid: Self.german, guesses: ["fur": ["für"], "uber": ["über"]]))
        }
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    private func tap(_ kind: KeyKind) {
        let key = engine.layout.key(kind)!
        let at = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: at)
        engine.touchEnded(id: 1, at: at)
    }

    private func type(_ text: String) {
        for character in text {
            tap(character == " " ? .space : .character(String(character)))
            now += 0.5
        }
    }

    private var learning: KeyboardLearningSession { adapter.engine.learning }

    func testTheStripShowsTyprsSuggestionsForTheWordBeingTyped() {
        type("teh")
        XCTAssertEqual(engine.suggestions.first?.kind, .keepLiteral)
        XCTAssertEqual(engine.suggestions.first?.replacement, "teh")
        let fix = engine.suggestions.first { $0.replacement == "the" }
        XCTAssertEqual(fix?.willAutoReplace, true)
    }

    func testSpaceAppliesTyprsCorrection() {
        type("teh ")
        XCTAssertEqual(target.text, "the ")
    }

    func testRevertPutsBackWhatWasTypedAndTyprLearnsTheRejection() {
        type("teh ")
        tap(.delete)
        XCTAssertEqual(target.text, "the")
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "teh")
        XCTAssertTrue(learning.protections.isRejected(typed: "teh", replacement: "the"))
        XCTAssertFalse(learning.protections.isKept("teh"), "a revert rejects the fix, as on Typr's keyboard")
    }

    func testPickingWhatWasTypedKeepsItInTyprsLexicon() {
        type("teh")
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "teh ")
        XCTAssertTrue(learning.protections.isKept("teh"))
    }

    func testProtectedPersonalLexiconKeepsItsWords() {
        var builder = ProtectedPersonalLexicon.Builder()
        builder.add("teh")
        adapter.engine.loadProtectedLexicon(builder.build())
        type("teh ")
        XCTAssertEqual(target.text, "teh ")
    }

    func testWordsFromContextRevisesTheWordBeforeOnlyWhenOn() {
        type("its a nice day ")
        XCTAssertEqual(target.text, "its a nice day ")
        makeEngine(contextWords: true)
        type("its a nice day ")
        XCTAssertEqual(target.text, "it's a nice day ")
    }

    func testRevertingARevisionRejectsIt() {
        makeEngine(contextWords: true)
        type("its a ")
        XCTAssertEqual(target.text, "it's a ")
        tap(.delete)
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "its a")
        XCTAssertTrue(learning.protections.isRejected(typed: "its", replacement: "it's"))
    }

    func testGermanWithEnglishPartnerUsesTyprsBilingualRevision() {
        engine.language = .german
        engine.partnerLanguage = .english
        XCTAssertEqual(engine.partnerLanguage, .english)
        XCTAssertNotNil(adapter.engine.german)
        XCTAssertTrue(adapter.engine.englishEnabled)
        XCTAssertEqual(adapter.engine.preferredLanguage, .german)
        type("fur dich ")
        XCTAssertEqual(target.text, "für dich ")
    }

    func testEnglishAloneDropsTyprsGermanLayer() {
        engine.language = .german
        XCTAssertNotNil(adapter.engine.german)
        XCTAssertFalse(adapter.engine.englishEnabled)
        engine.language = .english
        XCTAssertNil(adapter.engine.german)
        XCTAssertTrue(adapter.engine.englishEnabled)
    }

    func testALanguageTyprCannotReadGetsNoCorrections() {
        engine.language = .spanish
        type("teh")
        XCTAssertTrue(engine.suggestions.isEmpty)
        type(" ")
        XCTAssertEqual(target.text, "teh ")
    }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    let table: [String: [String]]
    init(valid: Set<String>, guesses: [String: [String]]) { self.valid = valid; table = guesses }
    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { table[word.lowercased()] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
}
