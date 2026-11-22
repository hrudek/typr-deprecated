import Foundation

/// Experimental › Hex experiments › Multilingual model (Parakeet) (anomalyco/hex #2197), in the
/// shared App Group so the keyboard reads it too. Off by default. While it's on, no engine is
/// chosen and Typr has the model ready, Typr dictates its 25 languages with Parakeet Ultra
/// (`ParakeetUltraTranscriber`), which hears them mixed within a sentence (German with English
/// words), and the keyboard hands its dictations to Typr: the model can't load within a
/// keyboard's memory limit. Until it's ready, both dictate as they would with the experiment off.
nonisolated struct MultilingualParakeetSettings {
    static let enabledKey = ExperimentalSwitch.multilingualParakeet.key
    /// Set by Typr once Parakeet Ultra loaded; cleared while it's missing, set aside or off.
    static let modelReadyKey = "\(enabledKey).ready"

    /// Parakeet Ultra's languages (ISO 639-1), those of NVIDIA Parakeet TDT 0.6B v3.
    static let languages: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it",
        "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk",
    ]

    /// As Parakeet V2: 6 GB iPhones report about 5.5 GB, 4 GB ones (iPhone 12, 13) under 4 GB.
    static let minimumPhysicalMemory: UInt64 = 5 << 30

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults?.bool(forKey: Self.enabledKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.enabledKey) }
    }

    /// Turned off by the person, as stored: never set reads false here, and so does an App
    /// Group iOS doesn't let Typr read yet (a launch before the iPhone's first unlock), which
    /// must not delete a model that is on.
    var isTurnedOff: Bool {
        defaults?.object(forKey: Self.enabledKey) as? Bool == false
    }

    /// Whether Typr has Parakeet Ultra loaded at least once since it last downloaded or was let
    /// back in: until then, the keyboard dictates as it would with the experiment off.
    var isModelReady: Bool {
        get { defaults?.bool(forKey: Self.modelReadyKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.modelReadyKey) }
    }

    /// Keyboard dictation opens Typr when Ultra is ready for the automatic engine and language.
    func keyboardOpensTypr(language: String?) -> Bool {
        isEnabled && isModelReady && language != nil
            && TyprSettings(defaults: defaults).preferredSpeechEngine == nil
    }

    /// Whether this iPhone has the memory to load it at all.
    static func fits(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Bool {
        physicalMemory >= minimumPhysicalMemory
    }

    static func supports(_ language: String?) -> Bool {
        guard let language, let code = Locale(identifier: language).language.languageCode?.identifier else {
            return false
        }
        return languages.contains(code)
    }

    /// The language (BCP 47) Parakeet Ultra dictates in, or nil while it doesn't dictate: the
    /// experiment off, an iPhone without the memory, or a language it doesn't know, which
    /// stays with the engine Typr uses without it. The one set, else the iPhone's first
    /// language (`DictationController.wantedLanguage`; Hex also follows the keyboard's
    /// language here, Typr does from the language-follow cutover).
    func language(
        set: String? = LanguageSettings().explicitDictationLanguage(typr: TyprSettings().dictationLanguage),
        preferred: [String] = Locale.preferredLanguages,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> String? {
        guard isEnabled, Self.fits(physicalMemory: physicalMemory) else { return nil }
        guard let wanted = set ?? preferred.first else { return nil }
        return Self.supports(wanted) ? wanted : nil
    }
}
