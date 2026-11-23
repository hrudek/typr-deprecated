import Foundation

/// Hex's standalone hesitation rule for German, Spanish, and Norwegian. The caller owns
/// style and casing. Typr fixes on the Hex base preserve source separators and punctuation.
nonisolated enum HexSpokenHesitations {
    private static let sentenceMarks: Set<Character> = [".", "?", "!", "…"]
    private static let pauses: Set<Character> = [",", ";", ":"]
    private static let closers: Set<Character> = ["\"", "'", "”", "“", "’", "‘", "»", "«", "›", "‹", ")", "]", "}"]
    private static let trailingMarks = sentenceMarks.union(pauses).union(closers)

    static func remove(from text: String, language: String?) -> String {
        let code = language.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        guard let code, ["de", "es", "nb", "nn", "no"].contains(code),
              let pattern = TranscriptFormatter.fillerPattern(for: code),
              let hesitation = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: .caseInsensitive) else {
            return text
        }

        var result = ""
        var start = text.startIndex
        for index in text.indices where text[index].isNewline {
            result += remove(in: text[start..<index], matching: hesitation)
            result.append(text[index])
            start = text.index(after: index)
        }
        return result + remove(in: text[start...], matching: hesitation)
    }

    private static func remove(in line: Substring, matching hesitation: NSRegularExpression) -> String {
        let words = line.split(whereSeparator: \.isWhitespace)
        var index = 0
        var cursor = line.startIndex
        var result = ""

        while index < words.count {
            guard let firstSuffix = suffix(of: words[index], matching: hesitation) else {
                index += 1
                continue
            }
            var suffix = String(firstSuffix)
            let start = index
            index += 1
            var multipleClosures = false
            while index < words.count, let next = self.suffix(of: words[index], matching: hesitation) {
                if suffix.contains(where: closers.contains), next.contains(where: closers.contains) {
                    multipleClosures = true
                }
                suffix = joining(suffix, with: next)
                index += 1
            }
            guard !multipleClosures else { continue }

            if start == 0 {
                // A quote or bracket that opened on a preceding line may close here.
                guard !suffix.contains(where: closers.contains) else { continue }
                result += line[cursor..<words[start].startIndex]
                cursor = index < words.count ? words[index].startIndex : words[index - 1].endIndex
            } else {
                let previous = words[start - 1]
                let end = previous.endIndex
                let mark = previous.last
                let previousHasPause = mark.map(pauses.contains) == true
                let previousEndsSentence = previous.reversed().drop(while: closers.contains).first
                    .map(sentenceMarks.contains) ?? false
                let hasBoundary = suffix.contains(where: sentenceMarks.contains)
                if previousEndsSentence {
                    suffix = String(suffix.drop(while: { sentenceMarks.contains($0) || pauses.contains($0) }))
                } else if suffix == ",", previousHasPause || index == words.count {
                    suffix = ""
                }
                let replacePause = (hasBoundary || suffix.first.map(pauses.contains) == true) && previousHasPause
                    || (index == words.count && mark == "," && suffix.isEmpty)
                result += line[cursor..<(replacePause ? line.index(before: end) : end)]
                result += suffix
                cursor = words[index - 1].endIndex
            }
        }
        return result + line[cursor...]
    }

    private static func joining(_ suffix: String, with next: Substring) -> String {
        let endsSentence = suffix.contains(where: sentenceMarks.contains)
        let nextEndsSentence = next.contains(where: sentenceMarks.contains)
        if suffix.contains(where: closers.contains) {
            return !endsSentence && nextEndsSentence ? suffix + next : suffix
        }
        if next.contains(where: closers.contains), endsSentence, !nextEndsSentence {
            return suffix + next
        }
        return !next.isEmpty && (!endsSentence || next.contains(where: closers.contains)) ? String(next) : suffix
    }

    private static func suffix(of word: Substring, matching hesitation: NSRegularExpression) -> Substring? {
        let stem = word.dropLast(word.reversed().prefix(while: trailingMarks.contains).count)
        let suffix = word[stem.endIndex...]
        // A hesitation that asks or exclaims is an utterance in its own right.
        guard !suffix.contains("?"), !suffix.contains("!"),
              hesitation.firstMatch(in: String(stem), range: NSRange(location: 0, length: stem.utf16.count)) != nil else {
            return nil
        }
        return suffix
    }
}
