import Foundation
import Speech

/// Hex's automatic engine choice (Hex's `DictationController+Engine`), used when no engine is
/// chosen in Typr (`SpeechEngineProviding.automaticTranscriber`). A chosen engine never comes
/// through here. Parakeet Ultra (Hex's multilingual experiment) is not part of it yet.
extension DictationController {
    // MARK: - Which engine dictates (`HexSpeechEnginePolicy`)

    /// The language dictation is meant to be in: the one picked by hand
    /// (`LanguageSettings.explicitDictationLanguage`), else the iPhone's.
    nonisolated static func wantedLanguage(explicit: String?) -> String? {
        explicit ?? Locale.preferredLanguages.first
    }

    /// Hex's `defaultTranscriber`: from iOS 26 Apple Speech where it has the language (English
    /// stays on Parakeet V2 only where `AppleSpeechTranscriber.shouldUse` says so), before it
    /// Parakeet V2 for English where it has room, else Apple's on-device recognizer.
    /// `strict`: Typr strict dictation language.
    static func defaultTranscriber(
        language: DictationLanguage,
        settings: LanguageSettings = LanguageSettings(),
        policy: HexSpeechEnginePolicy = .current,
        strict: Bool = TyprSettings()[experiment: .typrStrictDictationLanguage]
    ) async -> any LocalTranscribing {
        let explicit = settings.explicitDictationLanguage(typr: language)
        guard #available(iOS 26.0, *) else {
            return transcriberBeforeAppleSpeech(policy: policy, explicit: explicit, strict: strict)
        }
        if let speech = await appleSpeechLanguage(
            picked: AppleSpeechTranscriber.preferredLanguage(explicit: explicit, strict: strict),
            wanted: wantedLanguage(explicit: explicit),
            parakeetFits: policy.parakeetFitsBesideAppleSpeech
        ) {
            return AppleSpeechTranscriber(language: speech, automatic: explicit == nil)
        }
        return ParakeetTranscriber()
    }

    /// Before iOS 26: Parakeet or the on-device recognizer (`HexSpeechEnginePolicy`), in the
    /// language the recognizer has on this iPhone, else the one wanted, which then says it
    /// isn't available here.
    nonisolated static func transcriberBeforeAppleSpeech(
        policy: HexSpeechEnginePolicy,
        explicit: String?,
        strict: Bool = false,
        suite: String = KeyboardBridge.appGroup,
        access: SpeechRecognitionAccess = .system,
        resolve: (String?, Bool, LanguageSettings) -> String? = {
            OnDeviceSpeechLanguages.resolve(explicit: $0, strict: $1, settings: $2)
        }
    ) -> any LocalTranscribing {
        let settings = LanguageSettings(defaults: UserDefaults(suiteName: suite))
        let wanted = wantedLanguage(explicit: explicit)
        guard policy.engine(for: wanted, appleSpeechPicks: false) == .onDeviceRecognizer else {
            return ParakeetTranscriber()
        }
        let language = resolve(explicit, strict, settings) ?? wanted ?? "en-US"
        return OnDeviceSpeechTranscriber(language: language, automatic: explicit == nil, access: access, suite: suite)
    }

    /// The language Apple Speech dictates in, or nil for Parakeet V2, which knows only
    /// English: Apple Speech's pick, unless it is English that Parakeet takes
    /// (`AppleSpeechTranscriber.shouldUse`). With no pick (Speech not answering), English goes
    /// to Parakeet only on an iPhone without `SpeechTranscriber`, and any other language
    /// (`wanted`) stays on Apple Speech, which says it can't dictate it rather than Parakeet
    /// hearing Spanish as English words.
    @available(iOS 26.0, *)
    nonisolated static func appleSpeechLanguage(
        picked: SpeechLanguage?,
        wanted: String?,
        parakeetFits: Bool = ParakeetTranscriber.fitsInMemory,
        hasSpeechTranscriber: Bool = SpeechTranscriber.isAvailable,
        appleSetAside: Bool? = nil
    ) -> SpeechLanguage? {
        if let picked {
            return AppleSpeechTranscriber.shouldUse(
                picked,
                parakeetFits: parakeetFits,
                hasSpeechTranscriber: hasSpeechTranscriber,
                appleSetAside: appleSetAside
            ) ? picked : nil
        }
        guard let wanted else { return nil }
        if SpeechLanguagePicker.isEnglish(wanted) {
            let english = SpeechLanguage(locale: Locale(identifier: wanted), module: .speech)
            let setAside = appleSetAside ?? LanguageSettings().isUnavailable(english.identifier)
            guard hasSpeechTranscriber, !setAside else { return nil }
            return english
        }
        return SpeechLanguage(locale: Locale(identifier: wanted), module: .dictation)
    }
}
