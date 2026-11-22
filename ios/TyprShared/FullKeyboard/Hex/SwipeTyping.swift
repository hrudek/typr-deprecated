import Foundation

// Hex's SwipeTyping.needsSpace only, which the engine reads; Hex's swipe decoder, state and trail view arrive with K6.
/// Settings › Keyboard › Swipe typing: slide from a letter through the letters of a word and lift,
/// and the word goes in, as with Apple's QuickPath and Gboard's glide typing. English and
/// Spanish layouts only (the languages with a typing model); every other layout keeps a drag
/// as a slide to another key.
///
/// A touch on a letter key becomes a swipe once it travels more than a key's pitch from
/// where it went down: the key no longer types, a light trail follows the finger, and the
/// strip shows what the path reads as so far. Lifting the finger types the best reading
/// (`FullKeyboardEngine.typeSwipedWord`, which spaces and capitalises it) and offers the
/// next three in the strip. Taps, holds for accents, and slides of a key or less keep
/// working as before, and so do delete, the space bar's trackpad, 123 and the Hex key, which
/// no swipe starts on.
@MainActor
final class SwipeTyping {
    // MARK: - Spacing

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
