import Foundation

@MainActor
final class SwipeTyping {
    /// Whether a swiped word needs a space before it, as Apple's keyboard adds one: unless
    /// the text before the cursor is empty or ends in a space, a line break or opening
    /// punctuation (a bracket, an opening quote, ¿ or ¡, or a mark that starts a word such
    /// as @ # /). A straight quote opens when nothing or a space comes before it.
    static func needsSpace(before: String?) -> Bool {
        guard let before, let last = before.last else { return false }
        if last.isWhitespace || last.isNewline || opening.contains(last) { return false }
        if last == "\"" || last == "'" {
            let previous = before.dropLast().last
            return !(previous == nil || previous!.isWhitespace || previous!.isNewline || opening.contains(previous!))
        }
        return true
    }

    private static let opening: Set<Character> = ["(", "[", "{", "<", "«", "‹", "“", "‘", "„", "¿", "¡", "@", "#", "/"]
}
