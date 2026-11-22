import Foundation

// Only `TypingLearning`; the rest of Hex's file arrives with its journal.
/// What the keys learn from your corrections: typos you fix the same way, and
/// autocorrections you keep turning down.
nonisolated struct TypingLearning: Equatable, Sendable {
    static let minimumCount = 2

    /// Lowercased typo → the word you fixed it to, at least twice and only that way.
    var typos: [String: String] = [:]
    /// Lowercased words you kept as typed at least twice (undoing autocorrect with
    /// backspace, or tapping what you typed); autocorrect never rewrites them again.
    var rejected: Set<String> = []

    static func derive(from corrections: [TypingJournalCorrection]) -> TypingLearning {
        var rejections: [String: Int] = [:]
        for correction in corrections where correction.kind == .undone || correction.kind == .keptTyped {
            rejections[correction.final.lowercased(), default: 0] += 1
        }
        let rejected = Set(rejections.filter { $0.value >= minimumCount }.keys)

        // typo → lowercased word → (spelling, count)
        var fixes: [String: [String: (spelling: String, count: Int)]] = [:]
        for correction in corrections where correction.kind == .retyped || correction.kind == .picked {
            let typo = correction.typed.lowercased()
            let word = correction.final.lowercased()
            guard typo.count >= 2, isWord(typo), isWord(word), typo != word,
                  !word.hasPrefix(typo) // a completion, not a fix
            else { continue }
            var entry = fixes[typo, default: [:]][word] ?? (spelling: correction.final, count: 0)
            entry.count += 1
            // Prefer the spelling without a sentence-start capital.
            if correction.final == word { entry.spelling = word }
            fixes[typo, default: [:]][word] = entry
        }

        var typos: [String: String] = [:]
        for (typo, words) in fixes where words.count == 1 && !rejected.contains(typo) {
            guard let only = words.first, only.value.count >= minimumCount,
                  fixes[only.key]?[typo] == nil // you never fixed it the other way round
            else { continue }
            typos[typo] = only.value.spelling
        }
        return TypingLearning(typos: typos, rejected: rejected)
    }

    private static func isWord(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
    }
}
