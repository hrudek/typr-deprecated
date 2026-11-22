import Foundation

/// Words the words around them decide, after anomalyco/hex #2231 and #2144 (MIT, see
/// THIRD_PARTY_NOTICES.md): the word before takes the next word's language's umlauts, and
/// with Words from context on, sound-alike and apostrophe words follow their neighbours.
@MainActor
extension TyprAutocorrectEngine {
    /// English words chosen by the words around them rather than as typos (Hex's list):
    /// the same letters with and without an apostrophe, and words that sound alike. "were"
    /// and "we're" stay out: the word pairs can't tell them apart.
    static let contextGroups: [[String]] = [
        ["id", "I'd"], ["ill", "I'll"], ["hell", "he'll"], ["shell", "she'll"],
        ["wed", "we'd"], ["lets", "let's"], ["well", "we'll"],
        ["its", "it's"], ["your", "you're"], ["there", "their", "they're"], ["then", "than"],
    ]

    /// A contraction is also scored as the words it stands for, the better of the two.
    static let contractionWords: [String: [[String]]] = [
        "i'd": [["i", "would"], ["i", "had"]], "i'll": [["i", "will"]], "he'll": [["he", "will"]],
        "she'll": [["she", "will"]], "we'd": [["we", "would"], ["we", "had"]], "let's": [["let", "us"]],
        "we'll": [["we", "will"]], "it's": [["it", "is"], ["it", "has"]], "you're": [["you", "are"]],
        "they're": [["they", "are"]],
    ]

    /// German "es" contractions the Duden writes with an apostrophe, typed without one.
    static let germanContractions: [String: String] = [
        "gehts": "geht's", "gibts": "gibt's", "stimmts": "stimmt's", "klappts": "klappt's",
    ]

    private static let contextGroupOf: [String: [String]] = {
        var out: [String: [String]] = [:]
        for group in contextGroups { for word in group { out[word.lowercased()] = group } }
        return out
    }()

    /// Hex's margins in nats: with the word before only, and once the next word is known;
    /// changing letters ("your"/"you're") needs more than an apostrophe alone.
    private static let contextMargin = (previous: 3.0, next: 1.5)
    private static let contextLetterMargin = (previous: 6.0, next: 3.0)
    private static let contextUnknownCost = 15.0
    /// A next word that never follows "will", "would", "had" or "us" speaks against the
    /// contraction ending in it ("till hell freezes").
    private static let contextMissingFollower = 5.0
    private static let contextRichFollowers: Set<String> = ["will", "would", "had", "us"]

    /// The word of `word`'s group that the words around it make clearly likelier, cased as
    /// typed, or nil. Also the German apostrophe contractions. Only with Words from context.
    func contextChoice(for word: String, previous: String?, next: String?) -> String? {
        guard choosesWordsFromContext, isEnabled, !word.contains("'"), !word.contains("’"),
              !word.dropFirst().contains(where: \.isUppercase) else { return nil }
        let lower = word.lowercased()
        if german != nil, next == nil, let contraction = Self.germanContractions[lower] {
            return Self.matchCase(of: word, onto: contraction)
        }
        guard englishEnabled, let pack = contextResources.model?.en, let group = Self.contextGroupOf[lower],
              german?.blocksEnglishFix(lower) != true else { return nil }
        let previous = previous.map(KeyboardContextModel.key)
        let next = next.map(KeyboardContextModel.key)
        let own = Self.contextCost(lower, previous: previous, next: next, pack: pack)
        var best: (word: String, cost: Double)?
        for other in group where other.lowercased() != lower {
            let cost = Self.contextCost(other.lowercased(), previous: previous, next: next, pack: pack)
            if cost < best?.cost ?? .infinity { best = (other, cost) }
        }
        guard let best else { return nil }
        let sameLetters = best.word.replacingOccurrences(of: "'", with: "").lowercased() == lower
        let margins = sameLetters ? Self.contextMargin : Self.contextLetterMargin
        guard own - best.cost >= (next == nil ? margins.previous : margins.next) else { return nil }
        guard word.first?.isUppercase == true, !best.word.hasPrefix("I'") else { return best.word }
        return best.word.prefix(1).uppercased() + best.word.dropFirst()
    }

    /// -ln P(`word` | `previous`) + -ln P(`next` | `word`), a contraction as its words.
    private static func contextCost(_ word: String, previous: String?, next: String?,
                                    pack: KeyboardContextModel.Pack) -> Double {
        func cost(_ word: String, after context: String?) -> Double {
            let p = pack.probability(word, after: context)
            return p > 0 ? -log(p) : contextUnknownCost
        }
        var best = Double.infinity
        for words in [[word]] + (contractionWords[word] ?? []) {
            var total = cost(words[0], after: previous)
            for k in words.indices.dropFirst() { total += cost(words[k], after: words[k - 1]) }
            if let next, let last = words.last {
                total += cost(next, after: last)
                if contextRichFollowers.contains(last), let id = pack.id(next),
                   !pack.distribution(last).boosts.contains(where: { $0.id == id }) {
                    total += contextMissingFollower
                }
            }
            best = min(best, total)
        }
        return best
    }

    /// The word before the one just finished, revised now that `next` follows it, or nil to
    /// leave it. `before` is the text up to the end of `word`.
    func revision(of word: String, before: String, next: String) -> String? {
        let lower = word.lowercased()
        guard isEnabled, word.count >= 2,
              !protectedLexicon.contains(word), !suppressedInSession.contains(lower),
              !learning.protections.isKept(word), !lexiconTermKeys.contains(lower),
              lexiconShortcuts[lower] == nil, !Self.shorthandAllowlist.contains(lower) else { return nil }
        guard !word.dropFirst().contains(where: \.isUppercase) else { return nil }
        let rest = String(before.dropLast(word.count))
        let context = RejectedCorrection.context(before: before, token: word)
        let previous = Self.lastWord(of: context)
        let startsSentence = rest.trimmingCharacters(in: .whitespaces).last.map { ".!?\n".contains($0) } ?? true
        guard let choice = accentRevision(of: word, rest: rest, next: next)
                ?? contextChoice(for: word, previous: startsSentence ? KeyboardContextModel.bos : previous, next: next),
              choice != word, mayOffer(choice, after: previous),
              !learning.protections.isRejected(typed: word, replacement: choice, context: context) else { return nil }
        return choice
    }

    /// Hex #2231 for German and English: a word kept because only one language knows it
    /// ("fur" is English) takes the other's umlauts or ß once the next word leans that one
    /// ("fur die" -> "für die"). Only a respelling that adds them alone, to a word typed
    /// without any, and not when the words before lean the other way.
    private func accentRevision(of word: String, rest: String, next: String) -> String? {
        guard let german, englishEnabled, next.count >= 2 else { return nil }
        let lean = languageLean(next, commonFrom: 2)
        guard lean != 0, languageLean(rest, commonFrom: 3) * lean >= 0 else { return nil }
        let intoGerman = lean > 0
        guard knowsAsTyped(word, german: !intoGerman), !knowsAsTyped(word, german: intoGerman) else { return nil }
        let lower = word.lowercased()
        guard Self.plain(lower) == lower else { return nil }
        let guesses = intoGerman ? GermanAutocorrect.variants(of: lower) + german.guesses(for: lower)
                                 : checker.guesses(for: lower)
        let capital = word.first?.isUppercase == true
        for guess in guesses where Self.plain(guess.lowercased()) == lower && guess.lowercased() != lower {
            let spellings = capital ? [guess, guess.prefix(1).uppercased() + guess.dropFirst()] : [guess]
            for spelling in spellings where capital || spelling == spelling.lowercased() {
                if intoGerman ? german.isValid(spelling) : checker.isWordValid(spelling) {
                    return Self.matchCase(of: word, onto: spelling)
                }
            }
        }
        return nil
    }

    private func knowsAsTyped(_ word: String, german inGerman: Bool) -> Bool {
        let lower = word.lowercased()
        if inGerman {
            guard let german else { return false }
            return german.isValid(word) || german.isValid(lower)
        }
        return checker.isWordValid(word) || checker.isWordValid(lower)
    }

    /// The language `text`'s last words lean to, which a word learned at its end is kept under.
    func learningLanguage(_ text: String) -> SpatialWordDecoder.Language? {
        let lean = languageLean(text, commonFrom: 2)
        return lean > 0 ? .german : lean < 0 ? .english : nil
    }

    /// Learn each language separately: a word learned only in the other language than the
    /// sentence's, and unknown to the sentence language's dictionary, is not offered.
    func learnedElsewhere(_ word: String, sentence language: SpatialWordDecoder.Language?) -> Bool {
        guard let language, let learned = learning.model.language(of: word), learned != language else { return false }
        return !knowsAsTyped(word, german: language == .german)
    }

    /// Positive when the last words lean German, negative for English: a word only one
    /// dictionary knows counts for it, one both know by the typing models' odds when it has
    /// at least `commonFrom` letters.
    private func languageLean(_ text: String, commonFrom: Int) -> Int {
        var lean = 0
        for part in text.suffix(120).split(whereSeparator: { !$0.isLetter && $0 != "'" }).suffix(4) where part.count >= 2 {
            let word = String(part)
            switch (knowsAsTyped(word, german: true), knowsAsTyped(word, german: false)) {
            case (true, false): lean += 1
            case (false, true): lean -= 1
            case (true, true) where word.count >= commonFrom:
                let odds = contextResources.model?.evidence(KeyboardContextModel.key(word)) ?? 0
                if odds >= 1 { lean += 1 } else if odds <= -1 { lean -= 1 }
            default: break
            }
        }
        return lean
    }

    /// Without umlauts and accents, ß as ss.
    private static func plain(_ word: String) -> String {
        word.folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "ß", with: "ss")
    }
}
