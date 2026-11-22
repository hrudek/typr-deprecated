import UIKit

/// The return key for the field's `returnKeyType`, as Apple's keyboard draws it (Hex #2200, seen on
/// iOS 27.2 in fields of every type): a symbol on the blue key for the types that act (send ↑, go,
/// join and route →, search 🔍, done ✓, emergency call 📞) and on a plain key for return ↵, next
/// and continue ›. Apple shows no text on the key, so only the accessibility label is words.
/// Both the full keyboard and the dictation bar draw it.
nonisolated struct TyprReturnKeyStyle: Equatable, Sendable {
    let symbol: String
    let isAction: Bool
    let accessibilityLabel: String

    init(_ type: UIReturnKeyType?) {
        switch type ?? .default {
        case .send: (symbol, isAction, accessibilityLabel) = ("arrow.up", true, "Send")
        case .go: (symbol, isAction, accessibilityLabel) = ("arrow.right", true, "Go")
        case .join: (symbol, isAction, accessibilityLabel) = ("arrow.right", true, "Join")
        case .route: (symbol, isAction, accessibilityLabel) = ("arrow.right", true, "Route")
        case .google, .yahoo, .search: (symbol, isAction, accessibilityLabel) = ("magnifyingglass", true, "Search")
        case .done: (symbol, isAction, accessibilityLabel) = ("checkmark", true, "Done")
        case .emergencyCall: (symbol, isAction, accessibilityLabel) = ("phone", true, "Emergency call")
        case .next: (symbol, isAction, accessibilityLabel) = ("chevron.right", false, "Next")
        case .continue: (symbol, isAction, accessibilityLabel) = ("chevron.right", false, "Continue")
        default: (symbol, isAction, accessibilityLabel) = ("return", false, "Return")
        }
    }

    /// Off while the field is empty when it asks for that (`enablesReturnKeyAutomatically`):
    /// the key turns grey with a faint glyph and a tap does nothing.
    static func isEnabled(automatically: Bool?, hasText: Bool) -> Bool {
        !(automatically == true && !hasText)
    }
}
