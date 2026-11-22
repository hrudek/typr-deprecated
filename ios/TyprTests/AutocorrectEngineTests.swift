import UIKit
import XCTest
@testable import Typr

/// Hex's `AutocorrectEngineTests` (anomalyco/hex@0c1c13d7, HEXMobileTests) for what Typr has
/// imported so far: the dictionary engine, the typing decoder with the bundled models, German
/// capitals and the never-suggest list. Tests that type through Hex's `FullKeyboardEngine`
/// come with that engine; the decoder tests below read taps on a `KeyboardLayout` instead.
@MainActor
final class AutocorrectEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    /// The layouts and dictionaries below are Apple's iOS 27 keyboard; CI's newest simulator
    /// runtime is iOS 26.5, so the version these tests describe is pinned.
    private var runningSystemMajorVersion = 0

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "AutocorrectEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// TestFlight (build 56): "Even with auto-capitalization off, many suggested words are
    /// capitalized." With it off the strip offers no capital you didn't type either, as space
    /// puts none in: a guess or completion iOS knows capitalised ("Mandy", "Monday") and
    /// "I'd" for "id" come lowercase; your own spellings (a vocabulary word, a contact) and a
    /// capital you typed keep theirs.
    func testAutoCapitalizationOffSuggestsNoCapitals() {
        let engine = stubbed {
            $0.valid = ["id", "money"]
            $0.capitalised = ["Monday", "Mandy"]
            $0.guessTable = ["mondy": ["Monday", "Mandy"]]
            $0.completionTable = ["mon": ["Monday", "money"]]
        }
        engine.loadLexiconEntries([("Kimberly", "Kimberly")])
        engine.setVocabulary(["GitHub"])
        func strip(_ typed: String) -> [String] {
            engine.suggestions(beforeInput: typed, field: .text, autocorrectionType: .default).dropFirst().map(\.replacement)
        }
        XCTAssertEqual(strip("mondy"), ["Monday", "Mandy"], "on: as the dictionary spells them")
        engine.addsCapitals = false
        XCTAssertEqual(strip("mondy"), ["monday", "mandy"])
        XCTAssertEqual(strip("id"), ["i'd"])
        XCTAssertEqual(Set(strip("mon")), ["money", "monday"])
        XCTAssertEqual(strip("git"), ["GitHub"], "your vocabulary's spelling")
        XCTAssertEqual(strip("kim"), ["Kimberly"], "a contact's")
        XCTAssertEqual(strip("Mondy"), ["Monday", "Mandy"], "a capital you typed")
        func predictions(_ before: String) -> [String] {
            engine.suggestions(beforeInput: before, field: .text, autocorrectionType: .default, capitalizesNext: true).map(\.replacement)
        }
        XCTAssertEqual(predictions(""), ["I", "the", "I'm"], "sentence starters: only \"I\", which always has one (#2135)")
        XCTAssertEqual(predictions("well, "), ["I", "but", "and"], "clause starters")
        engine.addsCapitals = true
        XCTAssertEqual(predictions(""), ["I", "The", "I'm"])
    }

    /// TestFlight (build 56): "Custom dictionary for uncommon programmer slang." Hex's
    /// vocabulary list (Settings › Keyboard › Vocabulary, the one dictation spells) reaches the
    /// keys: its words are never autocorrected away, are spelled your way, are completed in
    /// the strip, and a bilingual partner shares them.
    func testVocabularyWordsAreKeptSpelledYourWayAndCompleted() {
        let engine = stubbed {
            $0.valid = ["deduce", "the"]
            $0.guessTable = ["dedupe": ["deduce"]]
            $0.completionTable = ["ded": ["deduce"]]
        }
        engine.setLanguage(.english, available: ["en_US", "fr_FR"])
        XCTAssertEqual(fix(engine, "dedupe"), "deduce", "not yet in the vocabulary")
        engine.setVocabulary(["dedupe", "GitHub", "Claude Code"])
        XCTAssertNil(fix(engine, "dedupe"))
        XCTAssertNil(fix(engine, "Dedupe"))
        XCTAssertEqual(fix(engine, "github"), "GitHub")
        XCTAssertNil(fix(engine, "GitHub"))
        XCTAssertNil(fix(engine, "GITHUB"))
        XCTAssertEqual(fix(engine, "claude"), "Claude", "a word of a phrase")
        func strip(_ typed: String) -> [String] {
            engine.suggestions(beforeInput: typed, field: .text, autocorrectionType: .default).map(\.replacement)
        }
        XCTAssertEqual(strip("dedupe"), ["dedupe"], "no guess for your word")
        XCTAssertEqual(strip("ded").dropFirst().first, "dedupe", "completed before the dictionary's words")
        XCTAssertEqual(strip("Cla").dropFirst().first, "Claude Code")
        XCTAssertTrue(engine.ownWords.contains("dedupe"), "Swipe typing reads it")
        let french = StubChecker()
        french.valid = ["deduire"]
        engine.setPartner(.french, available: ["en_US", "fr_FR"], checker: french)
        XCTAssertEqual(engine.partner?.vocabulary, ["dedupe", "GitHub", "Claude Code"])
        XCTAssertNil(fix(engine, "dedupe"), "kept beside a partner")
        XCTAssertEqual(fix(engine, "github"), "GitHub")
    }

    func testQwertyAdjacencyPrefersPhysicalNeighbor() {
        let near = AutocorrectEngine.singleEditKeyboardCost(from: "tge", to: "the")!
        let far = AutocorrectEngine.singleEditKeyboardCost(from: "tpe", to: "the")!
        XCTAssertLessThan(near, far, "g is adjacent to h; p is across the keyboard")
        XCTAssertNil(AutocorrectEngine.singleEditKeyboardCost(from: "abcdef", to: "abxyef"), "two substitutions are rejected")
    }

    /// Italian's unaccented spellings only come from its own table, and only where the plain
    /// spelling is no word: "e" is "and" and "ce" is "to us", so they stay as typed and the
    /// strip offers "è" and "c'è", which space never applies.
    func testItalianRestoresUnambiguousAccentsAndSuggestsTheAmbiguousOnes() {
        let italian = stubbed {
            $0.valid = ["e", "ce", "perche", "citta"]
        }
        italian.setLanguage(.italian, available: ["it"])
        XCTAssertEqual(fix(italian, "perche"), "perché", "even a checker that calls it valid")
        XCTAssertEqual(fix(italian, "citta"), "città")
        XCTAssertEqual(fix(italian, "piu"), "più")
        XCTAssertEqual(fix(italian, "Citta"), "Città")
        XCTAssertNil(fix(italian, "e"), "\"e\" is and")
        XCTAssertNil(fix(italian, "ce"), "\"ce\" is to us")
        let e = italian.suggestions(beforeInput: "e", field: .text, autocorrectionType: .default)
        XCTAssertEqual(e.dropFirst().first?.replacement, "è")
        XCTAssertFalse(e.dropFirst().first?.willAutoReplace ?? true, "space never applies it")
        let ce = italian.suggestions(beforeInput: "ce", field: .text, autocorrectionType: .default)
        XCTAssertEqual(ce.dropFirst().first?.replacement, "c'è")
        XCTAssertFalse(ce.dropFirst().first?.willAutoReplace ?? true, "space never applies it")

        // Bilingual autocorrect: the table is this language's own spelling even when the
        // partner's dictionary takes the plain form for a word (English beside Italian).
        let english = StubChecker()
        english.valid = ["perche", "the"]
        italian.setPartner(.english, available: ["it", "en_US"], checker: english)
        XCTAssertEqual(italian.partner?.language, .english)
        XCTAssertEqual(fix(italian, "perche"), "perché", "the table wins beside English")
        XCTAssertNil(fix(italian, "the"), "an English word stays")

        // It decides before the bilingual lean too, not only when the partner knows the plain
        // spelling: English words before "piu" would otherwise hand it to the partner's guess.
        english.valid.insert("pi")
        english.guessTable["piu"] = ["pi"]
        XCTAssertEqual(fix(italian, before: "the meeting piu"), "più")
    }

    /// Every restoration only adds accents: it never changes a letter ("perche" -> "perché").
    func testItalianAccentRestorationsOnlyAddAccents() {
        for (plain, accented) in KeyboardLanguage.italian.accentRestorations {
            XCTAssertEqual(
                accented.folding(options: .diacriticInsensitive, locale: nil),
                plain,
                plain
            )
        }
    }

    /// TestFlight (build 56): "Autocomplete suggests English words in Czech too." With Czech
    /// and English chosen, a sentence the words before show is Czech (`languageLean`) gets
    /// Czech completions only, none of English's even where Czech has none, and an English
    /// sentence English's only; with nothing before, both languages' in turn, as before
    /// (#2186). Autocorrect is #2186's: an English word stays as typed in a Czech sentence.
    func testEnglishSuggestionsStayOutOfACzechSentence() {
        let available = ["cs", "en_US"]
        let czech = stubbed {
            $0.valid = ["dobrý", "den", "jsem", "doma", "dnes", "děkuji", "dobře", "a", "do"]
            $0.completionTable = ["do": ["doma", "dobře", "dobrý"], "de": ["den", "děkuji"]]
        }
        czech.setLanguage(.czech, available: available)
        let english = StubChecker()
        english.valid = ["i", "am", "at", "home", "today", "do", "dog", "done", "door", "the", "a"]
        english.completionTable = ["do": ["dog", "done", "door"], "de": ["deal"], "kur": ["kurtosis", "kudos"]]
        english.guessTable = ["dorr": ["door"]]
        czech.setPartner(.english, available: available, checker: english)
        XCTAssertEqual(czech.partner?.language, .english)
        func strip(_ before: String) -> [String] {
            Array(czech.suggestions(beforeInput: before, field: .text, autocorrectionType: .default).dropFirst().map(\.replacement))
        }
        XCTAssertEqual(strip("dobrý den jsem do"), ["doma", "dobře"], "a Czech sentence: Czech words")
        XCTAssertEqual(strip("dobrý den jsem kur"), [], "and no English ones where Czech has none")
        XCTAssertEqual(strip("i am at home do"), ["dog", "done"], "an English sentence: English words")
        XCTAssertEqual(strip("do"), ["doma", "dog"], "nothing before: both, in turn")
        XCTAssertEqual(fix(czech, before: "i am at home dorr"), "door")
        XCTAssertEqual(fix(czech, before: "dorr"), "door")
        XCTAssertNil(fix(czech, before: "dobrý den jsem home"), "an English word stays as typed")
    }

    func testAdjacencyFollowsTheLayout() {
        // German swaps Y and Z: on QWERTZ, Z sits beside T.
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("z", "t", language: .german))
        XCTAssertFalse(AutocorrectEngine.areAdjacentKeys("z", "t", language: .english))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("ø", "l", language: .norwegian))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("ñ", "l", language: .spanish))
        // AZERTY: M sits under P, A beside Z, and W under D.
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("m", "p", language: .french))
        XCTAssertFalse(AutocorrectEngine.areAdjacentKeys("m", "p", language: .english))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("a", "z", language: .french))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("w", "d", language: .french))
        XCTAssertFalse(AutocorrectEngine.areAdjacentKeys("w", "q", language: .french))
        XCTAssertTrue(AutocorrectEngine.areAdjacentKeys("a", "q", language: .frenchCanadian))
    }

    /// A deterministic dictionary: `UITextChecker`'s answers vary between iOS versions.
    private final class StubChecker: TextChecking {
        var valid: Set<String> = []
        /// Words the dictionary knows only with their capitals, as German nouns are ("Haus",
        /// never "haus"): `valid` lowercases, so it cannot say this.
        var capitalised: Set<String> = []
        var acceptsEverything = false
        var guessTable: [String: [String]] = [:]
        var completionTable: [String: [String]] = [:]
        func isWordValid(_ word: String) -> Bool {
            acceptsEverything || valid.contains(word.lowercased()) || capitalised.contains(word)
        }
        func guesses(for word: String) -> [String] { guessTable[word.lowercased()] ?? [] }
        func completions(for prefix: String) -> [String] { completionTable[prefix.lowercased()] ?? [] }
    }

    private func stubbed(_ configure: (StubChecker) -> Void) -> AutocorrectEngine {
        let checker = StubChecker()
        configure(checker)
        return AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: defaults))
    }

    private func fix(_ engine: AutocorrectEngine, _ typed: String) -> String? {
        engine.replacementOnSpace(beforeInput: typed, field: .text, autocorrectionType: .default)?.replacement
    }

    func testAMissedSpaceBecomesTwoWordsNeverAHyphen() {
        let engine = stubbed {
            $0.valid = ["up", "to", "a", "lot"]
            // UITextChecker lists the hyphenated form first and the spaced one later.
            $0.guessTable = ["upto": ["up-to", "updo", "unto", "up to"], "alot": ["a-lot", "lot", "a lot"]]
        }
        XCTAssertEqual(fix(engine, "upto"), "up to")
        XCTAssertEqual(fix(engine, "Upto"), "Up to")
        XCTAssertEqual(fix(engine, "alot"), "a lot", "English \"a\" is a word")
        let slots = engine.suggestions(beforeInput: "upto", field: .text, autocorrectionType: .default)
        XCTAssertEqual(slots.dropFirst().first?.replacement, "up to")
        XCTAssertFalse(slots.contains { $0.replacement.contains("-") }, "never offers a hyphen you didn't type")
    }

    func testASplitNeedsTwoWordsYourLettersAndTheSpacedForm() {
        let engine = stubbed {
            $0.valid = ["ab", "cd", "e", "mail", "xy"]
            $0.guessTable = [
                // Only the hyphenated form: the checker doesn't offer the two words.
                "abcd": ["ab-cd"],
                // "zq" isn't a word.
                "xyzq": ["xy-zq", "xy zq"],
                // One letter that isn't "a" or "I" (UITextChecker accepts every letter).
                "bmail": ["b-mail", "b mail"],
                // Not a missed space: the letters changed.
                "emial": ["e-mail", "e mail"],
            ]
        }
        for typed in ["abcd", "xyzq", "bmail", "emial"] {
            XCTAssertNil(fix(engine, typed), "\(typed) stays as typed")
        }
    }

    func testAGuessNeverAddsPunctuationYouDidntType() {
        let engine = stubbed {
            $0.valid = ["ok"]
            $0.guessTable = ["tbq": ["t.b.q", "tb-q", "tbq."], "wnot": ["w.not", "won't"]]
        }
        XCTAssertNil(fix(engine, "tbq"))
        XCTAssertEqual(fix(engine, "wnot"), "won't", "a contraction's apostrophe is part of the word")
        let slots = engine.suggestions(beforeInput: "tbq", field: .text, autocorrectionType: .default)
        XCTAssertFalse(slots.contains { $0.replacement.contains(".") || $0.replacement.contains("-") })
    }

    private func fix(_ engine: AutocorrectEngine, before: String) -> String? {
        engine.replacementOnSpace(beforeInput: before, field: .text, autocorrectionType: .default)?.replacement
    }

    /// French elisions ("l'", "qu'"), typed on the AZERTY's apostrophe key: a slip on either
    /// side of the apostrophe is fixed as a word of its own, an elision a key away from the one
    /// typed becomes it, and a whole word the dictionary knows, a lone "l'" and every other
    /// language's apostrophes stay as typed.
    func testFrenchElisionsAreCorrectedOnEitherSide() {
        let french = stubbed {
            $0.valid = ["homme", "il", "ici", "est", "accord", "ai", "aujourd'hui"]
            $0.guessTable = ["hpmme": ["homme"], "eat": ["est"], "acvord": ["accord"]]
        }
        french.setLanguage(.french, available: ["fr_FR"])
        XCTAssertEqual(fix(french, before: "l'hpmme"), "l'homme")
        XCTAssertEqual(fix(french, before: "Je dis l'hpmme"), "l'homme")
        XCTAssertEqual(fix(french, before: "L'hpmme"), "L'homme")
        XCTAssertEqual(fix(french, before: "d'acvord"), "d'accord")
        XCTAssertEqual(fix(french, before: "c'eat"), "c'est")
        XCTAssertEqual(fix(french, before: "k'homme"), "l'homme", "a slip in the elision")
        XCTAssertEqual(fix(french, before: "qi'il"), "qu'il")
        XCTAssertNil(fix(french, before: "l'homme"))
        XCTAssertNil(fix(french, before: "j'ai"))
        XCTAssertNil(fix(french, before: "aujourd'hui"))
        XCTAssertNil(fix(french, before: "l'"))
        XCTAssertNil(fix(french, before: "zz'homme"), "no elision a key away")
        let english = stubbed {
            $0.valid = ["man"]
            $0.guessTable = ["hpmme": ["homme"]]
        }
        english.setLanguage(.english, available: ["en_US"])
        XCTAssertNil(fix(english, before: "l'hpmme"), "other languages never split a word at its apostrophe")
    }

    /// French and English on one keyboard (Apple's "Français et English"): a word of either is
    /// never "corrected" into the other, a typo only one can fix gets its fix, and when both
    /// can, the language of the words before wins, else the keyboard's own.
    func testBilingualAutocorrectNeverCorrectsOneLanguageIntoTheOther() {
        let available = ["fr_FR", "en_US"]
        let english = StubChecker()
        english.valid = ["the", "see", "you", "meeting", "at", "noon"]
        english.guessTable = ["mercu": ["mercy"], "est": ["east", "set"], "meetign": ["meeting"], "chst": ["chat"]]
        english.completionTable = ["mer": ["merry", "mercy"]]
        let french = stubbed {
            $0.valid = ["je", "pense", "que", "dont", "est", "le", "chat", "merci"]
            $0.guessTable = ["mercu": ["merci"], "the": ["thé"], "chst": ["chat"], "dont": ["don't"]]
            $0.completionTable = ["mer": ["merci", "mercredi"]]
        }
        french.setLanguage(.french, available: available)
        french.setPartner(.english, available: available, checker: english)
        XCTAssertEqual(french.partner?.language, .english)

        XCTAssertNil(fix(french, before: "the"), "an English word stays on the French keyboard")
        XCTAssertNil(fix(french, before: "dont"), "French \"dont\" never becomes \"don't\"")
        XCTAssertEqual(fix(french, before: "teh"), "the", "an English typo is fixed while French types")
        XCTAssertEqual(fix(french, before: "meetign"), "meeting")
        XCTAssertEqual(fix(french, before: "chst"), "chat")
        XCTAssertEqual(fix(french, before: "mercu"), "merci", "both can fix it: the keyboard's own language")
        XCTAssertEqual(fix(french, before: "je pense que mercu"), "merci")
        XCTAssertEqual(fix(french, before: "see you mercu"), "mercy", "the words before are English")
        XCTAssertEqual(Array(strip(french, "mercu").dropFirst()), ["merci", "mercy"], "both languages' fixes in the strip")
        XCTAssertEqual(Array(strip(french, "mer").dropFirst()), ["merci", "merry"], "and both languages' completions")

        // English typing with French beside it: French words stay, "i" is still "I".
        let englishFirst = stubbed { $0.valid = english.valid; $0.guessTable = english.guessTable }
        englishFirst.setLanguage(.english, available: available)
        let frenchChecker = StubChecker()
        frenchChecker.valid = ["dont", "est", "merci"]
        englishFirst.setPartner(.french, available: available, checker: frenchChecker)
        XCTAssertNil(fix(englishFirst, before: "est"))
        XCTAssertNil(fix(englishFirst, before: "dont"), "French \"dont\" stays")
        XCTAssertEqual(fix(englishFirst, before: "i"), "I")

        // No partner without a dictionary for it, or for the keyboard's own language.
        french.setPartner(.german, available: available)
        XCTAssertNil(french.partner)
        french.setPartner(.english, available: available, checker: english)
        french.setLanguage(.serbianLatin, available: available)
        XCTAssertNil(french.partner)
    }

    /// A partner whose dictionary takes any letters for a word (the iOS 27.2 simulator's pl_PL
    /// has no word data) is left out: English beside it still fixes "teh", where it kept every
    /// typo as "a Polish word"; a partner whose dictionary works still keeps its words.
    func testAPartnerDictionaryThatTakesEveryWordIsIgnored() {
        let available = ["en_US", "pl_PL"]
        let english = stubbed {
            $0.valid = ["the", "and", "just"]
            $0.guessTable = ["tge": ["the"], "jest": ["just"]]
        }
        english.setLanguage(.english, available: available)
        let empty = StubChecker()
        empty.acceptsEverything = true
        english.setPartner(.polish, available: available, checker: empty)
        XCTAssertEqual(english.partner?.language, .polish)
        XCTAssertEqual(fix(english, before: "teh"), "the")
        XCTAssertEqual(fix(english, before: "tge"), "the")
        XCTAssertTrue(strip(english, "tge").contains("the"))
        XCTAssertEqual(fix(english, before: "jest"), "just", "no working Polish dictionary to keep it")

        english.setPartner(nil, available: available)
        let polish = StubChecker()
        polish.valid = ["jest", "tak"]
        english.setPartner(.polish, available: available, checker: polish)
        XCTAssertNil(fix(english, before: "jest"), "a Polish word stays beside a working Polish dictionary")
        XCTAssertEqual(fix(english, before: "teh"), "the")
    }

    /// X (Philippe), English with French or German beside it: the other dictionary takes many
    /// English typos for words ("dont" and "im" are French and German words, iOS's French and
    /// German dictionaries take "dk", "dl" and "ro"), so they were kept and the held-out English
    /// benchmark went from 5.24% to 7.07% WER with French beside it. Once the words before are
    /// English, its sure fixes apply again (missing apostrophes, common slips, two letters);
    /// the other language's longer words stay, and at a sentence's start the next word decides.
    func testBesideAnotherLanguageEnglishStillFixesItsOwnTypos() {
        let available = ["en_US", "fr_FR", "de_DE"]
        let english = stubbed {
            $0.valid = ["we", "said", "that", "do", "not", "know", "going", "home", "the", "to"]
            $0.guessTable = ["mervi": ["mercy"]]
        }
        english.setLanguage(.english, available: available)
        let french = StubChecker()
        french.valid = ["dont", "im", "dk", "est", "merci", "je", "pense", "que", "mervi"]
        english.setPartner(.french, available: available, checker: french)

        XCTAssertEqual(fix(english, before: "we said that dont"), "don't", "the words before are English")
        XCTAssertEqual(fix(english, before: "we said that im"), "I'm")
        XCTAssertEqual(fix(english, before: "we said that dk"), "do", "a two-letter slip")
        XCTAssertNil(fix(english, before: "we said that est"), "a longer French word stays")
        XCTAssertNil(fix(english, before: "we said that merci"))
        XCTAssertNil(fix(english, before: "je pense que dont"), "French words before: French \"dont\" stays")
        XCTAssertNil(fix(english, before: "dont"), "nothing before tells: kept for now")
        XCTAssertEqual(fix(english, before: "dk"), "do", "a partner's word without a vowel (an abbreviation) is no word")

        func revised(_ word: String, next: String) -> String? {
            english.revision(of: word, before: word, next: next, field: .text, autocorrectionType: .default)
        }
        XCTAssertEqual(revised("Dont", next: "know"), "Don't", "an English word after it says it was English")
        XCTAssertEqual(revised("Im", next: "going"), "I'm")
        XCTAssertNil(revised("Dont", next: "je"), "a French word after it")
        XCTAssertNil(revised("Dont", next: "est"), "a word both or only French know tells nothing")
        XCTAssertNil(english.revision(of: "dont", before: "je pense que dont", next: "know", field: .text, autocorrectionType: .default),
                     "French words before it")

        let german = StubChecker()
        german.valid = ["im", "haus", "sommer"]
        english.setPartner(.german, available: available, checker: german)
        XCTAssertNil(revised("Im", next: "Haus"), "German \"Im Haus\" stays")
        XCTAssertEqual(revised("Im", next: "going"), "I'm")
        XCTAssertEqual(fix(english, before: "we said that im"), "I'm")
    }

    /// TestFlight build 56 (English and Portuguese): Apple's keyboard puts "nao sei" right once
    /// "sei" says it was Portuguese. A word only one language knows as typed ("voce" is an
    /// English word) takes the other's accents once the next word leans that one; never a
    /// guess that changes its letters, nor when the words before lean the other way.
    func testTheNextWordGivesTheWordBeforeItsLanguagesAccents() {
        let available = ["en_US", "pt_BR"]
        let english = stubbed { $0.valid = ["voce", "ate", "so", "we", "i", "lunch", "logo"] }
        english.setLanguage(.english, available: available)
        let portuguese = StubChecker()
        portuguese.valid = ["você", "esta", "até", "amanhã", "só", "logo", "eu"]
        portuguese.guessTable = ["voce": ["voe", "você"], "ate": ["até", "ata"], "so": ["só", "sol"], "we": ["wi"]]
        english.setPartner(.portuguese, available: available, checker: portuguese)

        func revised(_ word: String, before: String? = nil, next: String) -> String? {
            english.revision(of: word, before: before ?? word, next: next, field: .text, autocorrectionType: .default)
        }
        XCTAssertEqual(revised("voce", next: "esta"), "você")
        XCTAssertEqual(english.lastRevisionLanguage, .portuguese, "the fix is Portuguese's")
        XCTAssertEqual(revised("Voce", next: "esta"), "Você")
        XCTAssertEqual(revised("ate", next: "amanhã"), "até")
        XCTAssertNil(revised("ate", next: "lunch"), "an English word after it")
        XCTAssertNil(revised("ate", next: "logo"), "a word both know tells nothing")
        XCTAssertNil(revised("so", before: "we ate lunch so", next: "esta"), "English words before it")
        XCTAssertNil(revised("we", next: "esta"), "only a respelling with accents")
        XCTAssertNil(revised("lunch", next: "esta"), "no guess of Portuguese's")
    }

    private func strip(_ engine: AutocorrectEngine, _ typed: String) -> [String] {
        engine.suggestions(beforeInput: typed, field: .text, autocorrectionType: .default).map(\.replacement)
    }

    func testCompletionsKeepTheDictionarysFrequencyOrderAheadOfYourContacts() {
        let engine = stubbed {
            $0.valid = ["zo"]
            // Most probable first, as UITextChecker lists them; not by length or alphabet.
            $0.completionTable = ["zo": ["zone", "zoo", "zombie", "zones"]]
        }
        engine.loadLexiconEntries([("Zorbin", "Zorbin"), ("Zoltrax", "Zoltrax"), ("zoeticket", "zoeticket")])
        XCTAssertEqual(strip(engine, "zo"), ["zo", "zone", "zoo"])
        XCTAssertEqual(strip(engine, "Zo"), ["Zo", "Zone", "Zoo"], "a capital at the start of a sentence still means words first")
    }

    /// TestFlight (build 56, the video): "helli" typed mid-sentence went in as "Hello". A fix
    /// brought the capital of where it came from: picked at the start of a sentence ("Helli"
    /// to "Hello", learned), a guess iOS knows capitalised, a Contacts name that is also a word
    /// ("Bell"). Apple's keyboard writes the word as the sentence needs it, and keeps the
    /// capital of a name the dictionary knows only capitalised ("Taylor").
    func testAFixBringsNoCapitalOfItsOwnMidSentence() {
        let engine = stubbed {
            $0.valid = ["hello", "hell", "bell", "belt"]
            $0.capitalised = ["Taylor"]
            $0.guessTable = ["helli": ["Hello", "hell"], "taylr": ["Taylor"]]
            $0.completionTable = ["bel": ["belt"]]
        }
        engine.applyLearning(TypingLearning(typos: ["hrllo": "Hello"], rejected: []))
        engine.loadLexiconEntries([("Bell", "Bell"), ("Kate", "Kate")])
        XCTAssertEqual(fix(engine, "myem helli"), "hello")
        XCTAssertEqual(fix(engine, "Helli"), "Hello", "a capital you typed stays")
        XCTAssertEqual(fix(engine, "so hrllo"), "hello", "a fix learned at the start of a sentence")
        XCTAssertEqual(fix(engine, "so taylr"), "Taylor", "a name keeps its capital")
        XCTAssertEqual(strip(engine, "myem helli"), ["helli", "hello", "hell"])
        XCTAssertEqual(strip(engine, "so bel"), ["bel", "belt", "bell"], "a contact Bell, offered as the word")
        XCTAssertEqual(strip(engine, "so Bel"), ["Bel", "Belt", "Bell"])
    }

    /// TestFlight (build 56, iPhone 17 Pro): "Getting random words capitalized", with
    /// "Testing how this World" swiped and "Works" in the strip. Your own words that are also
    /// common words (a Contacts name or a text replacement whose phrase is its shortcut, a fix
    /// learned at a sentence's start) stay lowercase mid-sentence with Auto-capitalization off
    /// too, while a name the dictionary knows only capitalised, a text replacement's phrase and
    /// a word in your vocabulary keep the capitals you gave them (#2205).
    func testYourCommonWordsStayLowercaseAndYourVocabularyKeepsItsCapitals() {
        let engine = stubbed {
            $0.valid = ["world", "works", "will", "swift", "thanks"]
            $0.capitalised = ["Kate"]
        }
        engine.loadLexiconEntries([("World", "World"), ("Will", "Will"), ("Kate", "Kate"), ("thx", "Thanks")])
        engine.applyLearning(TypingLearning(typos: ["wrks": "Works"], rejected: []))
        engine.setVocabulary(["Swift"])
        for addsCapitals in [true, false] {
            engine.addsCapitals = addsCapitals
            let mode = addsCapitals ? "on" : "off"
            XCTAssertFalse(engine.isOwnSpelling("World"), "a common word, \(mode)")
            XCTAssertFalse(engine.isOwnSpelling("Works"), "a fix learned capitalised, \(mode)")
            XCTAssertTrue(engine.isOwnSpelling("Kate"), "a name, \(mode)")
            XCTAssertTrue(engine.isOwnSpelling("Thanks"), "a text replacement's phrase, \(mode)")
            XCTAssertTrue(engine.isOwnSpelling("Swift"), "your vocabulary's spelling, \(mode)")
            XCTAssertEqual(engine.withoutStrayCapital("Swift", typed: ""), "Swift", mode)
            XCTAssertEqual(strip(engine, "so wor"), ["wor", "world"], mode)
            XCTAssertEqual(strip(engine, "so thx"), ["thx", "Thanks"], mode)
            XCTAssertEqual(fix(engine, "so wrks"), "works", mode)
            XCTAssertEqual(fix(engine, "so swift"), "Swift", mode)
        }
    }

    func testNamesComeLastUnlessYouTypedACapital() {
        let engine = stubbed {
            $0.valid = ["qu"]
            $0.completionTable = ["qu": ["Quilla", "quip", "quiz"]]
        }
        engine.loadLexiconEntries([("Quorvent", "Quorvent"), ("qubitly", "qubitly")])
        XCTAssertEqual(strip(engine, "qu"), ["qu", "quip", "quiz"])
        XCTAssertEqual(strip(engine, "Qu"), ["Qu", "Quilla", "Quip"], "you typed a capital: names keep their place")

        // With fewer dictionary words, your own lowercase word comes before a name.
        let few = stubbed {
            $0.valid = ["qu"]
            $0.completionTable = ["qu": ["Quilla", "quip"]]
        }
        few.loadLexiconEntries([("Quorvent", "Quorvent"), ("qubitly", "qubitly")])
        XCTAssertEqual(strip(few, "qu"), ["qu", "quip", "qubitly"])
        XCTAssertEqual(strip(few, "Qu"), ["Qu", "Quilla", "Quip"])
        // Nothing else: a contact's name is still offered.
        let names = stubbed { $0.valid = ["qu"] }
        names.loadLexiconEntries([("Quorvent", "Quorvent")])
        XCTAssertEqual(strip(names, "qu"), ["qu", "Quorvent"])
    }

    func testTheStripNeverRepeatsWhatYouTyped() {
        let engine = stubbed {
            $0.valid = ["k", "kay"]
            $0.completionTable = ["k": ["k", "know", "keep"], "kay": ["kay", "kayak"]]
        }
        XCTAssertEqual(strip(engine, "k"), ["k", "know", "keep"], "one letter gets completions too")
        XCTAssertEqual(strip(engine, "kay"), ["kay", "kayak"])
        XCTAssertEqual(strip(engine, "Kay"), ["Kay", "Kayak"])
        XCTAssertEqual(strip(engine, "kq"), ["kq"], "nothing to offer: only the left slot, not a second copy")
        XCTAssertEqual(
            engine.suggestions(beforeInput: "kq", field: .text, autocorrectionType: .default).map(\.kind),
            [.keepLiteral]
        )
    }

    /// German's model is Android's, byte for byte: the same v3 file, with its own language
    /// and a vocabulary of lowercase German words ("haus", never "haua").
    func testTheBundledGermanModelLoads() throws {
        let model = try XCTUnwrap(TypingDecoderModel.bundled("de"), "the German model is bundled")
        XCTAssertEqual(model.language, "de")
        XCTAssertGreaterThan(model.wordCount, 50_000)
        XCTAssertNotNil(model.index(of: "haus"), "a common German word")
        XCTAssertNil(model.index(of: "haua"), "not a word")
    }

    /// The capitalisation sidecar rides beside the German model (same bundle, same embedded
    /// keyboard fallback): common nouns are written with a capital nearly always, while a word
    /// that is also a common verb form ("frage" 94, "reise" 94) or a stem people type alone
    /// ("kauf" 94, "schlaf" 94) is in the list below that, and a pure verb or function word is
    /// 50-94 too ("leben" 82) or absent.
    func testTheBundledGermanCapitalsLoad() throws {
        let capitals = try XCTUnwrap(GermanCapitals.bundled(), "de.capitals is bundled with the German model")
        for noun in ["haus", "bild", "auto", "zeit"] {
            XCTAssertGreaterThanOrEqual(capitals.percent(of: noun) ?? 0, 95, noun)
        }
        for verb in ["frage", "reise", "folge", "kauf", "schlaf", "koch", "spiel"] {
            XCTAssertLessThan(capitals.percent(of: verb) ?? 0, 95, verb)
        }
        for other in ["machen", "ist"] {
            XCTAssertNil(capitals.percent(of: other), other)
        }
    }

    /// Settings › Experiments › German spatial autocorrect, off by default, gates German alone.
    /// Without it the Deutsch layout keeps the dictionary engine exactly as before: no word
    /// list either, so no letter odds, no model completions in the strip, and no partner model.
    /// English and Spanish never wait on the experiment.
    func testTheGermanTypingModelNeedsItsExperiment() {
        let settings = FullKeyboardSettings(defaults: defaults)
        XCTAssertFalse(settings.germanSpatialAutocorrect, "off by default")
        XCTAssertNil(settings.typingModel(for: .german), "no German model unless the experiment is on")
        settings.spatialAutocorrect = true
        XCTAssertNil(settings.typingModel(for: .german), "and never without Spatial autocorrect")
        settings.germanSpatialAutocorrect = true
        XCTAssertEqual(settings.typingModel(for: .german)?.language, "de")
        settings.spatialAutocorrect = false
        XCTAssertNil(settings.typingModel(for: .german), "Spatial autocorrect off turns it off again")
        XCTAssertEqual(settings.typingModel(for: .english)?.language, "en", "English never waits on the experiment")
        XCTAssertEqual(settings.typingModel(for: .spanish)?.language, "es")
        settings.spatialAutocorrect = true
        XCTAssertEqual(settings.typingModel(for: .english)?.language, "en")
        XCTAssertEqual(settings.typingModel(for: .spanish)?.language, "es")
    }

    /// German spells every noun with a capital, and its model is lowercase throughout: a noun
    /// the decoder corrects to takes its capital, and so does one typed right, as the list
    /// beside the model (`de.capitals`) decides. Apple's German dictionary takes "haus",
    /// "auto" and "zeit" lowercase, so it cannot be the one to tell.
    func testGermanSpatialAutocorrectCapitalisesTheNounItCorrects() throws {
        let layout = KeyboardLayout(width: 393, language: .german)
        let keys = try XCTUnwrap(TypingDecoder.Keys(layout: layout))
        let checker = StubChecker()
        checker.valid = ["ist", "das", "die", "zu", "haus", "auto", "zeit", "leben",
                         "ich", "frage", "wollt", "ihr", "essen", "heute", "kauf",
                         "lass", "mich", "in"]
        checker.capitalised = ["Stadt", "Abend"]
        let autocorrect = AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: defaults))
        autocorrect.setLanguage(.german, available: ["de"])
        autocorrect.germanCapitals = GermanCapitals(percentages: [
            "haus": 99, "auto": 99, "zeit": 98, "leben": 60, "frage": 94, "essen": 61, "abend": 94,
            "kauf": 94, "ruhe": 94,
        ])
        autocorrect.decoder = TypingDecoder(model: try XCTUnwrap(TypingDecoderModel.bundled("de")))
        autocorrect.decoderKeys = keys
        func fix(_ before: String, taps: String) -> String? {
            autocorrect.decoderTaps = taps.map { keys.centres[$0]! }
            return autocorrect.replacementOnSpace(beforeInput: before, field: .text, autocorrectionType: .default)?.replacement
        }
        // A tap on a where s was meant, and on s where a was meant: both read "haus".
        XCTAssertEqual(fix("das haua", taps: "haua"), "Haus")
        XCTAssertEqual(fix("das hsus", taps: "hsus"), "Haus")
        // Typed right, the noun still takes its capital after the article.
        XCTAssertEqual(fix("das haus", taps: "haus"), "Haus")
        // Written with a capital only half the time: a noun after an article or determiner,
        // and the verb elsewhere ("zu leben").
        XCTAssertEqual(fix("das leben", taps: "leben"), "Leben")
        XCTAssertNil(fix("zu leben", taps: "leben"))
        // A 50-94% word with no determiner before it keeps the dictionary's rule: a verb form
        // stays lowercase ("ich frage", "wollt ihr essen"), and a word the dictionary knows
        // only capitalised still takes its capital ("heute abend" -> "heute Abend").
        XCTAssertNil(fix("ich frage", taps: "frage"))
        XCTAssertNil(fix("wollt ihr essen", taps: "essen"))
        XCTAssertNil(fix("ich kauf", taps: "kauf"))
        XCTAssertEqual(fix("heute abend", taps: "abend"), "Abend")
        // "in" takes a noun, unlike the pronoun "ihr".
        XCTAssertEqual(fix("lass mich in ruhe", taps: "ruhe"), "Ruhe")
        // A word the list doesn't know keeps the dictionary's rule too.
        XCTAssertEqual(fix("die stadt", taps: "stadt"), "Stadt")
        // Auto-capitalization off adds no capital you did not type.
        autocorrect.addsCapitals = false
        XCTAssertNil(fix("das haus", taps: "haus"))
        XCTAssertEqual(fix("das haua", taps: "haua"), "haus")
    }

    func testTheBundledListMarksSlursAndSwearWordsAndLeavesAnatomyAlone() {
        let en = OffensiveWords.bundled("en")
        XCTAssertEqual(en.kind(of: "nigger"), .slur)
        XCTAssertEqual(en.kind(of: "Faggots"), .slur, "inflections, any case")
        XCTAssertEqual(en.kind(of: "chink"), .slur, "slurs LDNOOBW lacks")
        XCTAssertEqual(en.kind(of: "fuck"), .swear)
        XCTAssertEqual(en.kind(of: "damn"), .swear)
        for word in ["penis", "vagina", "anus", "sex", "suck", "rape", "escort", "scat", "xx"] {
            XCTAssertNil(en.kind(of: word), "\(word) is an everyday, anatomy, medical or reporting word")
        }
        XCTAssertTrue(en.blocks("blow job", allowSwearing: false), "an expression")
        XCTAssertTrue(en.blocks("job", allowSwearing: false, after: "blow"), "an expression's second word after its first")
        XCTAssertFalse(en.blocks("blow", allowSwearing: false), "an expression's words alone are fine")
        XCTAssertFalse(en.blocks("job", allowSwearing: false, after: "a"))
        XCTAssertTrue(en.blocks("the shit", allowSwearing: false), "a listed word inside a split")
        XCTAssertFalse(en.blocks("the shit", allowSwearing: true))
        XCTAssertTrue(en.blocks("the nigger", allowSwearing: true))
        let es = OffensiveWords.bundled("es")
        XCTAssertEqual(es.kind(of: "maricón"), .slur)
        XCTAssertEqual(es.kind(of: "mierda"), .swear)
        XCTAssertNil(es.kind(of: "negro"), "Spanish for black")
        XCTAssertNil(es.kind(of: "cono"), "accents are kept: coño is listed, cono (cone) isn't")
        XCTAssertEqual(OffensiveWords.bundled("de").kind(of: "scheisse"), .swear)
        XCTAssertNil(OffensiveWords.bundled("de").kind(of: "dick"), "German for thick")
        XCTAssertEqual(OffensiveWords.bundled("nb").kind(of: "faen"), .swear)
        XCTAssertNil(OffensiveWords.bundled("nb").kind(of: "fag"), "Norwegian for a trade")
        let it = OffensiveWords.bundled("it")
        XCTAssertEqual(it.kind(of: "nigger"), .slur, "every layout shares the loanwords")
        XCTAssertEqual(it.kind(of: "fuck"), .swear)
        XCTAssertNil(it.kind(of: "chink"))
    }

    func testAnExpressionIsBlockedOnlyAfterItsFirstWord() {
        let autocorrect = stubbed {
            $0.valid = ["blow", "a", "jo", "job", "joke"]
            $0.completionTable = ["jo": ["job", "joke"]]
        }
        XCTAssertEqual(Array(strip(autocorrect, "blow jo").dropFirst()), ["joke"])
        XCTAssertEqual(Array(strip(autocorrect, "a jo").dropFirst()), ["job", "joke"])
        autocorrect.allowsSwearing = true
        XCTAssertEqual(Array(strip(autocorrect, "blow jo").dropFirst()), ["job", "joke"])
    }

    func testSwearWordsAreNeverGuessedOrCompletedUnlessTurnedOn() {
        let autocorrect = stubbed {
            $0.valid = ["ship", "duck", "fuchsia"]
            $0.guessTable = ["shiy": ["shit", "ship"]]
            $0.completionTable = ["fuc": ["fuck", "fucking", "fuchsia"]]
        }
        XCTAssertEqual(fix(autocorrect, "shiy"), "ship", "shit is a closer key, but never offered")
        XCTAssertFalse(strip(autocorrect, "shiy").contains("shit"))
        XCTAssertEqual(Array(strip(autocorrect, "fuc").dropFirst()), ["fuchsia"])

        autocorrect.allowsSwearing = true
        XCTAssertEqual(fix(autocorrect, "shiy"), "shit")
        XCTAssertEqual(Array(strip(autocorrect, "fuc").dropFirst()), ["fuck", "fucking"])
    }

    func testSlursAreNeverOfferedEvenWithSwearWordsOn() {
        let autocorrect = stubbed {
            $0.guessTable = ["niggr": ["nigger", "nigga"], "fagot": ["faggot", "fagots"]]
            $0.completionTable = ["nig": ["nigger", "night", "nigh"]]
            $0.valid = ["night", "nigh", "fagots"]
        }
        autocorrect.allowsSwearing = true
        XCTAssertNil(fix(autocorrect, "niggr"))
        XCTAssertEqual(strip(autocorrect, "niggr"), ["niggr"])
        XCTAssertEqual(fix(autocorrect, "fagot"), "fagots")
        XCTAssertEqual(Array(strip(autocorrect, "nig").dropFirst()), ["night", "nigh"])
    }

    func testAnOffensiveWordTypedInFullIsNeverCorrected() {
        let autocorrect = stubbed {
            $0.guessTable = ["fuck": ["duck", "luck"], "nigger": ["bigger", "niggle"]]
        }
        XCTAssertNil(fix(autocorrect, "fuck"), "UITextChecker may not know it, but you typed it")
        XCTAssertNil(fix(autocorrect, "Nigger"))
        XCTAssertFalse(autocorrect.suggestions(beforeInput: "fuck", field: .text, autocorrectionType: .default)
            .contains(where: \.willAutoReplace))
        autocorrect.allowsSwearing = true
        XCTAssertEqual(fix(autocorrect, "fuck"), "duck", "with swear words on, it's an ordinary word, as on Android")
        XCTAssertNil(fix(autocorrect, "Nigger"), "a slur typed in full still stays")
    }

    func testYourOwnContactsAndReplacementsAreStillOffered() {
        let autocorrect = stubbed { $0.completionTable = ["dic": ["dick", "dictionary"]] }
        autocorrect.loadLexiconEntries([("Dick", "Dick"), ("wtf", "what the fuck")])
        XCTAssertEqual(Array(strip(autocorrect, "Dic").dropFirst()), ["Dick", "Dictionary"])
        XCTAssertEqual(fix(autocorrect, "wtf"), "what the fuck")
    }

    // MARK: - Spatial autocorrect on a layout (Hex types these through its engine)

    /// An `AutocorrectEngine` reading taps with the bundled model, as the keyboard sets it up
    /// with Spatial autocorrect on. `checker` defaults to the system dictionary.
    private func decoding(_ language: KeyboardLanguage, checker: TextChecking = SystemTextChecker()) throws -> (AutocorrectEngine, TypingDecoder.Keys) {
        let autocorrect = AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: defaults))
        autocorrect.setLanguage(language, available: ["en_US", "es_ES"])
        let model = try XCTUnwrap(TypingDecoderModel.bundled(language.rawValue), "the \(language) model is bundled")
        autocorrect.decoder = TypingDecoder(model: model)
        let keys = try XCTUnwrap(TypingDecoder.Keys(layout: KeyboardLayout(width: 393, language: language)))
        autocorrect.decoderKeys = keys
        return (autocorrect, keys)
    }

    /// What space puts in place of `typed`, tapped at the keys' centres, after `before`.
    private func atSpace(_ autocorrect: AutocorrectEngine, _ keys: TypingDecoder.Keys, _ typed: String, after before: String = "") -> String {
        autocorrect.decoderTaps = typed.map { keys.centres[$0]! }
        let word = autocorrect.replacementOnSpace(beforeInput: before + typed, field: .text, autocorrectionType: .default)
        return word?.replacement ?? typed
    }

    /// Hex's `testSpatialAutocorrectReadsTapsWithTheWordBefore` and
    /// `testSpatialAutocorrectLeavesWordsTypedRight`, word by word, on a fixed dictionary.
    func testEnglishSpatialAutocorrectReadsTapsAndLeavesWordsTypedRight() throws {
        let checker = StubChecker()
        checker.valid = ["see", "on", "with", "the", "thank", "you"]
        let (autocorrect, keys) = try decoding(.english, checker: checker)
        autocorrect.addsCapitals = false
        for (typed, before) in [("see", ""), ("on", "see mary "), ("with", "on monday ")] {
            XCTAssertEqual(atSpace(autocorrect, keys, typed, after: before), typed, "typed right")
        }
        XCTAssertEqual(atSpace(autocorrect, keys, "thw", after: "see "), "the")
        XCTAssertEqual(atSpace(autocorrect, keys, "ypu", after: "thank "), "you")
    }

    /// Hex's `testSpatialAutocorrectAddsSpanishAccents`, on a fixed dictionary.
    func testSpatialAutocorrectAddsSpanishAccents() throws {
        let checker = StubChecker()
        checker.valid = ["esta", "está", "aquí", "mañana"]
        let (autocorrect, keys) = try decoding(.spanish, checker: checker)
        XCTAssertEqual(atSpace(autocorrect, keys, "esta"), "esta", "\"esta\" is a word too, so it stays")
        XCTAssertEqual(atSpace(autocorrect, keys, "aqui", after: "esta "), "aquí")
        XCTAssertEqual(atSpace(autocorrect, keys, "manana", after: "esta aquí "), "mañana")
    }

    func testTheBundledEnglishAndSpanishModelsLoad() throws {
        for (code, word) in [("en", "the"), ("es", "mañana")] {
            let model = try XCTUnwrap(TypingDecoderModel.bundled(code), "the \(code) model is bundled")
            XCTAssertEqual(model.language, code)
            XCTAssertGreaterThan(model.wordCount, 50_000)
            XCTAssertNotNil(model.index(of: word), word)
        }
    }

    // MARK: - Adaptive touch: personal centres rank readings, never correct on their own

    func testPersonalCentresNeverRewriteAWordTheStockCentresKeep() throws {
        let (ac, stock) = try decoding(.english)
        // A profile far past the experiment's bounds: b's centre sits on m, and c's on b.
        var personal = stock
        personal.centres["b"] = stock.centres["m"]
        personal.centres["c"] = stock.centres["b"]
        ac.decoderKeys = personal
        let bat = "bat".map { stock.centres[$0]! }
        func atSpace(_ taps: [CGPoint], stockKeys: TypingDecoder.Keys?) -> String? {
            ac.decoderBaselineKeys = stockKeys
            ac.decoderTaps = taps
            return ac.replacementOnSpace(beforeInput: "the bat", field: .text, autocorrectionType: .default)?.replacement
        }
        XCTAssertEqual(atSpace(bat, stockKeys: nil), "cat", "alone, the personal centres would rewrite \"bat\"")
        let nudged = bat.map { CGPoint(x: $0.x + 0.01, y: $0.y) }
        XCTAssertNil(atSpace(nudged, stockKeys: stock), "the stock centres keep it: no new rewrite")
        let strip = ac.suggestions(beforeInput: "the bat", field: .text, autocorrectionType: .default)
        XCTAssertTrue(strip.contains { $0.replacement == "cat" && !$0.willAutoReplace }, "offered, not applied: \(strip)")

        // A fix both make still goes in.
        ac.decoderKeys = stock
        let thw = "thw".map { stock.centres[$0]! }
        ac.decoderBaselineKeys = stock
        ac.decoderTaps = thw
        XCTAssertEqual(ac.replacementOnSpace(beforeInput: "see thw", field: .text, autocorrectionType: .default)?.replacement, "the")
    }

    func testTheDecodersReplacementCheckAgreesWithItsDecision() throws {
        let (autocorrect, keys) = try decoding(.english)
        let decoder = try XCTUnwrap(autocorrect.decoder)
        for (typed, previous, valid) in [("thw", "see", false), ("teh", nil, false), ("bat", "the", true), ("helo", "say", false), ("ypu", "thank", false)] {
            let taps = typed.map { keys.centres[$0]! }
            let decision = try XCTUnwrap(decoder.decide(taps: taps, typed: typed, previous: previous, literalIsValid: valid, keys: keys))
            if let replacement = decision.replacement, !replacement.contains(" ") {
                XCTAssertEqual(decoder.replaces(with: replacement, taps: taps, typed: typed, previous: previous, literalIsValid: valid, keys: keys), true, typed)
            }
            let margin = valid || decoder.model.index(of: typed) != nil ? decoder.parameters.validMargin : decoder.parameters.autoMargin
            for reading in decision.readings where !reading.text.contains(" ") {
                XCTAssertEqual(
                    decoder.replaces(with: reading.text, taps: taps, typed: typed, previous: previous, literalIsValid: valid, keys: keys),
                    decision.literalCost - reading.cost >= margin, "\(typed) → \(reading.text)"
                )
            }
        }
    }
}
