import Foundation

/// One learned dictation fix: words the speech model keeps getting wrong, and what you meant.
nonisolated struct DictationCorrection: Equatable, Sendable {
    let heard: String
    let meant: String
    /// False when every fix was made at a sentence start, so `meant`'s first letter follows the
    /// word it replaces.
    let caseIsKnown: Bool
}

/// Applies learned dictation fixes after transcription, with word boundaries and case.
nonisolated enum DictationCorrections {
    private static let joiners: Set<Character> = ["-", "_", "/", "\\", "@", "#", "&", "+", "=", "~", "*", "."]

    /// Replaces each heard word or phrase (matched ignoring case, whole words only, never inside
    /// a longer word or a hyphenated, dotted or slashed token) with what you meant.
    static func apply(_ corrections: [DictationCorrection], to text: String) -> String {
        guard !corrections.isEmpty, !text.isEmpty else { return text }
        var table: [[String]: DictationCorrection] = [:]
        var longest = 1
        for correction in corrections {
            let keys = DictationText.words(in: correction.heard).map { DictationText.key($0.text) }
            guard !keys.isEmpty, keys.count <= DictationEditClassifier.maxPairWords,
                  !correction.meant.isEmpty, table[keys] == nil else { continue }
            table[keys] = correction
            longest = max(longest, keys.count)
        }
        guard !table.isEmpty else { return text }

        let words = DictationText.words(in: text)
        var output = ""
        output.reserveCapacity(text.count)
        var copied = text.startIndex
        var index = 0
        while index < words.count {
            var matched = 0
            for count in stride(from: min(longest, words.count - index), through: 1, by: -1) {
                let window = Array(words[index..<(index + count)])
                let range = window[0].range.lowerBound..<window[count - 1].range.upperBound
                guard isJoinedBySpaces(window, in: text),
                      let correction = table[window.map { DictationText.key($0.text) }],
                      isBounded(range, in: text) else { continue }
                output.append(contentsOf: text[copied..<range.lowerBound])
                output.append(matchCase(correction, like: String(text[range]),
                                        sentenceStart: DictationText.isSentenceStart(window[0], in: text)))
                copied = range.upperBound
                matched = count
                break
            }
            index += max(1, matched)
        }
        output.append(contentsOf: text[copied...])
        return output
    }

    /// Learned spellings with a capital inside a word ("GitHub"), which a style must not undo.
    static func spellings(_ corrections: [DictationCorrection]) -> [String] {
        corrections.map(\.meant).filter { $0.dropFirst().contains(where: \.isUppercase) }
    }

    /// An all-caps original stays all caps and a spelling with capitals is kept. A small first
    /// letter you typed mid-sentence stays small unless the fix starts a sentence; one only
    /// seen at sentence starts follows the original's.
    static func matchCase(_ correction: DictationCorrection, like original: String, sentenceStart: Bool) -> String {
        let meant = correction.meant
        let letters = original.filter(\.isLetter)
        if letters.count >= 2, letters == letters.uppercased(), letters != letters.lowercased() {
            return meant.uppercased()
        }
        if meant.contains(where: \.isUppercase) { return meant }
        let capital = correction.caseIsKnown
            ? sentenceStart
            : original.first(where: \.isLetter)?.isUppercase == true
        guard capital, let head = meant.first else { return meant }
        return head.uppercased() + meant.dropFirst()
    }

    private static func isJoinedBySpaces(_ window: [DictationWord], in text: String) -> Bool {
        for index in window.indices.dropFirst() {
            let gap = text[window[index - 1].range.upperBound..<window[index].range.lowerBound]
            guard !gap.isEmpty, gap.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }
        }
        return true
    }

    /// Not part of a longer token: no joiner right before, and none right after except a
    /// sentence-ending period.
    private static func isBounded(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex, joiners.contains(text[text.index(before: range.lowerBound)]) {
            return false
        }
        guard range.upperBound < text.endIndex else { return true }
        let next = text[range.upperBound]
        guard joiners.contains(next) else { return true }
        guard next == "." else { return false }
        let afterDot = text.index(after: range.upperBound)
        guard afterDot < text.endIndex else { return true }
        let following = text[afterDot]
        return following.isWhitespace || following == "." || "\"”“’')]".contains(following)
    }
}

/// A word-level dictation fix with how often you made it. Holds at most three words a side,
/// never the dictation itself.
nonisolated struct DictationFixRecord: Codable, Equatable, Sendable {
    /// As Typr inserted it.
    var heard: String
    /// As you left it.
    var meant: String
    var caseIsKnown: Bool
    var count: Int
    /// Times you showed this fix is wrong: you kept the heard words in a dictation you
    /// corrected, changed the fix to something else, or fixed the other way round.
    var contradictions: Int
    var lastAt: TimeInterval

    static let limit = 200

    /// Folds one dictation into the records: a count for each pair, then contradictions.
    static func merging(_ result: DictationEditResult, into records: [DictationFixRecord],
                        at now: TimeInterval) -> [DictationFixRecord] {
        var records = records
        for pair in result.pairs {
            let heardKey = DictationText.phraseKey(pair.inserted)
            // Only a capital you added teaches anything when the words stay the same.
            guard heardKey != DictationText.phraseKey(pair.meant) || pair.meant.contains(where: \.isUppercase)
            else { continue }
            if let index = records.firstIndex(where: {
                $0.meant == pair.meant && DictationText.phraseKey($0.heard) == heardKey
            }) {
                records[index].count += 1
                records[index].lastAt = now
                records[index].caseIsKnown = records[index].caseIsKnown || pair.caseIsKnown
            } else {
                records.append(DictationFixRecord(heard: pair.inserted, meant: pair.meant, caseIsKnown: pair.caseIsKnown,
                                                  count: 1, contradictions: 0, lastAt: now))
            }
        }

        for index in records.indices where contradicts(result, records[index]) {
            records[index].contradictions += 1
        }

        if records.count > limit {
            let drop = records.indices
                .sorted { (records[$0].count, records[$0].lastAt) < (records[$1].count, records[$1].lastAt) }
                .prefix(records.count - limit)
            for index in drop.sorted(by: >) { records.remove(at: index) }
        }
        return records
    }

    private static func contradicts(_ result: DictationEditResult, _ fix: DictationFixRecord) -> Bool {
        let heardKey = DictationText.phraseKey(fix.heard)
        let meantKey = DictationText.phraseKey(fix.meant)
        let heardRun = heardKey.split(separator: " ").map(String.init)
        if heardKey != meantKey, result.keptWords.contains(where: { $0.containsRun(heardRun) }) {
            return true
        }
        for pair in result.pairs {
            let pairInserted = DictationText.phraseKey(pair.inserted)
            let pairMeant = DictationText.phraseKey(pair.meant)
            let pairLetters = DictationText.letters(pair.meant)
            let fixLetters = DictationText.letters(fix.meant)
            let extended = pairLetters.count > fixLetters.count && pairLetters.hasPrefix(fixLetters)
            let changedFix = pairInserted == meantKey && pairMeant != meantKey && !extended
            let reversed = pairMeant == heardKey && pairInserted == meantKey
            if changedFix || reversed { return true }
        }
        return false
    }
}

/// A learned dictation fix as Settings lists it.
nonisolated struct DictationLearnedFix: Equatable, Sendable, Identifiable {
    var id: String
    var heard: String
    var meant: String
    var caseIsKnown: Bool
    var count: Int
    var contradictions: Int

    var correction: DictationCorrection { DictationCorrection(heard: heard, meant: meant, caseIsKnown: caseIsKnown) }
}

/// When a (heard → meant) substitution becomes a fix Typr applies.
nonisolated enum DictationLearningRule {
    static let minimumCount = 2

    /// Every substitution you made, grouped by heard and meant words ignoring case. A capital
    /// you used is kept as the spelling.
    static func candidates(from records: [DictationFixRecord]) -> [DictationLearnedFix] {
        var groups: [String: DictationLearnedFix] = [:]
        var order: [String] = []
        for record in records {
            let heardKey = DictationText.phraseKey(record.heard)
            let meantKey = DictationText.phraseKey(record.meant)
            guard !heardKey.isEmpty, !meantKey.isEmpty else { continue }
            let id = heardKey + " → " + meantKey
            var group = groups[id] ?? DictationLearnedFix(id: id, heard: heardKey, meant: record.meant,
                                                          caseIsKnown: false, count: 0, contradictions: 0)
            if groups[id] == nil { order.append(id) }
            group.count += record.count
            group.contradictions += record.contradictions
            group.caseIsKnown = group.caseIsKnown || record.caseIsKnown
            if record.meant.contains(where: \.isUppercase) { group.meant = record.meant }
            groups[id] = group
        }
        return order.compactMap { groups[$0] }
    }

    /// Fixes seen at least twice, never contradicted, and whose heard words you only ever
    /// fixed one way. Anything else stays a record and is never applied.
    static func learned(from records: [DictationFixRecord]) -> [DictationLearnedFix] {
        let all = candidates(from: records)
        var meanings: [String: Int] = [:]
        for fix in all { meanings[fix.heard, default: 0] += 1 }
        return all.filter { fix in
            fix.count >= minimumCount && fix.contradictions == 0 && meanings[fix.heard] == 1
        }
    }
}

/// The word pairs Learn from my edits gathered, in the shared App Group: the keyboard records
/// them, dictation applies the learned ones and Settings lists and deletes them.
nonisolated struct DictationLearningStore {
    private static let key = "dictationLearning.fixes"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var records: [DictationFixRecord] {
        get {
            guard let data = defaults?.data(forKey: Self.key) else { return [] }
            return (try? JSONDecoder().decode([DictationFixRecord].self, from: data)) ?? []
        }
        nonmutating set {
            if newValue.isEmpty {
                defaults?.removeObject(forKey: Self.key)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: Self.key)
            }
        }
    }

    /// Most used first.
    var learnedFixes: [DictationLearnedFix] {
        DictationLearningRule.learned(from: records)
            .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

    var corrections: [DictationCorrection] { learnedFixes.map(\.correction) }

    func record(_ result: DictationEditResult, at now: TimeInterval = Date().timeIntervalSince1970) {
        guard !result.pairs.isEmpty || !result.keptWords.isEmpty else { return }
        let current = records
        let merged = DictationFixRecord.merging(result, into: current, at: now)
        if merged != current { records = merged }
    }

    /// Forgets every record behind a learned fix, so it is learned again only from new edits.
    func delete(_ fix: DictationLearnedFix) {
        records = records.filter {
            DictationText.phraseKey($0.heard) + " → " + DictationText.phraseKey($0.meant) != fix.id
        }
    }

    func deleteAll() {
        records = []
    }
}
