import CoreGraphics
import Foundation

// Hex's settings, key stats and corrections; the journal itself arrives with Hex's journal.

/// Learn how I type (on by default): a private, on-device record of how you type and dictate,
/// kept in the App Group so the app can show it and the keyboard can personalize itself.
///
/// It is deliberately not a keystroke log or a copy of what you write. Taps are folded into
/// per-key averages (where your finger lands relative to each key), so no sequence of letters
/// is ever stored, and corrections are word-level pairs: a word you erased and retyped,
/// autocorrect fixes, fixes you undid, suggestions you picked, and words you fixed in a
/// dictation, with at most a word of context on each side. Nothing leaves the iPhone.
struct TypingJournalSettings {
    private enum Key {
        static let enabled = "experiments.typingJournal"
        static let learnsPerLanguage = "experiments.learnPerLanguage"
        static let disabledDictationFixes = "typingJournal.disabledDictationFixes"
        static let erasedAt = "typingJournal.erasedAt"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// Learn how I type: on until you turn it off. Only a switch you turned off is saved as
    /// off, so an iPhone that never touched it learns.
    var isEnabled: Bool {
        get { defaults.map { $0.object(forKey: Key.enabled) as? Bool ?? true } ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.enabled) }
    }

    /// Experiment (Learn each language separately): learned words and fixes stay with the
    /// language you typed or dictated them in. Off by default, like every experiment: one
    /// shared list and one shared learning, exactly as before.
    var learnsPerLanguage: Bool {
        get { defaults?.bool(forKey: Key.learnsPerLanguage) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.learnsPerLanguage) }
    }

    /// Learned dictation fixes you switched off in Typing insights (their ids).
    var disabledDictationFixes: Set<String> {
        get { Set(defaults?.stringArray(forKey: Key.disabledDictationFixes) ?? []) }
        nonmutating set { defaults?.set(newValue.sorted(), forKey: Key.disabledDictationFixes) }
    }

    /// The words autocorrect learned to leave alone (`LearnedWordsStore`), the shared list
    /// and every language's own.
    func eraseLearnedWords() {
        guard let defaults else { return }
        defaults.removeObject(forKey: LearnedWordsStore.defaultsKey)
        for key in defaults.dictionaryRepresentation().keys where LearnedWordsStore.isScopedKey(key) {
            defaults.removeObject(forKey: key)
        }
    }

    /// When Delete what Hex learned last ran, so another process drops what it still holds.
    var erasedAt: TimeInterval {
        get { defaults?.double(forKey: Key.erasedAt) ?? 0 }
        nonmutating set { defaults?.set(newValue, forKey: Key.erasedAt) }
    }
}

nonisolated struct TypingJournalKeyStats: Codable, Equatable, Sendable {
    var count = 0
    /// Sums of the tap's offset from the keycap centre, in keycap widths and heights.
    var dx = 0.0
    var dy = 0.0

    var meanOffset: CGVector { count == 0 ? .zero : CGVector(dx: dx / Double(count), dy: dy / Double(count)) }
}

nonisolated struct TypingJournalCorrection: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// You erased a word and typed another.
        case retyped
        /// Autocorrect replaced it on space.
        case autocorrected
        /// You undid autocorrect with one backspace.
        case undone
        /// You tapped a suggestion.
        case picked
        /// You tapped what you typed instead of the autocorrection space would apply.
        case keptTyped
    }

    var kind: Kind
    var typed: String
    var final: String
    var at: TimeInterval
    /// The keyboard language it was typed in (`KeyboardLanguage.rawValue`); nil for a
    /// journal written before corrections carried one. It marks the language either way
    /// (`Learn each language separately`).
    var language: String? = nil
}
