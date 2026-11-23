import Foundation

/// Experimental › Hex experiments › Two-language dictation (anomalyco/hex #2348), in the shared
/// App Group so in-keyboard dictation reads it too. Off by default. While it is on, Apple
/// Speech reads one recording in the language dictation resolved and in the other of German
/// and English when its model is already installed, and keeps the more confident reading for
/// each phrase (`AppleSpeechTwoLanguage`, `TwoLanguageMerger`).
nonisolated struct TwoLanguageDictationSettings {
    static let enabledKey = ExperimentalSwitch.twoLanguageDictation.key

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults?.bool(forKey: Self.enabledKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.enabledKey) }
    }
}
