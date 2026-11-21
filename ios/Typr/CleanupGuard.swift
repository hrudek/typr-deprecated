import Foundation

nonisolated enum CleanupGuard {
    static let revision = "hex-ios-6f0b20c1-de"

    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            if word != nil { count += 1 }
        }
        return count
    }

    private static let negations: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere", "neither", "nor",
        "cannot", "can't", "cant", "don't", "dont", "doesn't", "doesnt", "didn't", "didnt",
        "won't", "wont", "wouldn't", "wouldnt", "shouldn't", "shouldnt", "couldn't", "couldnt",
        "isn't", "isnt", "aren't", "arent", "wasn't", "wasnt", "weren't", "werent",
        "hasn't", "hasnt", "haven't", "havent", "hadn't", "hadnt", "mustn't", "mustnt",
        "needn't", "neednt", "ain't", "aint",
    ]

    private static let people: Set<String> = [
        "i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself",
        "we", "us", "our", "ours",
        "i'm", "i've", "i'll", "i'd",
        "you're", "you've", "you'll", "you'd",
        "we're", "we've", "we'll", "we'd",
        "ich", "mich", "mir", "mein", "meine", "meinen", "meinem", "meiner", "meines",
        "du", "dich", "dir", "dein", "deine", "deinen", "deinem", "deiner", "deines",
        "wir", "uns", "unser", "unsere", "unseren", "unserem", "unserer", "unseres",
        "euch", "euer", "eure", "euren", "eurem", "eurer", "eures",
    ]

    private static let replyOpeners: Set<String> = [
        "yes", "yeah", "yep", "no", "nope", "sure", "okay", "ok", "certainly",
        "absolutely", "here", "here's", "sorry",
        "ja", "jawohl", "jep", "nein", "nee", "klar", "sicher", "gern", "gerne",
        "natürlich", "selbstverständlich", "hier", "entschuldigung",
    ]

    private static let preamblePhrases = [
        "here's the", "here is the", "cleaned transcript", "cleaned text",
        "hier ist der ", "hier ist die ", "hier ist das ", "hier ist dein",
        "bereinigte text", "bereinigter text", "bereinigte transkript", "bereinigtes transkript",
        "korrigierte text", "korrigierter text",
    ]

    static func rejection(original: String, cleaned: String) -> String? {
        let originalText = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalText.isEmpty, !cleanedText.isEmpty else {
            return "the cleaned text is empty"
        }

        guard cleanedText.count <= originalText.count * 3 / 2 + 16 else {
            return "the cleaned text is much longer than the transcript"
        }
        guard digits(in: originalText) == digits(in: cleanedText) else {
            return "a number changed"
        }

        let originalHeard = heardWords(in: originalText)
        let cleanedHeard = heardWords(in: cleanedText)
        guard !originalHeard.words.isEmpty, !cleanedHeard.words.isEmpty else {
            return "the cleaned text is empty"
        }

        guard negationCounts(in: originalText) == negationCounts(in: cleanedText) else {
            return "a negation was added or dropped"
        }

        let original = normalized(originalHeard)
        let originalWords = original.words
        let cleanedWords = normalized(cleanedHeard).words
        guard cleanedWords.count <= originalWords.count * 2 + 4 else {
            return "the cleaned text has many more words than the transcript"
        }

        let addedWords = addedWordCount(originalWords, cleanedWords)
        guard addedWords <= droppedWordCount(originalWords, cleanedWords),
              addedWords <= addedWordBudget(originalWords.count) else {
            return "the cleaned text added words the speaker did not say"
        }

        let originalPeople = personCounts(in: originalWords)
        let cleanedPeople = personCounts(in: cleanedWords)
        guard !cleanedPeople.contains(where: {
            $0.value > originalPeople[$0.key, default: 0]
        }) else {
            return "the cleaned text changed who is speaking"
        }

        let hearFix = hearBecameHere(originalWords, cleanedWords)
        if let cleanedOpener = replyOpener(in: cleanedWords),
           replyOpener(in: originalWords, skippingFillers: true) != cleanedOpener,
           !(cleanedOpener == "here" && hearFix) {
            return "the cleaned text starts with a reply"
        }

        guard !hasPreamble(original: originalText, cleaned: cleanedText, hearFix: hearFix) else {
            return "the cleaned text starts with a preamble"
        }

        let shared = sharedWordCount(originalWords, cleanedWords)
        guard Double(shared) / Double(cleanedWords.count) >= 0.5 else {
            return "the cleaned text is about something else"
        }
        if !(originalWords.count <= 6 && cleanedWords.count <= 3),
           Double(shared) / Double(originalWords.count) < 0.5,
           !(addedWords == 0 && keepsSelfCorrectionTail(original, cleanedWords)) {
            return "the cleaned text dropped most of the transcript"
        }
        return nil
    }

    static func isAcceptable(original: String, cleaned: String) -> Bool {
        rejection(original: original, cleaned: cleaned) == nil
    }

    private static func addedWordBudget(_ originalWords: Int) -> Int {
        max(2, originalWords / 4)
    }

    private static func normalized(_ heard: Words) -> Words {
        var result = Words()
        for (word, pause) in zip(heard.words, heard.pauseAfter) {
            let parts = expansion(of: word)
            result.words.append(contentsOf: parts)
            result.pauseAfter.append(contentsOf: Array(repeating: false, count: parts.count - 1) + [pause])
        }
        return result
    }

    private static func expansion(of word: String) -> [String] {
        if let parts = contractions[word] {
            return parts.flatMap(expansion(of:))
        }
        if word.hasSuffix("'s"), word.count > 2 {
            return [String(word.dropLast(2)), "es"]
        }
        return [word]
    }

    private static let contractions: [String: [String]] = [
        "i'm": ["i", "am"], "i've": ["i", "have"], "i'll": ["i", "will"], "i'd": ["i", "would"],
        "you're": ["you", "are"], "you've": ["you", "have"], "you'll": ["you", "will"], "you'd": ["you", "would"],
        "we're": ["we", "are"], "we've": ["we", "have"], "we'll": ["we", "will"], "we'd": ["we", "would"],
        "am": ["an", "dem"], "an'm": ["an", "dem"], "ans": ["an", "das"], "aufs": ["auf", "das"],
        "beim": ["bei", "dem"], "durchs": ["durch", "das"], "fürs": ["für", "das"],
        "hinterm": ["hinter", "dem"], "hinters": ["hinter", "das"], "im": ["in", "dem"], "ins": ["in", "das"],
        "überm": ["über", "dem"], "übers": ["über", "das"], "ums": ["um", "das"],
        "unterm": ["unter", "dem"], "unters": ["unter", "das"], "vom": ["von", "dem"],
        "vorm": ["vor", "dem"], "vors": ["vor", "das"], "zum": ["zu", "dem"], "zur": ["zu", "der"],
        "gibts": ["gibt", "es"], "gehts": ["geht", "es"], "kanns": ["kann", "es"], "hats": ["hat", "es"],
        "ists": ["ist", "es"], "wars": ["war", "es"], "habs": ["hab", "es"],
    ]

    private static func addedWordCount(_ original: [String], _ cleaned: [String]) -> Int {
        let originalSet = Set(original)
        return cleaned.filter { !originalSet.contains($0) }.count
    }

    private static func droppedWordCount(_ original: [String], _ cleaned: [String]) -> Int {
        let cleanedSet = Set(cleaned)
        return original.filter { !cleanedSet.contains($0) }.count
    }

    private static let selfCorrections: [[String]] = [
        ["no", "wait"],
        ["wait"],
        ["i", "mean"],
        ["actually"],
        ["scratch", "that"],
        ["sorry"],
        ["rather"],
    ]

    private static let germanSelfCorrections: [[String]] = [
        ["nein", "warte"],
        ["nein", "ich", "meine"],
        ["korrektur"],
    ]

    private static func keepsSelfCorrectionTail(_ heard: Words, _ cleaned: [String]) -> Bool {
        let original = heard.words
        var last: (end: Int, start: Int)?
        for start in original.indices {
            let setOff = germanSelfCorrections.filter {
                (start == 0 || heard.pauseAfter[start - 1])
                    && start + $0.count <= original.count && heard.pauseAfter[start + $0.count - 1]
            }
            for marker in selfCorrections + setOff where start + marker.count <= original.count {
                if original[start..<(start + marker.count)].elementsEqual(marker) {
                    let end = start + marker.count
                    if let current = last {
                        if end > current.end {
                            last = (end, start)
                        } else if end == current.end {
                            last = (end, min(current.start, start))
                        }
                    } else {
                        last = (end, start)
                    }
                }
            }
        }
        guard let last else { return false }
        let tail = Array(original[last.end...])
        guard !tail.isEmpty else { return false }
        for k in 0...last.start {
            guard last.start - k <= tail.count + 2 else { continue }
            guard cleaned.count == k + tail.count else { continue }
            if cleaned.prefix(k).elementsEqual(original.prefix(k)),
               cleaned.suffix(tail.count).elementsEqual(tail) {
                return true
            }
        }
        return false
    }

    private static func personCounts(in words: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for word in words where people.contains(word) {
            counts[word, default: 0] += 1
        }
        return counts
    }

    private static func replyOpener(in words: [String], skippingFillers: Bool = false) -> String? {
        var index = 0
        if skippingFillers {
            while index < words.count, fillers.contains(words[index]) {
                index += 1
            }
        }
        guard index < words.count else { return nil }
        let first = words[index]
        if first == "of", index + 1 < words.count, words[index + 1] == "course" {
            return "of course"
        }
        guard replyOpeners.contains(first) else { return nil }
        return first == "ok" ? "okay" : first
    }

    private static let fillers: Set<String> = [
        "um", "uh", "er", "ah", "so", "well", "like",
        "äh", "ähm", "öh", "hm", "hmm", "also", "na", "naja", "tja",
    ]

    private static func hearBecameHere(_ original: [String], _ cleaned: [String]) -> Bool {
        original.first == "hear"
            && original.count == cleaned.count
            && original.dropFirst() == cleaned.dropFirst()
    }

    private static func hasPreamble(original: String, cleaned: String, hearFix: Bool) -> Bool {
        let clause = firstClause(in: cleaned)
        if !hasRealColon(original), hasRealColon(String(clause)) {
            return true
        }
        let originalLowered = original.lowercased().replacingOccurrences(of: "’", with: "'")
        let cleanedLowered = cleaned.lowercased().replacingOccurrences(of: "’", with: "'")
        return preamblePhrases.contains {
            cleanedLowered.contains($0)
                && !originalLowered.contains($0)
                && !(hearFix && $0 == "here is the")
        }
    }

    private static func hasRealColon(_ text: String) -> Bool {
        let characters = Array(text)
        for index in characters.indices where characters[index] == ":" || characters[index] == "：" {
            let before: Character? = index > characters.startIndex ? characters[index - 1] : nil
            let after: Character? = index + 1 < characters.endIndex ? characters[index + 1] : nil
            if !(before?.isNumber == true && after?.isNumber == true) {
                return true
            }
        }
        return false
    }

    private static func firstClause(in text: String) -> Substring {
        if let end = text.firstIndex(where: { ".!?;\n\r\n。！？；".contains($0) }) {
            return text[..<end]
        }
        return text[...]
    }

    private static func digits(in text: String) -> [Character] {
        Array(text.filter(\.isNumber))
    }

    private struct Words {
        var words: [String] = []
        var pauseAfter: [Bool] = []
    }

    private static func words(in text: String) -> [String] {
        heardWords(in: text).words
    }

    private static func heardWords(in text: String) -> Words {
        var result = Words()
        var current = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "’" {
                if !current.isEmpty {
                    current.append("'")
                }
            } else {
                if !current.isEmpty {
                    result.words.append(trimTrailingApostrophes(current))
                    result.pauseAfter.append(false)
                    current = ""
                }
                if !character.isWhitespace, !result.pauseAfter.isEmpty {
                    result.pauseAfter[result.pauseAfter.count - 1] = true
                }
            }
        }
        if !current.isEmpty {
            result.words.append(trimTrailingApostrophes(current))
            result.pauseAfter.append(true)
        }
        return result
    }

    private static func trimTrailingApostrophes(_ word: String) -> String {
        var trimmed = word
        while trimmed.hasSuffix("'") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func negationCounts(in text: String) -> [String: Int] {
        let allWords = words(in: text)
        var counts: [String: Int] = [:]
        var index = 0
        while index < allWords.count {
            if allWords[index] == "no", index + 1 < allWords.count, allWords[index + 1] == "wait" {
                index += 2
                continue
            }
            if negations.contains(allWords[index]) {
                counts[allWords[index], default: 0] += 1
            }
            index += 1
        }
        return counts
    }

    private static func sharedWordCount(_ original: [String], _ cleaned: [String]) -> Int {
        var remaining: [String: Int] = [:]
        for word in original {
            remaining[word, default: 0] += 1
        }
        var shared = 0
        for word in cleaned {
            if let count = remaining[word], count > 0 {
                remaining[word] = count - 1
                shared += 1
            }
        }
        return shared
    }
}
