import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Typr's German and English text rules, once part of Typr's own dictation styles: whether
/// Automatic text reads as English, and German abbreviations whose period ends no sentence.
nonisolated enum TyprTranscriptFormatter {
    private static let germanMarkers: Set<String> = [
        "der", "die", "das", "und", "ist", "nicht", "ich", "du", "wir", "ein", "eine", "einen",
        "zu", "mit", "auf", "für", "den", "dem", "des", "sich", "es", "auch", "noch", "dass",
        "wenn", "aber", "oder", "wie", "was", "bitte", "mal", "habe", "hab", "sind", "wird",
        "kann", "soll", "uhr", "nein", "ja", "danach", "dann", "schon", "hier", "mir", "dir",
        "uns", "von", "im", "bei", "nach", "über", "ob", "weil", "eigentlich", "vielleicht",
        "gut", "danke", "hallo", "jetzt", "heute", "morgen", "sehr", "kommt", "komme", "gibt", "geht",
        "muss", "mach", "machen",
    ]
    private static let englishMarkers: Set<String> = [
        "the", "and", "is", "are", "to", "of", "you", "it", "that", "this", "with", "for",
        "i", "i'm", "we", "they", "a", "an", "on", "at", "be", "was", "have", "not", "can",
        "will", "what", "please", "let's", "my", "your", "just", "do", "don't", "so",
        "good", "great", "sounds", "yeah", "yes", "thanks", "thank", "hello", "today", "tomorrow",
    ]

    /// Decides whether English filler words may be removed. English only when the text has no
    /// umlaut/ß and more English than German function words; a tie asks
    /// the on-device language recognizer. Mixed German with English terms stays German.
    static func readsAsEnglish(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains(where: { "äöüß".contains($0) }) { return false }
        var german = 0
        var english = 0
        for word in lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let key = word.replacingOccurrences(of: "’", with: "'")
            if germanMarkers.contains(key) { german += 1 }
            if englishMarkers.contains(key) { english += 1 }
        }
        if english != german { return english > german }
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .german]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english
        #else
        return false
        #endif
    }

    /// For Hex's formatter in German: whether the period at `index` closes a word of
    /// `abbreviations` or either part of a two-part one ("z. B.", "d. h."). No other single
    /// letter counts.
    static func endsGermanAbbreviation(_ chars: [Character], periodAt index: Int) -> Bool {
        func token(endingAt end: Int) -> (text: String, start: Int)? {
            var start = end
            while start > 0, chars[start - 1].isLetter || chars[start - 1] == "." { start -= 1 }
            guard start < end else { return nil }
            return (String(chars[start...end]), start)
        }
        guard index < chars.count, chars[index] == ".", let last = token(endingAt: index) else { return false }
        if abbreviations.contains(last.text.lowercased()) { return true }
        if last.start >= 2, chars[last.start - 1] == " ", let previous = token(endingAt: last.start - 2),
           previous.text.hasSuffix("."), abbreviations.contains((previous.text + last.text).lowercased()) {
            return true
        }
        let next = index + 2
        guard next < chars.count, chars[index + 1] == " " else { return false }
        var end = next
        while end < chars.count, chars[end].isLetter { end += 1 }
        guard end > next, end < chars.count, chars[end] == "." else { return false }
        return abbreviations.contains((last.text + String(chars[next...end])).lowercased())
    }

    /// Common German and English abbreviations whose period is not a sentence end,
    /// written without inner spaces and lowercased ("z. B." is checked as "z.b.").
    private static let abbreviations: Set<String> = [
        "bzw.", "ca.", "usw.", "etc.", "ggf.", "evtl.", "vgl.", "bspw.", "inkl.", "exkl.", "zzgl.",
        "sog.", "z.b.", "d.h.", "u.a.", "o.ä.", "u.u.", "z.t.", "z.zt.", "i.d.r.", "s.o.", "s.u.",
        "e.g.", "i.e.", "vs.", "approx.", "nr.", "dr.", "prof.", "mr.", "mrs.", "ms.", "st.",
    ]
}
