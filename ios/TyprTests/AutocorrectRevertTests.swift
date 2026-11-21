import UIKit
import XCTest
@testable import Typr

@MainActor
final class AutocorrectRevertTests: XCTestCase {
    private final class Checker: TextChecking {
        func isWordValid(_ word: String) -> Bool { ["ich", "nicht", "heute", "komme"].contains(word) }
        func guesses(for word: String) -> [String] {
            ["nciht": ["nicht"], "hetue": ["heute"]][word] ?? []
        }
        func completions(for prefix: String) -> [String] { [] }
    }

    private var defaults: UserDefaults!
    private var suite: String!
    private var target: FixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 100

    override func setUp() async throws {
        suite = "AutocorrectRevertTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let autocorrect = AutocorrectEngine(checker: Checker(), learning: KeyboardLearningSession(defaults: defaults),
                                            spatialDecoder: nil)
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

    func testDeleteTakesOnlyTheSpaceAndTheStripOffersTheTypedWord() async throws {
        type("ich nciht ")
        XCTAssertEqual(target.text, "ich nicht ")
        XCTAssertFalse(engine.deleteUndoes, "the delete key shows no undo")

        engine.deleteBackward()
        XCTAssertEqual(target.text, "ich nicht")
        let chips = await strip()
        let revert = try XCTUnwrap(chips.first)
        XCTAssertEqual(revert.kind, .revert)
        XCTAssertEqual(revert.replacement, "nciht")
        XCTAssertFalse(chips.contains { $0.kind == .keepLiteral }, "the revert takes the left slot")

        engine.deleteBackward()
        XCTAssertEqual(target.text, "ich nich", "a second delete takes a letter")
        let afterLetter = await strip()
        XCTAssertFalse(afterLetter.contains { $0.kind == .revert })
    }

    func testTappingTheRevertRestoresTheTypedWordAndSpaceDoesNotCorrectItAgain() async throws {
        type("ich nciht ")
        engine.deleteBackward()
        let chips = await strip()
        let revert = try XCTUnwrap(chips.first)
        XCTAssertEqual(revert.kind, .revert)

        engine.acceptSuggestion(revert)
        XCTAssertEqual(target.text, "ich nciht", "the typed word comes back without a space")
        let afterRevert = await strip()
        XCTAssertFalse(afterRevert.contains { $0.kind == .revert })

        type(" komme")
        XCTAssertEqual(target.text, "ich nciht komme")
    }

    func testSpaceAfterTheDeleteKeepsTheCorrection() async {
        type("ich nciht ")
        engine.deleteBackward()
        type(" komme ")
        XCTAssertEqual(target.text, "ich nicht komme ")
    }

    func testTheOfferComesBackWhenDeletingBackToTheCorrection() async throws {
        type("nciht heute")
        XCTAssertEqual(target.text, "nicht heute")
        for _ in 0..<6 { engine.deleteBackward() }
        XCTAssertEqual(target.text, "nicht")
        let chips = await strip()
        let revert = try XCTUnwrap(chips.first)
        XCTAssertEqual(revert.kind, .revert)
        XCTAssertEqual(revert.replacement, "nciht")
    }

    func testANewerCorrectionReplacesTheOffer() async throws {
        type("nciht hetue ")
        XCTAssertEqual(target.text, "nicht heute ")
        engine.deleteBackward()
        let newer = await strip()
        XCTAssertEqual(newer.first?.kind, .revert)
        XCTAssertEqual(newer.first?.replacement, "hetue")
        for _ in 0..<6 { engine.deleteBackward() }
        XCTAssertEqual(target.text, "nicht")
        let older = await strip()
        XCTAssertFalse(older.contains { $0.kind == .revert })
    }

    func testAReplacementEndingInPunctuationIsRevertedLikeAWord() async throws {
        engine.autocorrect.loadLexiconEntries([(userInput: "mfg", documentText: "Mit freundlichen Grüßen!")])
        type("mfg ")
        XCTAssertEqual(target.text, "Mit freundlichen Grüßen! ")
        engine.deleteBackward()
        XCTAssertEqual(target.text, "Mit freundlichen Grüßen!")
        let chips = await strip()
        let revert = try XCTUnwrap(chips.first)
        XCTAssertEqual(revert.kind, .revert)
        XCTAssertEqual(revert.replacement, "mfg")
        engine.acceptSuggestion(revert)
        XCTAssertEqual(target.text, "mfg")
        type(" ")
        XCTAssertEqual(target.text, "mfg ")
    }

    func testANewFieldForgetsTheOffer() async {
        type("nciht ")
        engine.configureForField()
        engine.deleteBackward()
        XCTAssertEqual(target.text, "nicht")
        let chips = await strip()
        XCTAssertFalse(chips.contains { $0.kind == .revert })
    }

    func testStripDrawsTheRevertChipWithItsLabel() throws {
        let strip = KeyboardStripView(frame: CGRect(x: 0, y: 0, width: 393, height: 44))
        strip.update(suggestions: [
            KeyboardSuggestion(displayText: "nciht", replacement: "nciht", kind: .revert),
            KeyboardSuggestion(displayText: "nicht", replacement: "nicht", kind: .primary(autoReplace: true)),
        ], statusText: nil)
        strip.layoutIfNeeded()
        let labels = strip.subviews.filter { !$0.isHidden }.compactMap(\.accessibilityLabel)
        XCTAssertEqual(labels, ["Revert to nciht", "nicht"])
        let image = UIGraphicsImageRenderer(bounds: strip.bounds).image { context in
            strip.layer.render(in: context.cgContext)
        }
        XCTAssertEqual(image.size, strip.bounds.size)
    }
}
