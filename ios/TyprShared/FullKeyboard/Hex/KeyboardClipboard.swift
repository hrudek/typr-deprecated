import UIKit

/// Inspect clipboard metadata when offering Paste and read contents only after a tap.
enum KeyboardClipboardOffer: Equatable {
    case paste
    case code(canPaste: Bool)
    case dictation
}

enum KeyboardInputModes {
    struct Mode: Equatable {
        var primaryLanguage: String?
        var className: String
    }

    @MainActor
    static func hasAppleKeyboard(_ modes: [UITextInputMode] = UITextInputMode.activeInputModes) -> Bool {
        hasAppleKeyboard(modes.map { Mode(primaryLanguage: $0.primaryLanguage, className: NSStringFromClass(type(of: $0))) })
    }

    static func hasAppleKeyboard(_ modes: [Mode]) -> Bool {
        modes.contains { mode in
            !["emoji", "dictation"].contains(mode.primaryLanguage) && !mode.className.contains("Extension")
        }
    }
}

@MainActor
struct KeyboardClipboardTracker {
    static let freshness: TimeInterval = 3 * 60

    static let askedReadDuration: TimeInterval = 0.3
    static let allowPasteHintLimit = 3

    static var allowPasteHint: String {
        String(localized: "Settings › Apps › Typr › Paste from Other Apps › Allow")
    }

    static var allowPasteHintAnnouncement: String {
        String(localized: "To paste without being asked, go to Settings, Apps, Typr, Paste from Other Apps, and choose Allow.")
    }

    private enum Key {
        static let seenChange = "keyboard.clipboard.seenChange"
        static let seenAt = "keyboard.clipboard.seenAt"
        static let usedChange = "keyboard.clipboard.usedChange"
        static let allowPasteHints = "keyboard.clipboard.allowPasteHints"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    func offer(
        textContentType: UITextContentType?,
        keyboardType: UIKeyboardType?,
        autocorrectionType: UITextAutocorrectionType?,
        fieldIsEmpty: Bool,
        hasFullAccess: Bool,
        canSwitchKeyboard: Bool = true,
        hasAppleKeyboard: () -> Bool = { KeyboardInputModes.hasAppleKeyboard() },
        pasteboard: UIPasteboard = .general,
        now: Date = Date()
    ) -> KeyboardClipboardOffer? {
        guard hasFullAccess, fieldIsEmpty else { return nil }
        let fresh = hasFreshCopy(pasteboard: pasteboard, now: now)
        if canSwitchKeyboard,
           Self.expectsCode(textContentType: textContentType, keyboardType: keyboardType, autocorrectionType: autocorrectionType),
           hasAppleKeyboard() {
            return .code(canPaste: fresh)
        }
        return fresh ? .paste : nil
    }

    // Some chat boxes use .oneTimeCode with default autocorrection and a letter keyboard.
    static func expectsCode(
        textContentType: UITextContentType?,
        keyboardType: UIKeyboardType?,
        autocorrectionType: UITextAutocorrectionType?
    ) -> Bool {
        guard textContentType == .oneTimeCode else { return false }
        switch keyboardType {
        case .numberPad, .asciiCapableNumberPad, .decimalPad, .phonePad, .numbersAndPunctuation: return true
        default: return autocorrectionType == .yes || autocorrectionType == .no
        }
    }

    // Reading both string and URL can prompt twice for a link.
    static func read(_ pasteboard: UIPasteboard = .general) -> String? {
        if pasteboard.hasStrings { return pasteboard.string }
        if pasteboard.hasURLs { return pasteboard.url?.absoluteString }
        return nil
    }

    func shouldPointToAllowPaste(readDuration: TimeInterval, refused: Bool) -> Bool {
        if refused { return true }
        guard readDuration >= Self.askedReadDuration else { return false }
        let shown = defaults?.integer(forKey: Key.allowPasteHints) ?? 0
        guard shown < Self.allowPasteHintLimit else { return false }
        defaults?.set(shown + 1, forKey: Key.allowPasteHints)
        return true
    }

    func markPasted(pasteboard: UIPasteboard = .general) {
        defaults?.set(pasteboard.changeCount, forKey: Key.usedChange)
    }

    private func hasFreshCopy(pasteboard: UIPasteboard, now: Date) -> Bool {
        guard pasteboard.hasStrings || pasteboard.hasURLs else { return false }
        let change = pasteboard.changeCount
        guard let defaults else { return true }
        guard (defaults.object(forKey: Key.usedChange) as? Int) != change else { return false }
        if (defaults.object(forKey: Key.seenChange) as? Int) != change {
            defaults.set(change, forKey: Key.seenChange)
            defaults.set(now.timeIntervalSince1970, forKey: Key.seenAt)
            return true
        }
        return now.timeIntervalSince1970 - defaults.double(forKey: Key.seenAt) < Self.freshness
    }
}
