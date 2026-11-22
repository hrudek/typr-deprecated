import UIKit
import XCTest
@testable import Typr

/// Editing a word mid-sentence: no second space where the text after the cursor already has one
/// (Hex #2214), and no capitals from Contacts or lexicon terms in the strip or a swiped word
/// (Hex #2173, #2218).
@MainActor
final class MidSentenceEditingTests: XCTestCase {
    private final class Checker: TyprTextChecking {
        let valid: Set<String>
        let corrections: [String: String]
        init(valid: Set<String>, corrections: [String: String] = [:]) {
            self.valid = valid
            self.corrections = corrections
        }
        func isWordValid(_ word: String) -> Bool { valid.contains(word) }
        func guesses(for word: String) -> [String] { corrections[word].map { [$0] } ?? [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private static let english = Checker(
        valid: ["i", "have", "time", "today", "come", "testing", "how", "this", "world", "works", "pay", "the", "bill"],
        corrections: ["tdoay": "today", "cmoe": "come"])
    private static let german = Checker(
        valid: ["ich", "habe", "morgen", "zeit", "nicht", "heute", "komme", "wir", "warten", "lange", "will",
                "eine", "Rose", "Lange"],
        corrections: ["nciht": "nicht", "mrogen": "morgen"])

    private var defaults: UserDefaults!
    private var suite: String!
    private var target: FixtureTextTarget!
    private var engine: TyprFullKeyboardEngine!
    private var now: TimeInterval = 100

    override func setUp() async throws {
        suite = "MidSentenceEditingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func start(_ text: String, german: Bool, lexicon: [String] = [], swiped: String? = nil,
                       wordLists: Bool = false) {
        let cursor = text.firstIndex(of: "|")!
        let after = text[text.index(after: cursor)...].count
        target = FixtureTextTarget(text: text.replacingOccurrences(of: "|", with: ""))
        target.adjustTextPosition(byCharacterOffset: -after)
        let spatial = swiped != nil || wordLists ? SpatialWordDecoder(lexicons: BundledKeyboardData.lexicons ?? [:]) : nil
        let autocorrect = TyprAutocorrectEngine(checker: german ? Self.german : Self.english,
                                            learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: spatial)
        if german {
            autocorrect.german = GermanAutocorrect(checker: Self.german)
            autocorrect.englishEnabled = false
        }
        autocorrect.loadLexiconEntries(lexicon.map { (userInput: $0, documentText: $0) })
        let candidate = swiped.map { SwipeSearch.Candidate(word: $0, score: 0, language: german ? .german : .english) }
        engine = TyprFullKeyboardEngine(target: target, autocorrect: autocorrect,
                                    swipeDecoder: { _ in candidate.map { [$0] } ?? [] })
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.scheduleAfter = { _, _ in }
        engine.configureForField()
    }

    private var shown: String {
        let before = target.documentContextBeforeInput ?? ""
        return before + "|" + target.text.dropFirst(before.count)
    }

    private func type(_ text: String) {
        for character in text {
            let kind: TyprKeyKind = character == " " ? .space : .character(String(character))
            let frame = engine.layout.key(kind)!.frame
            let point = CGPoint(x: frame.midX, y: frame.midY)
            engine.touchBegan(id: 1, at: point)
            engine.touchEnded(id: 1, at: point)
            now += 0.3
        }
    }

    private func strip() async -> [String] {
        await engine.waitForSuggestions()
        return engine.suggestions.map(\.replacement)
    }

    private func chipReplacing(with replacement: String) async throws -> TyprKeyboardSuggestion {
        await engine.waitForSuggestions()
        return try XCTUnwrap(engine.suggestions.first { $0.replacement == replacement && $0.boundary != nil },
                             "\(engine.suggestions.map(\.replacement))")
    }

    private func pick(_ word: String) async throws {
        await engine.waitForSuggestions()
        engine.acceptSuggestion(try XCTUnwrap(engine.suggestions.first { $0.replacement == word }, "\(word) offered"))
    }

    func testSpaceBeforeASpaceTypesNoSecondOneGerman() {
        start("Ich habe | Zeit.", german: true)
        type("morgen ")
        XCTAssertEqual(shown, "Ich habe morgen| Zeit.")
        type("nicht")
        XCTAssertEqual(shown, "Ich habe morgen nicht| Zeit.", "the next word gets the held space")
    }

    func testSpaceBeforeASpaceTypesNoSecondOneEnglish() {
        start("I have | time.", german: false)
        type("today ")
        XCTAssertEqual(shown, "I have today| time.")
    }

    func testAnAutocorrectionMidSentenceTypesNoSecondSpaceAndDeleteOffersTheRevert() async throws {
        start("Ich habe | Zeit.", german: true)
        type("mrogen ")
        XCTAssertEqual(shown, "Ich habe morgen| Zeit.")
        engine.deleteBackward()
        XCTAssertEqual(shown, "Ich habe morgen| Zeit.", "delete takes back the held space only")
        let revert = try XCTUnwrap(engine.suggestions.first)
        XCTAssertEqual(revert.kind, .revert)
        engine.acceptSuggestion(revert)
        XCTAssertEqual(shown, "Ich habe mrogen| Zeit.")
        type(" ")
        XCTAssertEqual(shown, "Ich habe mrogen| Zeit.", "the reverted word stays")
    }

    func testAnAutocorrectionMidSentenceEnglish() {
        start("I have | time.", german: false)
        type("tdoay ")
        XCTAssertEqual(shown, "I have today| time.")
    }

    func testSpaceBeforeAClosingMarkIsHeld() {
        start("Ich komme|.", german: true)
        type(" ")
        XCTAssertEqual(shown, "Ich komme|.")
        type("heute")
        XCTAssertEqual(shown, "Ich komme heute|.")
    }

    func testASecondSpaceWhileHeldTypesNothing() {
        start("I have | time.", german: false)
        type("today  ")
        XCTAssertEqual(shown, "I have today| time.")
    }

    func testSpaceAtTheEndOrBeforeALineBreakStillTypesASpace() {
        start("Ich komme|", german: true)
        type(" ")
        XCTAssertEqual(shown, "Ich komme |")
        start("I come|\ntoday", german: false)
        type(" ")
        XCTAssertEqual(shown, "I come |\ntoday")
    }

    func testMovingTheCursorAwayAndBackDropsTheHeldSpace() {
        start("Ich habe | Zeit.", german: true)
        type("morgen ")
        target.adjustTextPosition(byCharacterOffset: -3)
        engine.discardTouchEvidenceAndHeldSpace()
        target.adjustTextPosition(byCharacterOffset: 3)
        engine.discardTouchEvidenceAndHeldSpace()
        type("s")
        XCTAssertEqual(shown, "Ich habe morgens| Zeit.")

        start("I have | time.", german: false)
        type("today ")
        engine.textDidChange()
        type("s")
        XCTAssertEqual(shown, "I have todays| time.")
    }

    func testTheSpaceBarTrackpadDropsTheHeldSpace() {
        start("Ich habe | Zeit.", german: true)
        type("morgen ")
        let space = engine.layout.key(.space)!.frame
        let start = CGPoint(x: space.midX, y: space.midY)
        let activated = CGPoint(x: start.x - TyprFullKeyboardEngine.trackpadActivationDistance, y: start.y)
        let away = CGPoint(x: activated.x - 3 * TyprFullKeyboardEngine.trackpadPointsPerCharacter, y: start.y)
        engine.touchBegan(id: 3, at: start)
        now += TyprFullKeyboardEngine.trackpadDelay + 0.1
        engine.touchMoved(id: 3, to: activated)
        engine.touchMoved(id: 3, to: away)
        engine.touchMoved(id: 3, to: activated)
        engine.touchEnded(id: 3, at: activated)
        now += 0.3
        XCTAssertEqual(shown, "Ich habe morgen| Zeit.")
        type("s")
        XCTAssertEqual(shown, "Ich habe morgens| Zeit.")
    }

    func testEditsAfterTheHeldSpaceDropItWhenDeletedBack() {
        start("Ich habe | Zeit.", german: true)
        type("morgen x")
        XCTAssertEqual(shown, "Ich habe morgen x| Zeit.")
        engine.deleteBackward()
        engine.deleteBackward()
        XCTAssertEqual(shown, "Ich habe morgen| Zeit.")
        type("s")
        XCTAssertEqual(shown, "Ich habe morgens| Zeit.")
    }

    func testASwipeAfterTheHeldSpaceDropsItWhenDeletedBack() async {
        start("Ich komme| Zeit.", german: true, swiped: "heute")
        type(" ")
        await swipe("heute")
        XCTAssertEqual(shown, "Ich komme heute| Zeit.")
        engine.deleteBackward()
        engine.deleteBackward()
        XCTAssertEqual(shown, "Ich komme| Zeit.")
        type("s")
        XCTAssertEqual(shown, "Ich kommes| Zeit.")

        start("I come| today.", german: false, swiped: "back")
        type(" ")
        await swipe("back")
        XCTAssertEqual(shown, "I come back| today.")
        engine.deleteBackward()
        engine.deleteBackward()
        type("s")
        XCTAssertEqual(shown, "I comes| today.")
    }

    func testPickingACorrectionMidSentenceTypesNoSecondSpaceGerman() async throws {
        start("ich | heute", german: true)
        type("nciht")
        try await pick("nicht")
        XCTAssertEqual(shown, "ich nicht| heute")
        type("komme")
        XCTAssertEqual(shown, "ich nicht komme| heute")
    }

    func testPickingACorrectionMidSentenceTypesNoSecondSpaceEnglish() async throws {
        start("I | today", german: false)
        type("cmoe")
        try await pick("come")
        XCTAssertEqual(shown, "I come| today")
    }

    func testPickingTheNextWordWhileTheSpaceIsHeldTypesTheSpaceFirst() async throws {
        start("ich | heute", german: true)
        type("nciht ")
        XCTAssertEqual(shown, "ich nicht| heute")
        await engine.waitForSuggestions()
        XCTAssertFalse(engine.suggestions.contains { $0.kind == .revert }, "the held space hides the revert")
        engine.acceptSuggestion(TyprKeyboardSuggestion(displayText: "komme", replacement: "komme",
                                                   kind: .primary(autoReplace: false),
                                                   ownership: engine.suggestionOwnership))
        XCTAssertEqual(shown, "ich nicht komme| heute")
    }

    func testDeleteAfterAHeldBoundaryPickUndoesIt() async throws {
        start("We | today", german: false, wordLists: true)
        type("greatday")
        let chip = try await chipReplacing(with: "great day")
        engine.acceptSuggestion(chip)
        XCTAssertEqual(shown, "We great day| today")
        XCTAssertFalse(engine.deleteUndoes, "the first delete takes the held space")
        engine.deleteBackward()
        XCTAssertEqual(shown, "We great day| today")
        XCTAssertTrue(engine.deleteUndoes)
        engine.deleteBackward()
        XCTAssertEqual(shown, "We greatday| today")
    }

    func testDeleteAfterAHeldKeepPickUndoesTheKeep() async throws {
        for (text, typed) in [("ich | heute", "nciht"), ("I | today", "cmoe")] {
            start(text, german: text.hasPrefix("ich"))
            type(typed)
            await engine.waitForSuggestions()
            engine.acceptSuggestion(try XCTUnwrap(engine.suggestions.first { $0.kind == .keepLiteral }))
            let kept = text.replacingOccurrences(of: "| ", with: typed + "| ")
            XCTAssertEqual(shown, kept)
            engine.deleteBackward()
            XCTAssertTrue(engine.deleteUndoes)
            engine.deleteBackward()
            XCTAssertEqual(shown, kept, "delete undoes the keep instead of taking a letter")
        }
    }

    func testLexiconTermsCompleteInLowercaseMidSentenceGerman() async {
        start("Wir warten |", german: true, lexicon: ["Lange", "Rose"])
        type("lan")
        let chips = await strip()
        XCTAssertTrue(chips.contains("lange"), "\(chips)")
        XCTAssertFalse(chips.contains("Lange"), "\(chips)")
    }

    func testGermanNounsFromTheLexiconKeepTheirCapital() async {
        start("Eine |", german: true, lexicon: ["Rose"])
        type("ros")
        let chips = await strip()
        XCTAssertTrue(chips.contains("Rose"), "\(chips)")
    }

    func testLexiconTermsCompleteInLowercaseMidSentenceEnglish() async {
        start("Testing how this |", german: false, lexicon: ["World", "Works", "Kate"])
        type("wor")
        let chips = await strip()
        XCTAssertFalse(chips.contains { $0 == "World" || $0 == "Works" }, "\(chips)")
        XCTAssertTrue(chips.contains("world") || chips.contains("works"), "\(chips)")
    }

    func testNamesTheDictionaryDoesNotKnowInLowercaseKeepTheirCapital() async {
        start("Testing how this |", german: false, lexicon: ["Kate"])
        type("ka")
        let chips = await strip()
        XCTAssertTrue(chips.contains("Kate"), "\(chips)")
    }

    func testSwipedWordsMidSentenceStayLowercaseWithLexiconTerms() async {
        start("Ich |", german: true, lexicon: ["Will"], swiped: "will")
        await swipe("will")
        XCTAssertEqual(shown, "Ich will|")
        start("pay the |", german: false, lexicon: ["Bill"], swiped: "bill")
        await swipe("bill")
        XCTAssertEqual(shown, "pay the bill|")
    }

    private func swipe(_ word: String) async {
        let points = word.map { letter -> CGPoint in
            let frame = engine.layout.key(.character(String(letter)))!.frame
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        engine.touchBegan(id: 2, at: points[0], time: now)
        for (from, to) in zip(points, points.dropFirst()) {
            for step in 1...10 {
                let t = CGFloat(step) / 10
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                now += 0.008
                engine.touchMoved(id: 2, to: point, samples: [(point, now)])
            }
        }
        engine.touchEnded(id: 2, at: points.last!)
        await engine.waitForSwipe()
        now += 0.3
    }
}
