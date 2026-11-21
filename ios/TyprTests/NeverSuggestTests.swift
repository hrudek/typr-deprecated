import UIKit
import XCTest
@testable import Typr

@MainActor
final class NeverSuggestTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var target: FixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 200

    private static let german = [
        "schwuchtek": ["Schwuchtel"], "negrr": ["Neger"], "schlanpe": ["Schlampe"], "ficke": ["Dicke"],
        "jaus": ["Haus"],
    ]
    private static let english = ["niggee": ["nigger"], "retatd": ["retard"], "fucj": ["fuck"], "teh": ["the"]]

    override func setUp() async throws {
        suiteName = "NeverSuggestTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        makeEngine()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeEngine(learned: [String] = [], swearing: Bool = false) {
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        var state = PersonalTypingModel.State()
        for word in learned { state.kept[word] = Date() }
        let autocorrect = AutocorrectEngine(checker: Checker(valid: ["the"], guesses: Self.english),
                                            learning: KeyboardLearningSession(state: state), spatialDecoder: nil)
        autocorrect.german = GermanAutocorrect(checker: Checker(valid: ["Haus", "Dicke"], guesses: Self.german))
        autocorrect.allowsSwearing = swearing
        engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    private func tap(_ kind: KeyKind) {
        let key = engine.layout.key(kind)!
        let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: center)
        engine.touchEnded(id: 1, at: center)
        now += 0.45
    }

    private func stripThenSpace(_ word: String) async -> [String] {
        for letter in word { tap(.character(String(letter))) }
        await engine.waitForSuggestions()
        let strip = engine.suggestions.map { $0.replacement.lowercased() }
        tap(.space)
        return strip
    }

    func testGermanSlurIsNeverSuggestedOrAutocorrectedInto() async {
        for swearing in [false, true] {
            makeEngine(swearing: swearing)
            let strip = await stripThenSpace("schwuchtek")
            XCTAssertFalse(strip.contains("schwuchtel"))
            _ = await stripThenSpace("negrr")
            XCTAssertEqual(target.text, "schwuchtek negrr ")
        }
    }

    func testEnglishSlurIsNeverSuggestedOrAutocorrectedInto() async {
        for swearing in [false, true] {
            makeEngine(swearing: swearing)
            let strip = await stripThenSpace("niggee")
            XCTAssertFalse(strip.contains("nigger"))
            _ = await stripThenSpace("retatd")
            XCTAssertEqual(target.text, "niggee retatd ")
        }
    }

    func testOrdinaryWordsAreStillCorrected() async {
        _ = await stripThenSpace("jaus")
        _ = await stripThenSpace("teh")
        XCTAssertEqual(target.text, "Haus the ")
    }

    func testGermanSwearWordOnlyOnceLearnedOrAsked() async {
        let strip = await stripThenSpace("schlanpe")
        XCTAssertFalse(strip.contains("schlampe"))
        XCTAssertEqual(target.text, "schlanpe ")

        makeEngine(learned: ["schlampe"])
        _ = await stripThenSpace("schlanpe")
        XCTAssertEqual(target.text, "Schlampe ")

        makeEngine(swearing: true)
        _ = await stripThenSpace("schlanpe")
        XCTAssertEqual(target.text, "Schlampe ")
    }

    func testEnglishSwearWordOnlyOnceLearnedOrAsked() async {
        let strip = await stripThenSpace("fucj")
        XCTAssertFalse(strip.contains("fuck"))
        XCTAssertEqual(target.text, "fucj ")

        makeEngine(learned: ["fuck"])
        _ = await stripThenSpace("fucj")
        XCTAssertEqual(target.text, "fuck ")

        makeEngine(swearing: true)
        _ = await stripThenSpace("fucj")
        XCTAssertEqual(target.text, "fuck ")
    }

    func testSwearWordTypedInFullIsNotCorrectedIntoAnotherWord() async {
        _ = await stripThenSpace("ficke")
        XCTAssertEqual(target.text, "ficke ")
    }

    func testImportedWordIsOffered() {
        var builder = ProtectedPersonalLexicon.Builder()
        builder.add("Schlampe")
        engine.autocorrect.loadProtectedLexicon(builder.build())
        XCTAssertTrue(engine.autocorrect.mayOffer("Schlampe", before: ""))
        XCTAssertFalse(engine.autocorrect.mayOffer("Schwuchtel", before: ""))
    }

    func testTwoWordExpressionIsBlockedOnlyAsAPair() {
        XCTAssertFalse(engine.autocorrect.mayOffer("job", before: "a blow "))
        XCTAssertFalse(engine.autocorrect.mayOffer("blow job", before: ""))
        XCTAssertTrue(engine.autocorrect.mayOffer("job", before: "a new "))
        XCTAssertTrue(engine.autocorrect.mayOffer("blow", before: ""))
    }

    func testNextWordPredictionsSkipWordsTheyMayNotOffer() throws {
        let model = try XCTUnwrap(BundledKeyboardData.contextModel)
        for (previous, weightDE) in [("ich", 1.0), ("the", 0.0)] {
            let top = model.suggestions(after: previous, weightDE: weightDE)
            let first = try XCTUnwrap(top.first?.key)
            let filtered = model.suggestions(after: previous, weightDE: weightDE, allows: { $0 != first })
            XCTAssertEqual(filtered.count, top.count)
            XCTAssertFalse(filtered.contains { $0.key == first })
        }
    }
}

private final class Checker: TextChecking {
    let valid: Set<String>
    let table: [String: [String]]
    init(valid: Set<String>, guesses: [String: [String]]) { self.valid = valid; table = guesses }
    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { table[word.lowercased()] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
}
