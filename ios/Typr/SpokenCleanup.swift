import Foundation

/// "Clean up what I say": deterministic German and English word rules, adapted from Hex's
/// `SpokenCleanupRules` and `CleanupReconstruction` (anomalyco/hex d65b02d3, MIT). Hex's
/// English cleanup tagger is not used: it is English only and dropped negations in other
/// languages. Each line is cleaned on its own (line breaks stay), and the rules only remove words. When in
/// doubt a rule leaves the text as said:
/// - hesitation sounds ("äh", "ähm", "öh", "hm"; English also "um", "uh"), never "eh"
///   ("das ist eh egal"), a sound that asks or exclaims ("Hm?") or one inside quotes;
/// - a conjunction or preposition said twice in a row, written the same ("wir und und
///   ihr"), never a pronoun or article, three or more repeats, a repeat with punctuation
///   between or one touching quotes or brackets;
/// - an explicit self-repair inside one sentence, set off by commas, that swaps a number,
///   weekday, month or relative day right before the marker for a different one of the same
///   kind and ends the clause, unless a negation comes earlier in the sentence:
///   "am Dienstag, ich meine, Mittwoch." becomes "am Mittwoch.", "um 3, nein, um 4." becomes
///   "um 4.".
nonisolated enum SpokenCleanup {
    struct Rules {
        let hesitation: NSRegularExpression
        let markers: [[String]]
        let kinds: [Set<String>]
        let units: Set<String>
        let noComma: Set<String>
        let stutters: Set<String>
        let negations: Set<String>

        func kind(of word: String) -> Int? {
            if word.contains(where: \.isNumber) { return kinds.count }
            return kinds.firstIndex { $0.contains(word) }
        }
    }

    /// `text` with hesitations, stutters and explicit self-repairs removed; `text` itself when
    /// nothing goes. Automatic reads the text as English only when `TranscriptFormatter` does.
    static func clean(_ text: String, language: DictationLanguage) -> String {
        let english = switch language {
        case .english: true
        case .german: false
        case .automatic: TranscriptFormatter.readsAsEnglish(text)
        }
        let rules = english ? Self.english : german
        var result = ""
        var line = ""
        for character in text {
            if character.isNewline {
                result += cleanLine(line, rules: rules) + String(character)
                line = ""
            } else {
                line.append(character)
            }
        }
        result += cleanLine(line, rules: rules)
        return result
    }

    private static func cleanLine(_ line: String, rules: Rules) -> String {
        let original = words(in: line)
        var cleaned = removingHesitations(original, rules: rules)
        cleaned = removingStutters(cleaned, rules: rules)
        cleaned = resolvingCorrections(cleaned, rules: rules)
        return cleaned == original ? line : cleaned.joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func removingHesitations(_ words: [String], rules: Rules) -> [String] {
        let deletes = words.map { isHesitation($0, rules) }
        guard deletes.contains(true) else { return words }
        return self.words(in: reconstruct(words, deletes: deletes, rules: rules))
    }

    private static func isHesitation(_ word: String, _ rules: Rules) -> Bool {
        guard !word.contains(where: quotesAndBrackets.contains), let last = word.last, last != "?", last != "!" else {
            return false
        }
        let bare = bare(word)
        return rules.hesitation.firstMatch(in: bare, range: NSRange(bare.startIndex..., in: bare)) != nil
    }

    private static func removingStutters(_ input: [String], rules: Rules) -> [String] {
        var words = input
        var index = 0
        while index + 1 < words.count {
            let first = words[index], second = words[index + 1]
            let isPair = first.allSatisfy { $0.isLetter }
                && !second.contains(where: quotesAndBrackets.contains)
                && rules.stutters.contains(first)
                && stripped(second) == first
                && (index == 0 || bare(words[index - 1]) != first.lowercased())
                && (index + 2 >= words.count || bare(words[index + 2]) != first.lowercased())
            guard isPair else {
                index += 1
                continue
            }
            words.remove(at: index)
            index += 1
        }
        return words
    }

    private struct Correction {
        let start: Int
        let markerEnd: Int
        let repair: Int
    }

    private static func resolvingCorrections(_ input: [String], rules: Rules) -> [String] {
        var words = input
        while let found = nextCorrection(in: words, rules: rules) {
            words[found.repair] = taking(words[found.start], into: words[found.repair])
            var deletes = Array(repeating: false, count: words.count)
            for position in found.start...found.markerEnd {
                deletes[position] = true
            }
            words = self.words(in: reconstruct(words, deletes: deletes, rules: rules))
        }
        return words
    }

    private static func nextCorrection(in words: [String], rules: Rules) -> Correction? {
        guard words.count > 2 else { return nil }
        for markerStart in 1..<words.count {
            let replaced = words[markerStart - 1]
            guard replaced.hasSuffix(","), !replaced.contains(where: quotesAndBrackets.contains),
                  let kind = rules.kind(of: bare(replaced)),
                  !sentence(before: markerStart, in: words).contains(where: { isNegation($0, rules) }) else { continue }
            for marker in rules.markers where matches(marker, words, at: markerStart) {
                let markerEnd = markerStart + marker.count - 1
                guard words[markerEnd].hasSuffix(","), markerEnd + 1 < words.count else { continue }
                var start = markerStart - 1
                var value = markerEnd + 1
                if markerStart >= 2, rules.kind(of: bare(words[markerStart - 2])) == nil,
                   !endsSentence(words[markerStart - 2]), !isPause(words[markerStart - 2]),
                   bare(words[value]) == bare(words[markerStart - 2]), value + 1 < words.count {
                    start = markerStart - 2
                    value += 1
                }
                let repaired = words[value]
                guard !repaired.contains(where: quotesAndBrackets.contains),
                      rules.kind(of: bare(repaired)) == kind, bare(repaired) != bare(replaced),
                      endsClause(at: value, in: words, rules: rules) else { continue }
                return Correction(start: start, markerEnd: markerEnd, repair: markerEnd + 1)
            }
        }
        return nil
    }

    private static func endsClause(at index: Int, in words: [String], rules: Rules) -> Bool {
        var last = index
        if last + 1 < words.count, !isPause(words[last]), !endsSentence(words[last]),
           rules.units.contains(bare(words[last + 1])) {
            last += 1
        }
        return last == words.count - 1 || isPause(words[last]) || endsSentence(words[last])
    }

    private static func sentence(before index: Int, in words: [String]) -> ArraySlice<String> {
        var start = index
        while start > 0, !endsSentence(words[start - 1]) {
            start -= 1
        }
        return words[start..<index]
    }

    private static func isNegation(_ word: String, _ rules: Rules) -> Bool {
        let bare = bare(word)
        return rules.negations.contains(bare) || bare.hasSuffix("n't") || bare.hasSuffix("n’t")
    }

    private static func taking(_ replaced: String, into repair: String) -> String {
        guard let source = replaced.first, source.isLetter,
              let index = repair.firstIndex(where: \.isLetter),
              !repair[repair.index(after: index)...].contains(where: \.isUppercase) else {
            return repair
        }
        var result = repair
        let letter = String(result[index])
        result.replaceSubrange(index...index, with: source.isUppercase ? letter.uppercased() : letter.lowercased())
        return result
    }

    private static func reconstruct(_ words: [String], deletes: [Bool], rules: Rules) -> String {
        var out: [String] = []
        var pending: [String] = []
        for (index, word) in words.enumerated() {
            if deletes[index] {
                pending.append(word)
                continue
            }
            var next = word
            if !pending.isEmpty {
                next = afterGap(&out, deleted: pending, next: word, rules: rules)
                pending.removeAll()
            }
            out.append(next)
        }
        if let lastDeleted = pending.last, var last = out.last, !endsSentence(last) {
            last = trimmingPauses(last) + terminal(lastDeleted)
            out[out.count - 1] = last
        }
        return out.joined(separator: " ")
    }

    private static func afterGap(_ out: inout [String], deleted: [String], next: String, rules: Rules) -> String {
        guard var kept = out.last else { return capitalized(next) }
        let term = terminal(deleted[deleted.count - 1])
        if kept.hasSuffix(","), rules.noComma.contains(bare(kept)) {
            kept.removeLast()
        }
        if !term.isEmpty, !endsSentence(kept), next.first?.isUppercase == true,
           deleted.allSatisfy({ isHesitation($0, rules) }) {
            kept = trimmingPauses(kept) + term
        }
        out[out.count - 1] = kept
        return endsSentence(kept) ? capitalized(next) : next
    }

    private static func terminal(_ word: String) -> String {
        guard endsSentence(word), !word.hasSuffix("..."), let last = word.last else { return "" }
        return String(last)
    }

    private static func trimmingPauses(_ word: String) -> String {
        String(word.reversed().drop { ",;:".contains($0) }.reversed())
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first, first.isLowercase, !word.dropFirst().contains(where: \.isUppercase) else {
            return word
        }
        return first.uppercased() + word.dropFirst()
    }

    private static let quotesAndBrackets: Set<Character> = [
        "\"", "'", "“", "”", "„", "‚", "‘", "’", "«", "»", "‹", "›", "(", ")", "[", "]", "{", "}",
    ]
    private static let closingMarks: Set<Character> = [",", ".", ";", ":", "!", "?", "…"]

    private static func stripped(_ word: String) -> String {
        String(word.reversed().drop { closingMarks.contains($0) }.reversed())
    }

    private static func bare(_ word: String) -> String {
        stripped(word).lowercased()
    }

    private static func matches(_ phrase: [String], _ words: [String], at index: Int) -> Bool {
        guard index + phrase.count <= words.count else { return false }
        for (offset, part) in phrase.enumerated() {
            let word = words[index + offset]
            if offset < phrase.count - 1, let last = word.last, last != ",", closingMarks.contains(last) {
                return false
            }
            if word.contains(where: quotesAndBrackets.contains) || bare(word) != part { return false }
        }
        return true
    }

    private static func isPause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ",;:".contains(last)
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ".!?…".contains(last)
    }

    private static func hesitations(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: "^(?:\(pattern))$", options: .caseInsensitive)
    }

    private static let germanHesitations = "ä+h+m*|ö+h+m*|e+h+m+|hm+"

    private static let german = Rules(
        hesitation: hesitations(germanHesitations),
        markers: [["nein"], ["nein", "warte"], ["ich", "meine"], ["besser", "gesagt"], ["sorry"],
                  ["entschuldigung"]],
        kinds: [
            ["zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"],
            ["montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag"],
            ["januar", "jänner", "februar", "märz", "april", "mai", "juni", "juli", "august", "september",
             "oktober", "november", "dezember"],
            ["heute", "morgen", "gestern", "übermorgen"],
        ],
        units: ["uhr"],
        noComma: ["und", "oder", "aber", "dass", "der", "die", "das", "ein", "eine", "mit", "zu", "in",
                  "an", "auf", "für", "von", "ich", "du", "er", "sie", "wir"],
        stutters: ["und", "weil", "für"],
        negations: ["nicht", "kein", "keine", "keinen", "keinem", "keiner", "keines", "nie", "niemals", "nichts",
                    "niemand", "nirgends", "weder", "ohne"]
    )

    private static let english = Rules(
        hesitation: hesitations(germanHesitations + "|u+m+|u+h+m*|e+r+m+"),
        markers: [["no"], ["no", "wait"], ["i", "mean"], ["or", "rather"], ["sorry"]],
        kinds: [
            ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"],
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
            ["january", "february", "march", "april", "june", "july", "august", "september", "october",
             "november", "december"],
            ["today", "tomorrow", "yesterday", "tonight"],
        ],
        units: ["pm", "am", "o'clock"],
        noComma: ["a", "an", "the", "to", "of", "for", "with", "and", "or", "but", "i", "we", "you", "my"],
        stutters: ["the", "a", "an", "and", "but", "of", "for", "with", "to"],
        negations: ["not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "without", "cannot"]
    )
}
