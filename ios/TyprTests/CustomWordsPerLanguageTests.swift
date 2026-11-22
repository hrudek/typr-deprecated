import Foundation
import XCTest
@testable import Typr

@MainActor
final class CustomWordsPerLanguageTests: XCTestCase {
    private final class Checker: TextChecking {
        let valid: Set<String>
        init(_ valid: Set<String>) { self.valid = valid }
        func isWordValid(_ word: String) -> Bool { valid.contains(word) }
        func guesses(for word: String) -> [String] { [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private static let english: Set<String> = ["we", "have", "a", "use", "run", "meeting", "it", "also"]
    private static let german: Set<String> = ["ich", "habe", "heute", "nutze", "wir"]

    private func engine(_ session: KeyboardLearningSession, predicts: Bool = false) -> AutocorrectEngine {
        let ac = AutocorrectEngine(checker: Checker(Self.english), learning: session, spatialDecoder: nil,
                                   contextResources: predicts ? .init(model: BundledKeyboardData.contextModel) : nil)
        ac.german = GermanAutocorrect(checker: Checker(Self.german))
        return ac
    }

    private func session() -> KeyboardLearningSession {
        let defaults = UserDefaults(suiteName: "typr.tests.custom-words.\(UUID().uuidString)")!
        defaults.set(true, forKey: "keyboard.personalLearning")
        return KeyboardLearningSession(defaults: defaults)
    }

    private func alternatives(_ ac: AutocorrectEngine, _ text: String) -> [String] {
        ac.suggestions(beforeInput: text, field: .text, autocorrectionType: .default)
            .filter { $0.kind != .keepLiteral }.map(\.replacement)
    }

    private func pick(_ word: String, typed literal: String, after text: String, in ac: AutocorrectEngine) {
        _ = ac.suggestions(beforeInput: text + literal, field: .text, autocorrectionType: .default)
        ac.recordSuggestionFeedback(KeyboardSuggestion(displayText: word, replacement: word, kind: .secondary,
                                                       isCompletion: true), literal: literal, evidence: nil)
    }

    func testCustomWordsAreCompletedAndKeptInGermanAndEnglish() {
        let ac = engine(session())
        XCTAssertFalse(alternatives(ac, "Ich nutze kub").contains("kubectl"))
        ac.loadCustomWords(["kubectl", "Claude Code"])
        XCTAssertTrue(alternatives(ac, "Ich nutze kub").contains("kubectl"))
        XCTAssertTrue(alternatives(ac, "we use kub").contains("kubectl"))
        XCTAssertTrue(alternatives(ac, "we use Cla").contains("Claude"), "each word of a phrase")
        XCTAssertNil(ac.replacementOnSpace(beforeInput: "Ich nutze kubectl", field: .text, autocorrectionType: .default))
        XCTAssertNil(ac.replacementOnSpace(beforeInput: "we run kubectl", field: .text, autocorrectionType: .default))
        XCTAssertFalse(ac.loadCustomWords(["kubectl", "Claude Code"]), "an unchanged list changes nothing")
        ac.loadCustomWords([])
        XCTAssertFalse(alternatives(ac, "Ich nutze kub").contains("kubectl"))
    }

    func testCustomWordsKeepContactsFirst() {
        let ac = engine(session())
        ac.loadLexiconEntries([(userInput: "Kubrick", documentText: "Kubrick")])
        ac.loadCustomWords(["kubectl", "kubrick"])
        XCTAssertEqual(alternatives(ac, "Ich nutze kub"), ["Kubrick", "kubectl"])
    }

    func testLearnedWordsAreTaggedWithTheSentenceLanguage() {
        let learning = session()
        let ac = engine(learning)
        pick("meeting", typed: "mee", after: "we have a ", in: ac)
        pick("Meerblick", typed: "mee", after: "ich habe heute ", in: ac)
        XCTAssertEqual(learning.model.language(of: "meeting"), .english)
        XCTAssertEqual(learning.model.language(of: "meerblick"), .german)
        pick("meeting", typed: "mee", after: "ich habe heute ", in: ac)
        XCTAssertNil(learning.model.language(of: "meeting"))
        pick("meeting", typed: "mee", after: "we have a ", in: ac)
        XCTAssertNil(learning.model.language(of: "meeting"), "once in both, in both for good")
    }

    func testLearnedWordIsOnlySuggestedInItsLanguageWithTheSwitchOn() {
        let learning = session()
        let ac = engine(learning)
        for _ in 0..<3 {
            pick("meeting", typed: "mee", after: "we have a ", in: ac)
            pick("Meerblick", typed: "mee", after: "ich habe heute ", in: ac)
        }
        XCTAssertTrue(alternatives(ac, "ich habe heute mee").contains("meeting"), "off: as before")
        ac.learnsLanguagesSeparately = true
        let german = alternatives(ac, "ich habe heute mee")
        XCTAssertFalse(german.contains("meeting"))
        XCTAssertTrue(german.contains { $0.lowercased() == "meerblick" })
        let english = alternatives(ac, "we have a mee")
        XCTAssertTrue(english.contains("meeting"))
        XCTAssertFalse(english.contains { $0.lowercased() == "meerblick" })
        let neither = alternatives(ac, "mee")
        XCTAssertTrue(neither.contains("meeting") && neither.contains { $0.lowercased() == "meerblick" },
                      "no lean: every learned word")
        pick("meeting", typed: "mee", after: "ich habe heute ", in: ac)
        XCTAssertTrue(alternatives(ac, "ich habe heute mee").contains("meeting"), "typed in both: in both")
    }

    func testSharedWordsStayInBothLanguagesUntilEveryUseLeansOneWay() {
        let learning = session()
        learning.model.recordWord("meeting")
        let ac = engine(learning)
        ac.learnsLanguagesSeparately = true
        pick("meeting", typed: "mee", after: "we have a ", in: ac)
        XCTAssertNil(learning.model.language(of: "meeting"), "learned before languages: stays shared")
        XCTAssertTrue(alternatives(ac, "ich habe heute mee").contains("meeting"))
        pick("Meerblick", typed: "mee", after: "", in: ac)
        pick("Meerblick", typed: "mee", after: "ich habe heute ", in: ac)
        XCTAssertNil(learning.model.language(of: "meerblick"), "first used leaning neither: shared")
        XCTAssertTrue(alternatives(ac, "we have a mee").contains { $0.lowercased() == "meerblick" })
    }

    func testNextWordPredictionsKeepToTheSentenceLanguage() throws {
        try XCTSkipIf(BundledKeyboardData.contextModel == nil, "no bundled word data")
        let learning = session()
        for _ in 0..<4 {
            learning.model.recordWord("zorbex", language: .english)
            learning.model.recordPair("zorbex", after: "also")
        }
        let ac = engine(learning, predicts: true)
        func predicts(_ text: String) -> Bool {
            ac.suggestions(beforeInput: text, field: .text, autocorrectionType: .default)
                .contains { $0.replacement.lowercased() == "zorbex" }
        }
        XCTAssertTrue(predicts("ich habe heute also "), "off: as before")
        XCTAssertTrue(predicts("we have it also "))
        ac.learnsLanguagesSeparately = true
        XCTAssertFalse(predicts("ich habe heute also "))
        XCTAssertTrue(predicts("we have it also "))
    }

    func testLanguagesSurviveSavingAndForgetting() throws {
        let model = PersonalTypingModel()
        model.recordWord("meeting", language: .english)
        model.keep("tastatur", language: .german)
        let data = try JSONEncoder().encode(model.state)
        let loaded = try XCTUnwrap(JSONDecoder().decode(PersonalTypingModel.State.self, from: data).validated())
        XCTAssertEqual(loaded.languages, ["meeting": "en", "tastatur": "de"])
        model.forgetCount("meeting")
        model.forgetKeep("tastatur")
        XCTAssertEqual(model.state.languages, [:])
        var untagged = loaded
        untagged.languages = nil
        let old = try JSONDecoder().decode(PersonalTypingModel.State.self, from: JSONEncoder().encode(untagged))
        XCTAssertNotNil(old.validated(), "state saved before languages loads; its words belong to both")
        XCTAssertNil(PersonalTypingModel(state: old).language(of: "meeting"))
    }

    func testLearnEachLanguageIsAnExperimentalSwitch() {
        XCTAssertTrue(ExperimentalSwitch.all.contains(.learnEachLanguage))
    }
}
