import UIKit
import XCTest
@testable import Typr

/// Hex #2231 (the next word gives the word before its language's umlauts) and #2144
/// (punctuation corrects first; Words from context), German first.
@MainActor
final class BilingualRevisionTests: XCTestCase {
    private var target: FixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 200

    private static let english: Set<String> = [
        "fur", "die", "coats", "i", "like", "uber", "the", "its", "it's", "a", "nice", "day", "id", "I'd",
        "more", "then", "than", "that", "on", "way", "well", "we'll", "done", "dog", "wagged", "tail",
        "lets", "let's", "go", "see",
    ]
    private static let german: Set<String> = [
        "für", "über", "die", "dich", "ich", "bin", "alles", "wie", "schon", "geht", "gehts", "gibts",
    ]

    private func makeEngine(german: Bool = true, english: Bool = true, contextWords: Bool = false) {
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let autocorrect = AutocorrectEngine(
            checker: Checker(valid: Self.english, guesses: ["teh": ["the"]]),
            learning: KeyboardLearningSession(state: PersonalTypingModel.State()), spatialDecoder: nil,
            contextResources: .init(model: BundledKeyboardData.contextModel))
        autocorrect.englishEnabled = english
        if german {
            autocorrect.german = GermanAutocorrect(checker: Checker(
                valid: Self.german, guesses: ["fur": ["für"], "uber": ["über"], "shcon": ["schon"]]))
        }
        autocorrect.choosesWordsFromContext = contextWords
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
        now += 0.2
    }

    /// Letters, spaces and marks as typed; a mark comes from the 123 page.
    private func type(_ text: String) {
        for character in text {
            let s = String(character)
            if s == " " {
                tap(.space)
            } else if character.isLetter {
                if character.isUppercase != engine.isUppercase { tap(.shift) }
                tap(.character(s.lowercased()))
            } else {
                tap(.layerSwitch(.numbers))
                tap(.character(s))
                if engine.layerState.layer != .letters { tap(.layerSwitch(.letters)) }
            }
        }
    }

    private func typed(_ text: String, german: Bool = true, english: Bool = true, contextWords: Bool = false) -> String {
        makeEngine(german: german, english: english, contextWords: contextWords)
        type(text)
        return target.text
    }

    func testTheNextGermanWordGivesTheWordBeforeItsUmlauts() {
        XCTAssertEqual(typed("fur dich "), "für dich ")
        XCTAssertEqual(typed("ich bin fur dich "), "ich bin für dich ")
        XCTAssertEqual(typed("uber alles "), "über alles ")
        XCTAssertEqual(typed("Fur dich "), "Für dich ")
        XCTAssertEqual(typed("fur die "), "für die ", "die leans German by the typing models")
        XCTAssertEqual(typed("fur dich."), "für dich.", "a closing mark finishes the next word too")
    }

    func testTheWordBeforeStaysWhenNothingSaysGerman() {
        XCTAssertEqual(typed("fur "), "fur ", "no next word yet")
        XCTAssertEqual(typed("i like fur coats "), "I like fur coats ", "an English word after it")
        XCTAssertEqual(typed("i like fur die "), "I like fur die ", "English words before it")
        XCTAssertEqual(typed("fur dich ", german: false), "fur dich ", "German off")
        XCTAssertEqual(typed("fur ", english: false), "für ", "German alone fixes it at its own space, as before")
    }

    func testOneDeleteTakesTheRevisionBack() {
        makeEngine()
        type("fur dich ")
        XCTAssertEqual(target.text, "für dich ")
        XCTAssertTrue(engine.deleteUndoes, "Delete shows that it undoes the revision")
        engine.deleteBackward()
        XCTAssertEqual(target.text, "fur dich")
        type(" ")
        XCTAssertEqual(target.text, "fur dich ", "an undone revision is not made again")
        type("fur dich ")
        XCTAssertEqual(target.text, "fur dich fur dich ", "nor for the rest of the session")
    }

    func testPunctuationAfterATypoFixesItFirst() {
        XCTAssertEqual(typed("teh;"), "the;")
        XCTAssertEqual(typed("shcon;"), "schon;")
        XCTAssertEqual(typed("teh:"), "teh:", "a colon often ends a label or scheme (Fwd:, ftp:), left as typed")
        XCTAssertEqual(typed("(teh)"), "(the)")
        XCTAssertEqual(typed("(shcon)"), "(schon)")
        XCTAssertEqual(typed("see you ;)"), "see you ;)", "a space before an emoticon stays")
        XCTAssertEqual(typed("ok :)"), "ok :)")
    }

    func testWordsFromContextIsOffByDefault() {
        XCTAssertTrue(ExperimentalSwitch.all.contains(.wordsFromContext))
        XCTAssertEqual(typed("its a nice day "), "its a nice day ")
        XCTAssertEqual(typed("wie gehts "), "wie gehts ")
    }

    func testWordsFromContextFollowTheWordsAround() {
        XCTAssertEqual(typed("wie gehts ", contextWords: true), "wie geht's ")
        XCTAssertEqual(typed("gibts ", contextWords: true), "gibt's ")
        XCTAssertEqual(typed("its a nice day ", german: false, contextWords: true), "it's a nice day ")
        XCTAssertEqual(typed("id like ", german: false, contextWords: true), "I'd like ")
        XCTAssertEqual(typed("lets go ", german: false, contextWords: true), "let's go ")
        XCTAssertEqual(typed("more then that ", german: false, contextWords: true), "more than that ")
        XCTAssertEqual(typed("ID ", german: false, contextWords: true), "ID ", "an abbreviation in capitals")
        XCTAssertEqual(typed("on its way ", german: false, contextWords: true), "on its way ")
        XCTAssertEqual(typed("well done ", german: false, contextWords: true), "well done ")
        XCTAssertEqual(typed("the dog wagged its tail ", german: false, contextWords: true), "the dog wagged its tail ")
    }

    func testWordsFromContextUndoKeepsWhatWasTyped() {
        makeEngine(german: false, contextWords: true)
        type("its a ")
        XCTAssertEqual(target.text, "it's a ")
        engine.deleteBackward()
        XCTAssertEqual(target.text, "its a")
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
