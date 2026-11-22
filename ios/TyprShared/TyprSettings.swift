import Foundation

/// An opt-in switch in Settings > Experimental for behavior that deviates from the default.
/// Always off by default. To add one: declare a static constant and list it in `all`.
struct ExperimentalSwitch: Hashable {
    let key: String
    let title: String
    let detail: String

    init(name: String, title: String, detail: String) {
        key = "typr.experimental.\(name)"
        self.title = title
        self.detail = detail
    }

    /// The switches shown in Settings > Experimental, in display order.
    static let all: [ExperimentalSwitch] = [.warmMicOnIPhone, .mixWithOtherAudio, .spokenPunctuation, .spaceTrackpad, .formatLists]

    /// Hex's warm session (anomalyco/hex #2179): idle on the iPhone's microphone, each dictation
    /// moves to the chosen one. Typr can't start input in the background, so a move there can
    /// end the warm session.
    static let warmMicOnIPhone = ExperimentalSwitch(
        name: "warmMicOnIPhone",
        title: "Warm mic on iPhone",
        detail: "Between dictations the warm mic uses the iPhone's; each dictation switches to the chosen microphone. Switching can end the warm session while Typr is in the background."
    )

    /// Hex's recording session (anomalyco/hex #2005, #2151, #2160): mixes with other apps'
    /// audio instead of interrupting it, and leaves the hardware at its own sample rate.
    static let mixWithOtherAudio = ExperimentalSwitch(
        name: "mixWithOtherAudio",
        title: "Keep other audio playing",
        detail: "Music and videos keep playing while you dictate, and the warm mic stays on while they play. Applies from the next dictation."
    )

    /// Hex's spoken punctuation (anomalyco/hex #2198, `SpokenPunctuation`), German and English.
    static let spokenPunctuation = ExperimentalSwitch(
        name: "spokenPunctuation",
        title: "Spoken punctuation",
        detail: "Say “Komma”, “Fragezeichen” or “Klammer auf” for the mark, in every style except Verbatim. Some commands stay words when they could be part of a noun phrase."
    )

    static let spaceTrackpad = ExperimentalSwitch(
        name: "spaceTrackpad",
        title: "Space bar trackpad like Apple's",
        detail: "Hold the space bar to move the cursor, also up and down through lines. Faster slides move it further."
    )

    /// Hex's Format lists (anomalyco/hex #2131, `SpokenLists`), German and English.
    static let formatLists = ExperimentalSwitch(
        name: "formatLists",
        title: "Format lists",
        detail: "Say “erstens … zweitens …”, “Punkt eins … Punkt zwei …”, “Spiegelstrich” or “neue Zeile” for numbered lines, bullets and line breaks, in every style except Verbatim. Some commands stay words when they could be part of a sentence."
    )
}

/// Typr switches, stored in the App Group so the keyboard reads them too.
/// Each switch documents its default. Dictation log deliberately retains saved history while off;
/// other switches keep upstream's behavior when off.
@MainActor
struct TyprSettings {
    private enum Key {
        static let aiCleanup = "typr.aiCleanup"
        static let cleanUpWhatISay = "typr.cleanUpWhatISay"
        static let dictationLog = "typr.dictationLog"
        static let autocorrectGerman = "typr.autocorrectGerman"
        static let autocorrectEnglish = "typr.autocorrectEnglish"
        static let autocorrectLanguageOrder = "typr.autocorrectLanguageOrder"
        static let hideSuggestionBar = "typr.hideSuggestionBar"
        static let personalLearning = "keyboard.personalLearning"
        static let dictationLanguage = "typr.dictationLanguage"
        static let preferredSpeechEngine = "typr.preferredSpeechEngine"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// Dictation cleanup. Off by default and retains the plain transcription path.
    var aiCleanup: Bool {
        get { defaults?.object(forKey: Key.aiCleanup) as? Bool ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.aiCleanup) }
    }

    /// "Clean up what I say": hesitations, stutters and explicit self-repairs removed by word
    /// rules before AI cleanup, skipped in Verbatim. On by default, like Hex.
    var cleanUpWhatISay: Bool {
        get { defaults?.object(forKey: Key.cleanUpWhatISay) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.cleanUpWhatISay) }
    }

    /// Collection only. Off interrupts pending log entries but deliberately keeps saved history.
    var dictationLog: Bool {
        get { defaults?.object(forKey: Key.dictationLog) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationLog) }
    }

    /// Quick feedback for this keyboard instance's newly inserted dictation. Off keeps existing UI.
    var dictationFeedbackStrip: Bool {
        get { defaults?.object(forKey: DictationFeedbackBridge.stripKey) as? Bool ?? false }
        nonmutating set { defaults?.set(newValue, forKey: DictationFeedbackBridge.stripKey) }
    }

    /// Independently selected autocorrect languages. Both default on.
    /// Retired experiment switches do not override the language selection.
    var autocorrectGerman: Bool {
        get { defaults?.object(forKey: Key.autocorrectGerman) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.autocorrectGerman) }
    }

    var autocorrectEnglish: Bool {
        get { defaults?.object(forKey: Key.autocorrectEnglish) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.autocorrectEnglish) }
    }

    /// Both autocorrect languages, preferred first; selected or not. Deutsch first by default;
    /// anything but exactly both languages falls back to the default.
    var autocorrectLanguageOrder: [SpatialWordDecoder.Language] {
        get {
            let stored = defaults?.stringArray(forKey: Key.autocorrectLanguageOrder) ?? []
            guard stored.sorted() == ["de", "en"] else { return [.german, .english] }
            return stored.compactMap(SpatialWordDecoder.Language.init(rawValue:))
        }
        nonmutating set { defaults?.set(newValue.map(\.rawValue), forKey: Key.autocorrectLanguageOrder) }
    }

    /// Learn local touch calibration and word counts. Explicit keep protection still works while off.
    var personalLearning: Bool {
        get { defaults?.object(forKey: Key.personalLearning) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.personalLearning) }
    }

    /// The dictation language (a picker, not a switch). Automatic, the default, keeps the
    /// previous speech-locale and cleanup-language behavior.
    var dictationLanguage: DictationLanguage {
        get { defaults?.string(forKey: Key.dictationLanguage).flatMap(DictationLanguage.init(rawValue:)) ?? .automatic }
        nonmutating set { defaults?.set(newValue.rawValue, forKey: Key.dictationLanguage) }
    }

    /// The speech engine the user explicitly chose (a picker, not a switch). nil, the default and
    /// any unknown stored value, keeps the original automatic choice (Apple Speech when available,
    /// else Parakeet V2). An explicit choice is never replaced by another engine.
    var preferredSpeechEngine: SpeechEngineChoice? {
        get { defaults?.string(forKey: Key.preferredSpeechEngine).flatMap(SpeechEngineChoice.init(rawValue:)) }
        nonmutating set {
            if let newValue {
                defaults?.set(newValue.rawValue, forKey: Key.preferredSpeechEngine)
            } else {
                defaults?.removeObject(forKey: Key.preferredSpeechEngine)
            }
        }
    }

    /// Read in the keyboard, written by Settings > Experimental.
    subscript(experiment experiment: ExperimentalSwitch) -> Bool {
        get { defaults?.bool(forKey: experiment.key) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: experiment.key) }
    }

    /// The full keyboard without its suggestion bar: the keys move up and the keyboard gets
    /// shorter. Autocorrect on space still applies. Off by default; the bar is shown.
    var hideSuggestionBar: Bool {
        get { defaults?.object(forKey: Key.hideSuggestionBar) as? Bool ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.hideSuggestionBar) }
    }
}
