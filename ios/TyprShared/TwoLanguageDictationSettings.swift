import Foundation

/// Experimental › Hex experiments › Two-language dictation (anomalyco/hex #2348). Off by
/// default. Only app dictation reads it; in-keyboard dictation keeps one recognizer.
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
