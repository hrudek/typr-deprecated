import UIKit
import XCTest
@testable import Typr

@MainActor
final class TextReplacementTests: XCTestCase {
    private final class Checker: TextChecking {
        func isWordValid(_ word: String) -> Bool {
            ["ich", "nicht", "heute", "komme", "bis", "dann", "see", "you", "the", "and"].contains(word.lowercased())
        }
        func guesses(for word: String) -> [String] { ["nciht": ["nicht"], "teh": ["the"]][word] ?? [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private var defaults: UserDefaults!
    private var suite: String!
    private var target: FixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 100

    override func setUp() async throws {
        suite = "TextReplacementTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let autocorrect = AutocorrectEngine(checker: Checker(), learning: KeyboardLearningSession(defaults: defaults),
                                            spatialDecoder: nil)
        autocorrect.loadLexiconEntries([
            (userInput: "mfg", documentText: "Mit freundlichen Grüßen"),
            (userInput: "vlg", documentText: "viele liebe Grüße"),
            (userInput: "brb", documentText: "be right back"),
            (userInput: "omw", documentText: "On my way!"),
            (userInput: "mip", documentText: "My iPhone"),
            (userInput: "sgdh", documentText: "Sehr geehrte Damen und Herren,"),
            (userInput: "grü", documentText: "grüß dich"),
            (userInput: "ua", documentText: "unter anderem"),
        ])
        engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.scheduleAfter = { _, _ in }
        engine.configureForField()
    }

    override func tearDown() async throws {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func type(_ text: String) {
        for character in text {
            let kind: KeyKind = character == " " ? .space : .character(String(character))
            let frame = engine.layout.key(kind)!.frame
            let point = CGPoint(x: frame.midX, y: frame.midY)
            engine.touchBegan(id: 1, at: point)
            engine.touchEnded(id: 1, at: point)
            now += 0.1
        }
    }

    private func strip() async -> [KeyboardSuggestion] {
        await engine.waitForSuggestions()
        return engine.suggestions
    }

    private func replaced(_ typed: String) -> String? {
        engine.autocorrect.replacementOnSpace(beforeInput: typed, field: .text, autocorrectionType: .default)?.replacement
    }

    func testReplacementsExpandWithAutocorrectOff() async throws {
        engine.autocorrect.isEnabled = false
        type("bis dann mfg ")
        XCTAssertEqual(target.text, "bis dann Mit freundlichen Grüßen ")
        type("omw ")
        XCTAssertEqual(target.text, "bis dann Mit freundlichen Grüßen On my way! ")
    }

    func testAutocorrectOffShowsTheReplacementButNoFix() async throws {
        engine.autocorrect.isEnabled = false
        type("vlg")
        let chips = await strip()
        XCTAssertTrue(chips.contains { $0.replacement == "viele liebe Grüße" && $0.kind == .primary(autoReplace: true) })
        type(" ich nciht teh ")
        XCTAssertEqual(target.text, "viele liebe Grüße ich nciht teh ")
    }

    func testAFieldWithoutAutocorrectionGetsNoReplacement() {
        engine.autocorrect.isEnabled = false
        XCTAssertNil(engine.autocorrect.replacementOnSpace(beforeInput: "mfg", field: .text, autocorrectionType: .no))
        engine.autocorrect.isEnabled = true
        XCTAssertNil(engine.autocorrect.replacementOnSpace(beforeInput: "omw", field: .text, autocorrectionType: .no))
    }

    func testYourShortcutBeatsChatShorthand() {
        XCTAssertEqual(replaced("brb"), "be right back")
        XCTAssertNil(replaced("idk"))
        engine.autocorrect.isEnabled = false
        XCTAssertEqual(replaced("brb"), "be right back")
    }

    func testTheShortcutsLeadingCapitalCarriesOverGerman() {
        XCTAssertEqual(replaced("vlg"), "viele liebe Grüße")
        XCTAssertEqual(replaced("Vlg"), "Viele liebe Grüße")
        XCTAssertEqual(replaced("VLG"), "viele liebe Grüße")
        XCTAssertEqual(replaced("mfg"), "Mit freundlichen Grüßen")
        XCTAssertEqual(replaced("Mfg"), "Mit freundlichen Grüßen")
        XCTAssertEqual(replaced("MFG"), "Mit freundlichen Grüßen")
        XCTAssertEqual(replaced("Sgdh"), "Sehr geehrte Damen und Herren,")
        XCTAssertEqual(replaced("Grü"), "Grüß dich")
        XCTAssertEqual(replaced("grü"), "grüß dich")
        XCTAssertEqual(replaced("Ua"), "Unter anderem")
        XCTAssertEqual(replaced("UA"), "unter anderem")
    }

    func testTheShortcutsLeadingCapitalCarriesOverEnglish() {
        XCTAssertEqual(replaced("brb"), "be right back")
        XCTAssertEqual(replaced("Brb"), "Be right back")
        XCTAssertEqual(replaced("BRB"), "be right back")
        XCTAssertEqual(replaced("omw"), "On my way!")
        XCTAssertEqual(replaced("OMW"), "On my way!")
        XCTAssertEqual(replaced("mip"), "My iPhone")
        XCTAssertEqual(replaced("Mip"), "My iPhone")
        XCTAssertEqual(replaced("MIP"), "My iPhone")
    }

    func testAutoCapitalisedShortcutCapitalisesAtASentenceStartOnly() async throws {
        target.autocapitalizationType = .sentences
        engine.configureForField()
        type("vlg ")
        XCTAssertEqual(target.text, "Viele liebe Grüße ")
        type("und vlg ")
        XCTAssertEqual(target.text, "Viele liebe Grüße und viele liebe Grüße ")
        type("brb  brb ")
        XCTAssertEqual(target.text, "Viele liebe Grüße und viele liebe Grüße be right back. Be right back ")
    }

    func testMidSentenceTheStripShowsNoStrayCapital() async throws {
        type("ich vlg")
        let german = await strip()
        XCTAssertTrue(german.contains { $0.replacement == "viele liebe Grüße" })
        XCTAssertFalse(german.contains { $0.replacement == "Viele liebe Grüße" })
        type(" and brb")
        let english = await strip()
        XCTAssertTrue(english.contains { $0.replacement == "be right back" })
        XCTAssertFalse(english.contains { $0.replacement == "Be right back" })
    }

    func testDeleteAfterAReplacementTakesOnlyTheSpace() async throws {
        type("mfg ")
        engine.deleteBackward()
        XCTAssertEqual(target.text, "Mit freundlichen Grüßen")
        type(" brb ")
        engine.deleteBackward()
        XCTAssertEqual(target.text, "Mit freundlichen Grüßen be right back")
    }

    func testARevertKeepsTheShortcutOnceAndItExpandsWhenTypedAgain() async throws {
        var expected = ""
        for _ in 0..<3 {
            type("mfg ")
            XCTAssertEqual(target.text, expected + "Mit freundlichen Grüßen ")
            engine.deleteBackward()
            let chips = await strip()
            let revert = try XCTUnwrap(chips.first { $0.kind == .revert })
            XCTAssertEqual(revert.replacement, "mfg")
            engine.acceptSuggestion(revert)
            type(" ")
            expected += "mfg "
            XCTAssertEqual(target.text, expected)
        }
        type("mfg brb ")
        engine.deleteBackward()
        let chips = await strip()
        let revert = try XCTUnwrap(chips.first { $0.kind == .revert })
        engine.acceptSuggestion(revert)
        type(" brb ")
        XCTAssertEqual(target.text, expected + "Mit freundlichen Grüßen brb be right back ")
    }
}
