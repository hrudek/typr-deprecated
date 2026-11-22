import UIKit

/// The user's keyboards, from `UITextInputMode.activeInputModes`, which a keyboard extension
/// sees in Settings › General › Keyboard › Keyboards order. A third-party keyboard is a
/// `UIKeyboardExtensionInputMode` and Apple's are `UIKeyboardInputMode`; Emoji's language is
/// `emoji`. `advanceToNextInputMode` skips Emoji when Apple's keyboard is on, in either order
/// (Hex, iOS 27.2 simulator).
enum TyprKeyboardInputModes {
    struct Mode: Equatable {
        var primaryLanguage: String?
        var className: String
    }

    @MainActor
    static func hasAppleKeyboard(_ modes: [UITextInputMode] = UITextInputMode.activeInputModes) -> Bool {
        hasAppleKeyboard(modes.map { Mode(primaryLanguage: $0.primaryLanguage, className: NSStringFromClass(type(of: $0))) })
    }

    /// Apple's own keyboard for a language: not Emoji or dictation, and not an extension.
    static func hasAppleKeyboard(_ modes: [Mode]) -> Bool {
        modes.contains { mode in
            !["emoji", "dictation"].contains(mode.primaryLanguage) && !mode.className.contains("Extension")
        }
    }

    /// Only Apple's keyboard receives a code from Messages or Mail; a third-party keyboard gets
    /// nothing, not even the system's suggestion above it. Without Apple's keyboard the next one
    /// is Emoji or another third-party keyboard, so the chip would do nothing.
    /// `hasAppleKeyboard` is asked only in a one-time-code field.
    static func offersCodeFromMessages(textContentType: UITextContentType?, hasAppleKeyboard: () -> Bool) -> Bool {
        textContentType == .oneTimeCode && hasAppleKeyboard()
    }
}
