import Foundation

/// "Clean up what I say": deterministic German and English word rules, adapted from Hex's
/// `SpokenCleanupRules` and `CleanupReconstruction` (anomalyco/hex d65b02d3, MIT). Hex's
/// English cleanup tagger is not used: it is English only and dropped negations in other
/// languages. The rules only remove words:
/// - hesitation sounds ("äh", "ähm", "öh", "hm"; English also "um", "uh"), never "eh"
///   ("das ist eh egal") or a sound that asks or exclaims ("Hm?");
/// - a stuttered function word ("ich ich habe"), never an emphatic repeat ("sehr sehr");
/// - an explicit self-repair ("am Dienstag, ich meine, Mittwoch") with its marker and the words
///   it replaces, counted back from the nearest earlier word that matches the repair's first
///   word or is of its kind (number, weekday, month, relative day), within the sentence and
///   `maxReach` words. A bare "nein", "no" or "sorry" counts only when the repair names a
///   word of the same kind, and never right after a question. Anything else stays as said.
nonisolated enum SpokenCleanup {
    static let maxReach = 8

    struct Rules {
        let hesitation: NSRegularExpression
        let markers: [[String]]
        let plainMarkers: [[String]]
        let weakMarkers: [[String]]
        let kinds: [Set<String>]
        let noComma: Set<String>
        let stutters: Set<String>

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
        let original = words(in: text)
        var cleaned = removingHesitations(original, rules: rules)
        cleaned = removingStutters(cleaned, rules: rules)
        cleaned = resolvingCorrections(cleaned, rules: rules)
        return cleaned == original ? text : cleaned.joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: Hesitations and stutters

    private static func removingHesitations(_ words: [String], rules: Rules) -> [String] {
        let deletes = words.map { isHesitation($0, rules) }
        guard deletes.contains(true) else { return words }
        return self.words(in: reconstruct(words, deletes: deletes, rules: rules))
    }

    private static func isHesitation(_ word: String, _ rules: Rules) -> Bool {
        guard !hasOpeningMark(word), let last = word.last, last != "?", last != "!" else { return false }
        let bare = bare(word)
        return rules.hesitation.firstMatch(in: bare, range: NSRange(bare.startIndex..., in: bare)) != nil
    }

    private static func removingStutters(_ words: [String], rules: Rules) -> [String] {
        var deletes = Array(repeating: false, count: words.count)
        var kept = 0
        for index in words.indices.dropFirst() {
            let previous = words[kept]
            let word = bare(words[index])
            let joined = previous.last.map { $0 == "," || !closingMarks.contains($0) } ?? false
            if joined, !hasOpeningMark(words[index]), rules.stutters.contains(word), bare(previous) == word {
                deletes[index] = true
            } else {
                kept = index
            }
        }
        guard deletes.contains(true) else { return words }
        return self.words(in: reconstruct(words, deletes: deletes, rules: rules))
    }

    // MARK: Corrections

    private struct Correction {
        let start: Int
        let markerEnd: Int
        let repair: Int
    }

    private static func resolvingCorrections(_ input: [String], rules: Rules) -> [String] {
        var words = input
        var from = 0
        while let found = nextCorrection(in: words, from: from, rules: rules) {
            words[found.repair] = taking(words[found.start], into: words[found.repair])
            var deletes = Array(repeating: false, count: words.count)
            for position in found.start...found.markerEnd {
                deletes[position] = true
            }
            words = self.words(in: reconstruct(words, deletes: deletes, rules: rules))
            from = found.start + 1
        }
        return words
    }

    private static func nextCorrection(in words: [String], from: Int, rules: Rules) -> Correction? {
        guard max(1, from) < words.count else { return nil }
        for markerStart in max(1, from)..<words.count {
            for marker in rules.markers where matches(marker, words, at: markerStart) {
                let markerEnd = markerStart + marker.count - 1
                let repair = markerEnd + 1
                guard repair < words.count, !hasOpeningMark(words[markerStart]) else { continue }
                let before = words[markerStart - 1]
                if before.hasSuffix("?") { continue }
                let setOff = (isPause(before) || endsSentence(before)) && words[markerEnd].hasSuffix(",")
                let plain = rules.plainMarkers.contains(marker)
                    && !endsSentence(before)
                    && !isPause(words[markerEnd])
                    && !endsSentence(words[markerEnd])
                guard setOff || plain else { continue }
                let first = bare(words[repair])
                guard !first.isEmpty else { continue }

                var low = markerStart - 1
                while low > 0, !endsSentence(words[low - 1]), markerStart - low < maxReach {
                    low -= 1
                }
                let candidates = (low..<markerStart).reversed()
                var start = candidates.first { bare(words[$0]) == first }
                if start == nil, let kind = rules.kind(of: first) {
                    start = candidates.first { rules.kind(of: bare(words[$0])) == kind }
                }
                guard let start else { continue }
                if rules.weakMarkers.contains(marker) {
                    let repairKinds = Set(words[repair..<min(repair + 2, words.count)].compactMap { rules.kind(of: bare($0)) })
                    let replacedKinds = Set(words[start..<markerStart].compactMap { rules.kind(of: bare($0)) })
                    guard !repairKinds.isDisjoint(with: replacedKinds) else { continue }
                }
                return Correction(start: start, markerEnd: markerEnd, repair: repair)
            }
        }
        return nil
    }

    private static func taking(_ replaced: String, into repair: String) -> String {
        let marks = String(replaced.prefix { openingMarks.contains($0) })
        var result = repair
        if !marks.isEmpty, !hasOpeningMark(result) {
            result = marks + result
        }
        guard let source = replaced.dropFirst(marks.count).first, source.isLetter,
              let index = result.firstIndex(where: \.isLetter),
              !result[result.index(after: index)...].contains(where: \.isUppercase) else {
            return result
        }
        let letter = String(result[index])
        result.replaceSubrange(index...index, with: source.isUppercase ? letter.uppercased() : letter.lowercased())
        return result
    }

    // MARK: Reconstruction

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

    // MARK: Words

    private static let openingMarks: Set<Character> = ["\"", "“", "„", "«", "(", "¿", "¡"]
    private static let closingMarks: Set<Character> = [",", ".", ";", ":", "!", "?", "…", "\"", "”", "“", "»", ")"]

    private static func bare(_ word: String) -> String {
        var scalars = Substring(word)
        while let first = scalars.first, openingMarks.contains(first) {
            scalars = scalars.dropFirst()
        }
        while let last = scalars.last, closingMarks.contains(last) {
            scalars = scalars.dropLast()
        }
        return scalars.lowercased()
    }

    private static func matches(_ phrase: [String], _ words: [String], at index: Int) -> Bool {
        guard index + phrase.count <= words.count else { return false }
        for (offset, part) in phrase.enumerated() {
            let word = words[index + offset]
            if offset < phrase.count - 1, let last = word.last, last != ",", closingMarks.contains(last) {
                return false
            }
            if bare(word) != part { return false }
        }
        return true
    }

    private static func isPause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ",;:".contains(last)
    }

    private static func endsSentence(_ word: String) -> Bool {
        let trimmed = word.reversed().drop { "\"”»)".contains($0) }
        guard let last = trimmed.first else { return false }
        return ".!?…".contains(last)
    }

    private static func hasOpeningMark(_ word: String) -> Bool {
        word.first.map(openingMarks.contains) ?? false
    }

    // MARK: Languages

    private static func hesitations(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: "^(?:\(pattern))$", options: .caseInsensitive)
    }

    private static let germanHesitations = "ä+h+m*|ö+h+m*|e+h+m+|hm+"

    private static let german = Rules(
        hesitation: hesitations(germanHesitations),
        markers: [["nein"], ["nein", "warte"], ["ich", "meine"], ["besser", "gesagt"], ["sorry"],
                  ["entschuldigung"]],
        plainMarkers: [["besser", "gesagt"]],
        weakMarkers: [["nein"], ["sorry"], ["entschuldigung"]],
        kinds: [
            ["zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"],
            ["montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag"],
            ["januar", "jänner", "februar", "märz", "april", "mai", "juni", "juli", "august", "september",
             "oktober", "november", "dezember"],
            ["heute", "morgen", "gestern", "übermorgen"],
        ],
        noComma: ["und", "oder", "aber", "dass", "der", "die", "das", "ein", "eine", "mit", "zu", "in",
                  "an", "auf", "für", "von", "ich", "du", "er", "sie", "wir"],
        stutters: ["ich", "wir", "du", "ein", "eine", "einen", "und", "oder", "aber", "dass", "weil", "wenn",
                   "dann", "ist", "mit", "zu", "im", "am", "auf", "für"]
    )

    private static let english = Rules(
        hesitation: hesitations(germanHesitations + "|u+m+|u+h+m*|e+r+m+"),
        markers: [["no"], ["no", "wait"], ["i", "mean"], ["or", "rather"], ["sorry"]],
        plainMarkers: [["or", "rather"]],
        weakMarkers: [["no"], ["sorry"]],
        kinds: [
            ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"],
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
            ["january", "february", "march", "april", "june", "july", "august", "september", "october",
             "november", "december"],
            ["today", "tomorrow", "yesterday", "tonight"],
        ],
        noComma: ["a", "an", "the", "to", "of", "for", "with", "and", "or", "but", "i", "we", "you", "my"],
        stutters: ["i", "we", "the", "a", "an", "and", "but", "of", "for", "with", "my", "to"]
    )
}
