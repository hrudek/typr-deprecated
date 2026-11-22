import Foundation

/// A word in dictated or typed text: letters and digits, with apostrophes inside it.
nonisolated struct DictationWord: Equatable, Sendable {
    let text: String
    let range: Range<String.Index>
}

nonisolated enum DictationText {
    static func words(in text: String) -> [DictationWord] {
        var result: [DictationWord] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            let isWordCharacter = character.isLetter || character.isNumber
                || (isApostrophe(character) && start != nil && next < text.endIndex && text[next].isLetter)
            if isWordCharacter {
                if start == nil { start = index }
            } else if let wordStart = start {
                result.append(DictationWord(text: String(text[wordStart..<index]), range: wordStart..<index))
                start = nil
            }
            index = next
        }
        if let wordStart = start {
            result.append(DictationWord(text: String(text[wordStart...]), range: wordStart..<text.endIndex))
        }
        return result
    }

    static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }

    /// How two words compare: lowercased, with curly apostrophes made straight.
    static func key(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    /// A phrase's word keys joined by single spaces.
    static func phraseKey(_ phrase: String) -> String {
        words(in: phrase).map { key($0.text) }.joined(separator: " ")
    }

    /// Letters and digits only, lowercased, so spacing and punctuation don't count.
    static func letters(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }

    /// Whether a word begins a sentence: after a period, question or exclamation mark, a line
    /// break, or nothing at all.
    static func isSentenceStart(_ word: DictationWord, in text: String) -> Bool {
        var index = word.range.lowerBound
        while index > text.startIndex {
            index = text.index(before: index)
            let character = text[index]
            if character.isNewline { return true }
            if character.isWhitespace || "\"“”„'‘’‚([".contains(character) { continue }
            return ".!?…".contains(character)
        }
        return true
    }
}

/// A dictation Typr inserted, remembered by the text right around it rather than by
/// position, because the host only shows the text near the cursor and it moves.
nonisolated struct DictationInsertion: Equatable, Sendable {
    static let anchorLength = 32

    let inserted: String
    let anchorBefore: String
    let anchorAfter: String

    init(inserted: String, before: String?, after: String?) {
        self.inserted = inserted
        anchorBefore = String((before ?? "").suffix(Self.anchorLength))
        anchorAfter = String((after ?? "").prefix(Self.anchorLength))
    }
}

/// The text that now sits where the dictation went.
nonisolated struct DictationSpan: Equatable, Sendable {
    var text: String
    /// False when the start can't be told from the host cutting its context short
    /// (the dictation began the field and text now sits before the cursor).
    var startIsCertain: Bool
    /// False when the end can't be told from the host cutting its context short.
    var endIsCertain: Bool

    var hasWords: Bool { !DictationText.words(in: text).isEmpty }
}

nonisolated enum DictationSpanLocator {
    /// Finds the dictation between its anchors in the text around the cursor, or nil
    /// when the context is missing or the anchors are gone (another field, or edited).
    static func locate(_ insertion: DictationInsertion, before: String?, after: String?) -> DictationSpan? {
        guard before != nil || after != nil else { return nil }
        let currentBefore = before ?? ""
        let currentAfter = after ?? ""
        let text = currentBefore + currentAfter
        let starts: [String.Index] = insertion.anchorBefore.isEmpty
            ? [text.startIndex]
            : text.ranges(of: insertion.anchorBefore).map(\.upperBound)
        let ends: [String.Index] = insertion.anchorAfter.isEmpty
            ? [text.endIndex]
            : text.ranges(of: insertion.anchorAfter).map(\.lowerBound)
        guard !starts.isEmpty, !ends.isEmpty else { return nil }

        let expected = insertion.inserted.count
        var best: (range: Range<String.Index>, miss: Int)?
        for start in starts.prefix(16) {
            for end in ends.prefix(16) where start <= end {
                let miss = abs(text.distance(from: start, to: end) - expected)
                if best.map({ miss < $0.miss }) ?? true {
                    best = (start..<end, miss)
                }
            }
        }
        guard let range = best?.range,
              text.distance(from: range.lowerBound, to: range.upperBound) <= expected * 4 + 200
        else { return nil }
        return DictationSpan(
            text: String(text[range]),
            startIsCertain: !insertion.anchorBefore.isEmpty || currentBefore.isEmpty,
            endIsCertain: !insertion.anchorAfter.isEmpty || currentAfter.isEmpty
        )
    }
}

nonisolated enum DictationWordDiff {
    /// A run of old words replaced by a run of new words; either side may be empty.
    struct Hunk: Equatable, Sendable {
        var old: Range<Int>
        var new: Range<Int>
    }

    static let maxCells = 250_000

    /// The changes from `old` to `new`, by longest common subsequence of whole words.
    static func hunks(_ old: [String], _ new: [String]) -> [Hunk] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        let a = Array(old[prefix..<(old.count - suffix)])
        let b = Array(new[prefix..<(new.count - suffix)])
        if a.isEmpty && b.isEmpty { return [] }
        if a.isEmpty || b.isEmpty || a.count * b.count > maxCells {
            return [Hunk(old: prefix..<(prefix + a.count), new: prefix..<(prefix + b.count))]
        }

        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var hunks: [Hunk] = []
        var i = 0, j = 0
        var open: (i: Int, j: Int)?
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                if let start = open {
                    hunks.append(Hunk(old: (prefix + start.i)..<(prefix + i), new: (prefix + start.j)..<(prefix + j)))
                    open = nil
                }
                i += 1
                j += 1
            } else {
                if open == nil { open = (i, j) }
                if j >= m || (i < n && table[i + 1][j] >= table[i][j + 1]) {
                    i += 1
                } else {
                    j += 1
                }
            }
        }
        if let start = open {
            hunks.append(Hunk(old: (prefix + start.i)..<(prefix + n), new: (prefix + start.j)..<(prefix + m)))
        }
        return hunks
    }
}

nonisolated enum DictationOutcome: Sendable {
    /// Sent or left as Typr inserted it.
    case kept
    /// Some words fixed.
    case edited
    /// More than half of it changed: not word fixes.
    case rewritten
    /// Taken back with Undo dictation.
    case undone
    /// Deleted and not dictated again soon after.
    case deleted
    /// Deleted and dictated again soon after.
    case redictated
}

/// Words you replaced in a dictation, at most three a side.
nonisolated struct DictationEditPair: Equatable, Sendable {
    /// The words as Typr inserted them.
    var inserted: String
    /// The words you ended up with.
    var meant: String
    /// False when `meant` began a sentence, so whether its first letter is a capital is unknown
    /// and `meant` is stored with a small one.
    var caseIsKnown: Bool
}

nonisolated struct DictationEditResult: Equatable, Sendable {
    var outcome: DictationOutcome
    var pairs: [DictationEditPair] = []
    /// Runs of word keys left exactly as inserted in a dictation you corrected elsewhere, so you
    /// saw them and kept them. Never stored; used to contradict learned fixes.
    var keptWords: [[String]] = []
}

nonisolated enum DictationEditClassifier {
    static let maxPairWords = 3
    static let maxWords = 400

    /// Classifies a dictation against the text now in its place. Nil when there is nothing to
    /// judge (no words, or far too long).
    static func classify(inserted: String, final span: DictationSpan, undone: Bool = false) -> DictationEditResult? {
        let insertedWords = DictationText.words(in: inserted)
        guard !insertedWords.isEmpty, insertedWords.count <= maxWords else { return nil }
        let finalWords = DictationText.words(in: span.text)
        if finalWords.isEmpty {
            return DictationEditResult(outcome: undone ? .undone : .deleted)
        }
        guard finalWords.count <= maxWords * 2 else { return nil }

        let ins = insertedWords.map(\.text)
        let fin = finalWords.map(\.text)
        let allHunks = DictationWordDiff.hunks(ins, fin)
        let hunks = trimEdges(allHunks, old: ins, new: fin, span: span)
        guard !hunks.isEmpty else {
            return DictationEditResult(outcome: .kept)
        }

        let changed = hunks.reduce(0) { $0 + max($1.old.count, $1.new.count) }
        guard Double(changed) <= max(1, Double(ins.count) / 2) else {
            return DictationEditResult(outcome: .rewritten)
        }

        let startsSentence = ins.first?.first?.isUppercase ?? false
        var pairs: [DictationEditPair] = []
        for hunk in hunks where isReplacement(hunk) {
            let sentenceStart = hunk.new.lowerBound == 0
                ? startsSentence
                : DictationText.isSentenceStart(finalWords[hunk.new.lowerBound], in: span.text)
            if let pair = pair(ins[hunk.old], fin[hunk.new], sentenceStart: sentenceStart) {
                pairs.append(pair)
            }
        }

        return DictationEditResult(
            outcome: .edited,
            pairs: pairs,
            keptWords: keptRuns(ins, excluding: allHunks)
        )
    }

    /// A dictation you removed and dictated again within the redictation window: the words
    /// that came out differently the second time, when most of it is the same.
    static func redictation(previousInserted: String, nextInserted: String) -> DictationEditResult? {
        let oldWords = DictationText.words(in: previousInserted)
        guard !oldWords.isEmpty, oldWords.count <= maxWords else { return nil }
        let newWords = DictationText.words(in: nextInserted)
        let old = oldWords.map(\.text)
        let new = newWords.map(\.text)
        var result = DictationEditResult(outcome: .redictated)
        guard !new.isEmpty, new.count <= maxWords * 2 else { return result }

        let hunks = DictationWordDiff.hunks(old.map(DictationText.key), new.map(DictationText.key))
        let changed = hunks.reduce(0) { $0 + max($1.old.count, $1.new.count) }
        guard Double(changed) <= max(1, Double(old.count) / 2) else { return result }

        let startsSentence = new.first?.first?.isUppercase ?? false
        for hunk in hunks where isReplacement(hunk) {
            let sentenceStart = hunk.new.lowerBound == 0
                ? startsSentence
                : DictationText.isSentenceStart(newWords[hunk.new.lowerBound], in: nextInserted)
            if let pair = pair(old[hunk.old], new[hunk.new], sentenceStart: sentenceStart) {
                result.pairs.append(pair)
            }
        }
        return result
    }

    /// Whether `meant` could be a fix of `inserted` rather than different words altogether.
    static func isPlausibleFix(_ inserted: String, _ meant: String) -> Bool {
        let a = DictationText.letters(inserted)
        let b = DictationText.letters(meant)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return DictationText.distance(a, b) <= max(2, max(a.count, b.count) / 2)
    }

    private static func isReplacement(_ hunk: DictationWordDiff.Hunk) -> Bool {
        !hunk.old.isEmpty && !hunk.new.isEmpty && hunk.old.count <= maxPairWords && hunk.new.count <= maxPairWords
    }

    private static func pair(_ old: ArraySlice<String>, _ new: ArraySlice<String>, sentenceStart: Bool) -> DictationEditPair? {
        let inserted = old.joined(separator: " ")
        let typed = new.joined(separator: " ")
        guard isPlausibleFix(inserted, typed) else { return nil }
        let meant = normalizedMeant(typed, sentenceStart: sentenceStart)
        guard meant != inserted else { return nil }
        return DictationEditPair(inserted: inserted, meant: meant, caseIsKnown: meant == typed)
    }

    /// Edits at the very edges of the span are the least certain: words typed before or
    /// after it are new writing, and when the host cut the context short a missing edge
    /// is truncation, not a deletion.
    private static func trimEdges(
        _ hunks: [DictationWordDiff.Hunk],
        old: [String],
        new: [String],
        span: DictationSpan
    ) -> [DictationWordDiff.Hunk] {
        var result = hunks
        if let first = result.first, first.old.lowerBound == 0, first.new.lowerBound == 0 {
            let truncated = !span.startIsCertain
                && (first.new.isEmpty || isPartialWord(new[first.new.lowerBound], of: old[first.old], suffix: true))
            if first.old.isEmpty || truncated {
                result.removeFirst()
            } else if first.new.count > first.old.count {
                let keep = bestLength(old: old[first.old], new: new[first.new], fromEnd: true)
                result[0].new = (first.new.upperBound - keep)..<first.new.upperBound
            }
        }
        if let last = result.last, last.old.upperBound == old.count, last.new.upperBound == new.count {
            let truncated = !span.endIsCertain
                && (last.new.isEmpty || isPartialWord(new[last.new.upperBound - 1], of: old[last.old], suffix: false))
            if last.old.isEmpty || truncated {
                result.removeLast()
            } else if last.new.count > last.old.count {
                let keep = bestLength(old: old[last.old], new: new[last.new], fromEnd: false)
                result[result.count - 1].new = last.new.lowerBound..<(last.new.lowerBound + keep)
            }
        }
        return result
    }

    /// A word the host cut in half: a proper suffix (at the start) or prefix (at the end) of an old word.
    private static func isPartialWord(_ word: String, of old: ArraySlice<String>, suffix: Bool) -> Bool {
        let key = DictationText.key(word)
        return old.contains { candidate in
            let full = DictationText.key(candidate)
            return full.count > key.count && (suffix ? full.hasSuffix(key) : full.hasPrefix(key))
        }
    }

    /// How many of the new words replace the old ones; the rest is new writing.
    private static func bestLength(old: ArraySlice<String>, new: ArraySlice<String>, fromEnd: Bool) -> Int {
        let target = DictationText.letters(old.joined())
        var best = 1
        var bestScore = Int.max
        for length in 1...min(new.count, maxPairWords + 1) {
            let slice = fromEnd ? new.suffix(length) : new.prefix(length)
            let score = DictationText.distance(target, DictationText.letters(slice.joined()))
            if score < bestScore {
                best = length
                bestScore = score
            }
        }
        return best
    }

    /// A capital that only marks a sentence start isn't part of how you spell the word.
    private static func normalizedMeant(_ meant: String, sentenceStart: Bool) -> String {
        guard sentenceStart, let first = meant.first, first.isUppercase,
              !meant.dropFirst().contains(where: \.isUppercase) else { return meant }
        let firstWord = DictationText.words(in: meant).first.map { DictationText.key($0.text) } ?? ""
        guard !["i", "i'm", "i'll", "i've", "i'd"].contains(firstWord) else { return meant }
        return first.lowercased() + meant.dropFirst()
    }

    /// Runs of word keys untouched by the edit.
    private static func keptRuns(_ words: [String], excluding hunks: [DictationWordDiff.Hunk]) -> [[String]] {
        var touched = Array(repeating: false, count: words.count)
        for hunk in hunks {
            for index in hunk.old { touched[index] = true }
        }
        var runs: [[String]] = []
        var run: [String] = []
        for (index, word) in words.enumerated() {
            if !touched[index] {
                run.append(DictationText.key(word))
            } else if !run.isEmpty {
                runs.append(run)
                run = []
            }
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }
}

extension Array where Element == String {
    /// Whether `run` appears in order, without gaps, inside this array.
    nonisolated func containsRun(_ run: [String]) -> Bool {
        guard !run.isEmpty, run.count <= count else { return false }
        for start in 0...(count - run.count) where Array(self[start..<(start + run.count)]) == run {
            return true
        }
        return false
    }
}
