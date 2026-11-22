import Foundation

/// Hex's automatic engine choice (Hex's `SpeechEngineChoice`, renamed: Typr's `SpeechEngineChoice`
/// is the user's persisted engine).
///
/// From iOS 26, Apple Speech takes every language it has, and English stays on Parakeet only
/// where Apple has no `SpeechTranscriber` (`appleSpeechPicks`). Before iOS 26 Parakeet dictates
/// English where it has room; everything else goes to Apple's on-device recognizer.
nonisolated struct HexSpeechEnginePolicy: Equatable, Sendable {
    /// The engines Hex's automatic choice can land on.
    enum Engine: Equatable, Sendable {
        /// Apple Speech (`SpeechAnalyzer`, iOS 26+): `SpeechTranscriber`, else `DictationTranscriber`.
        case appleSpeech
        /// FluidAudio Parakeet V2: English only.
        case parakeet
        /// Apple's `SFSpeechRecognizer` on the iPhone only, before iOS 26.
        case onDeviceRecognizer
    }

    /// What dictation uses: the engine the user chose in Typr, never substituted, or Hex's
    /// automatic choice when there is none.
    enum Selection: Equatable, Sendable {
        case chosen(SpeechEngineChoice)
        case automatic(Engine)
    }

    /// iOS's major version.
    var system: Int
    /// `ProcessInfo.physicalMemory`.
    var physicalMemory: UInt64
    /// `os_proc_available_memory()`: 0 where iOS sets no limit (the simulator).
    var availableMemory: UInt64
    /// A Parakeet load ended the app, or found too little memory.
    var parakeetSetAside: Bool

    /// 3 GB iPhones (iPhone XR, SE 2nd generation) report about 2.8 GB, 4 GB ones about 3.7 GB.
    static let smallMemory: UInt64 = 3 << 30
    /// What loading Parakeet takes (Hex's `ParakeetTranscriber.loadMemory`).
    static let parakeetLoadMemory: UInt64 = 1_400 << 20

    private var parakeetHasRoomToLoad: Bool {
        availableMemory == 0 || availableMemory >= Self.parakeetLoadMemory
    }

    /// Whether Parakeet can load here now, before iOS 26.
    var parakeetHasRoom: Bool {
        physicalMemory > Self.smallMemory && !parakeetSetAside && parakeetHasRoomToLoad
    }

    /// `language` is the dictation language (BCP 47), nil when unknown (English).
    /// `appleSpeechPicks` is iOS 26's answer: Apple Speech has the language.
    func engine(for language: String?, appleSpeechPicks: Bool) -> Engine {
        if system >= 26 {
            return appleSpeechPicks ? .appleSpeech : .parakeet
        }
        guard SpeechLanguagePicker.isEnglish(language), parakeetHasRoom else { return .onDeviceRecognizer }
        return .parakeet
    }

    func selection(chosen: SpeechEngineChoice?, language: String?, appleSpeechPicks: Bool) -> Selection {
        if let chosen { return .chosen(chosen) }
        return .automatic(engine(for: language, appleSpeechPicks: appleSpeechPicks))
    }

    /// Why English moved off Parakeet before iOS 26 because of Parakeet itself rather than the
    /// iPhone's size, for a notice.
    func notice(for language: String?) -> String? {
        guard system < 26, SpeechLanguagePicker.isEnglish(language), physicalMemory > Self.smallMemory,
              !parakeetHasRoom else { return nil }
        return "Not enough memory for the speech model. Typr is using Apple's on-device speech recognition."
    }
}
