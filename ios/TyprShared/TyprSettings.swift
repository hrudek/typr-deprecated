import Foundation

/// An opt-in switch in Settings > Experimental for behavior that deviates from the default.
/// Always off by default. To add one: declare a static constant and list it in `all`.
nonisolated struct ExperimentalSwitch: Hashable {
    let key: String
    let title: String
    let detail: String

    init(name: String, title: String, detail: String) {
        key = "typr.experimental.\(name)"
        self.title = title
        self.detail = detail
    }

    /// Settings > Experimental › Hex experiments: Hex's own experiments, with Hex's names and
    /// defaults. Each is listed once its implementation works.
    static let hexExperiments: [ExperimentalSwitch] = [.appleIntelligenceCleanup]

    /// Settings > Experimental › Typr variants: where Typr behaves differently from Hex, in
    /// display order. Each is listed once its implementation works.
    static let typrVariants: [ExperimentalSwitch] = [.typrExclusiveAudioSession, .typrKeepSelectedWarmMicrophone, .typrAudioActivationRetries, .typrStrictDictationLanguage, .typrGermanFormattingRules, .spokenPunctuation, .spaceTrackpad, .formatLists, .cleanUpWhatISay, .deleteSlide, .learnFromEdits, .wordsFromContext, .keyboardDictation, .learnEachLanguage]

    /// Every switch shown in Settings > Experimental.
    static let all = hexExperiments + typrVariants

    static let appleIntelligenceCleanup = ExperimentalSwitch(
        name: "appleIntelligenceCleanup",
        title: "Clean up with Apple Intelligence",
        detail: "Uses on-device Apple Intelligence instead of the AI cleanup engine in the Typr app. Requires iOS 26 and skips Verbatim."
    )

    static let typrExclusiveAudioSession = ExperimentalSwitch(
        name: "variant.exclusiveAudioSession",
        title: "Typr exclusive audio session",
        detail: "Dictation pauses other audio and records at 16 kHz, and the warm mic stays off while other audio plays, as Typr did before Hex."
    )

    static let typrKeepSelectedWarmMicrophone = ExperimentalSwitch(
        name: "variant.keepSelectedWarmMicrophone",
        title: "Typr keep selected warm microphone",
        detail: "Between dictations the warm mic stays on the chosen microphone instead of the iPhone's."
    )

    static let typrAudioActivationRetries = ExperimentalSwitch(
        name: "variant.audioActivationRetries",
        title: "Typr audio activation retries",
        detail: "When another app still holds audio, Typr tries again for about five seconds before dictation fails."
    )

    static let typrFixedDictationLanguage = ExperimentalSwitch(
        name: "variant.fixedDictationLanguage",
        title: "Typr fixed dictation language",
        detail: "Dictation uses Typr's Automatic, German or English choice instead of following the keyboard and iPhone languages."
    )

    static let typrStrictDictationLanguage = ExperimentalSwitch(
        name: "variant.strictDictationLanguage",
        title: "Typr strict dictation language",
        detail: "German or English chosen as the dictation language never falls back to another language when Apple's speech recognition doesn't have it."
    )

    static let typrGermanFormattingRules = ExperimentalSwitch(
        name: "variant.germanFormattingRules",
        title: "Typr German formatting rules",
        detail: "Lists and spoken punctuation follow Typr's German and English rules instead of Hex's, switched by Format lists and Spoken punctuation below instead of the Style settings."
    )

    static let typrConservativeSpokenCleanup = ExperimentalSwitch(
        name: "variant.conservativeSpokenCleanup",
        title: "Typr conservative spoken cleanup",
        detail: "Clean up what I say uses Typr's German and English word rules instead of Hex's."
    )

    static let typrAICleanupPipeline = ExperimentalSwitch(
        name: "variant.aiCleanupPipeline",
        title: "Typr AI cleanup pipeline",
        detail: "AI cleanup uses Typr's prompt, rewrites and guard, and the Anthropic provider when it is chosen."
    )

    static let typrVocabularyMatching = ExperimentalSwitch(
        name: "variant.vocabularyMatching",
        title: "Typr vocabulary matching",
        detail: "Your words are matched with Typr's spelling rules instead of Hex's."
    )

    static let typrDictationEditLearning = ExperimentalSwitch(
        name: "variant.dictationEditLearning",
        title: "Typr dictation edit learning",
        detail: "Learning from your edits uses Typr's rules and storage instead of Hex's."
    )

    static let typrTranslationPolicy = ExperimentalSwitch(
        name: "variant.translationPolicy",
        title: "Typr translation policy",
        detail: "Translate what I say only between German and English, with Typr's five-second limit."
    )

    static let typrAlwaysDictateInApp = ExperimentalSwitch(
        name: "variant.alwaysDictateInApp",
        title: "Typr always dictate in app",
        detail: "The Typr key always dictates in the Typr app, never in the keyboard."
    )

    static let typrAutomaticHostReturn = ExperimentalSwitch(
        name: "variant.automaticHostReturn",
        title: "Typr automatic host return",
        detail: "After dictating in the Typr app, Typr goes back to the app you came from."
    )

    /// Typr overrides of Hex defaults: off is Hex's behavior, on restores Typr's. Each joins
    /// `typrVariants` when its area switches to Hex.
    static let typrOverrides: [ExperimentalSwitch] = [
        .typrExclusiveAudioSession, .typrKeepSelectedWarmMicrophone, .typrAudioActivationRetries,
        .typrStrictDictationLanguage, .typrFixedDictationLanguage, .typrGermanFormattingRules, .typrConservativeSpokenCleanup,
        .typrAICleanupPipeline, .typrVocabularyMatching, .typrDictationEditLearning, .typrTranslationPolicy,
        .typrAlwaysDictateInApp, .typrAutomaticHostReturn,
    ]

    /// Retired: Hex's warm session (anomalyco/hex #2179) is the default since its audio cutover;
    /// Typr keep selected warm microphone restores the old behavior. Kept for its stored key
    /// only, which nothing reads, so a stored value never changes the default or an override.
    static let warmMicOnIPhone = ExperimentalSwitch(
        name: "warmMicOnIPhone",
        title: "Warm mic on iPhone",
        detail: "Between dictations the warm mic uses the iPhone's; each dictation switches to the chosen microphone. Switching can end the warm session while Typr is in the background."
    )

    /// Retired: Hex's recording session (anomalyco/hex #2005, #2151, #2160) is the default since
    /// its audio cutover; Typr exclusive audio session restores the old behavior. Kept for its
    /// stored key only, which nothing reads, so a stored value never changes the default or an
    /// override.
    static let mixWithOtherAudio = ExperimentalSwitch(
        name: "mixWithOtherAudio",
        title: "Keep other audio playing",
        detail: "Music and videos keep playing while you dictate, and the warm mic stays on while they play. Applies from the next dictation."
    )

    /// Typr's spoken punctuation (`TyprSpokenPunctuation`), German and English. Compatibility
    /// only: read while Typr German formatting rules is on; otherwise Style › Spoken punctuation.
    static let spokenPunctuation = ExperimentalSwitch(
        name: "spokenPunctuation",
        title: "Spoken punctuation",
        detail: "With Typr German formatting rules: say “Komma”, “Fragezeichen” or “Klammer auf” for the mark, in every style except Verbatim. Some commands stay words when they could be part of a noun phrase."
    )

    static let spaceTrackpad = ExperimentalSwitch(
        name: "spaceTrackpad",
        title: "Space bar trackpad like Apple's",
        detail: "Hold the space bar to move the cursor, also up and down through lines. Faster slides move it further."
    )

    /// Typr's Format lists (`TyprSpokenLists`), German and English. Compatibility only: read
    /// while Typr German formatting rules is on; otherwise Style › Format lists.
    static let formatLists = ExperimentalSwitch(
        name: "formatLists",
        title: "Format lists",
        detail: "With Typr German formatting rules: say “erstens … zweitens …”, “Punkt eins … Punkt zwei …”, “Spiegelstrich” or “neue Zeile” for numbered lines, bullets and line breaks, in every style except Verbatim. Some commands stay words when they could be part of a sentence."
    )

    /// Hex's "Clean up what I say" (anomalyco/hex #2023, #2132) as German and English word rules
    /// (`SpokenCleanup`), before AI cleanup.
    static let cleanUpWhatISay = ExperimentalSwitch(
        name: "cleanUpWhatISay",
        title: "Clean up what I say",
        detail: "Removes “äh” and “um”, doubled words like “und und” and corrections like “Dienstag, ich meine, Mittwoch”, in every style except Verbatim. Anything less certain stays as said."
    )

    /// Hex's delete slide (anomalyco/hex #2080, #2257), without Hex's hold-to-repeat: on, a held
    /// delete key deletes only by sliding. Off, delete repeats while held, as before.
    static let deleteSlide = ExperimentalSwitch(
        name: "deleteSlide",
        title: "Slide delete to remove words",
        detail: "Press delete and slide left: each key width removes one more word. Slide back to bring words back; lift to keep the rest deleted. Holding delete without sliding removes only one letter."
    )

    /// Hex's learning from dictation edits (anomalyco/hex #2022, `DictationEditTracker`).
    static let learnFromEdits = ExperimentalSwitch(
        name: "learnFromEdits",
        title: "Learn from my edits",
        detail: "For a minute after a dictation, Typr's keyboard notes words you replace with similar ones, like “Wal” with “Wahl”. Fixed the same way twice, Typr writes it that way in later dictations. Needs Full Access; manage them in AI & vocabulary."
    )

    /// Hex's context words (anomalyco/hex #2144): its/it's, your/you're, there/their/they're,
    /// then/than and words missing an apostrophe follow the words around them, at their own
    /// space or the next word's; German gets geht's and gibt's.
    static let wordsFromContext = ExperimentalSwitch(
        name: "wordsFromContext",
        title: "Words from context",
        detail: "Autocorrect picks its or it's, your or you're, then or than by the words around them, and writes geht's and gibt's with an apostrophe."
    )

    /// Hex's in-keyboard dictation (anomalyco/hex #1999, #2089, #2045): off, the Typr app dictates.
    static let keyboardDictation = ExperimentalSwitch(
        name: "keyboardDictationAppleSpeech",
        title: "Keyboard dictation: Apple Speech in the keyboard",
        detail: "Off: the Typr key dictates in the Typr app with your selected engine, such as Orukeet. On: without a warm mic, the keyboard records itself and transcribes with Apple Speech, not Orukeet, without opening Typr. A warm mic still uses your selected engine. Needs iOS 26; Typr opens as before when memory, the microphone or Apple Speech's language isn't available."
    )

    /// Hex's per-language learning (anomalyco/hex #2188): learned words carry the language of the
    /// sentence they were typed in, whether this is on or not.
    static let learnEachLanguage = ExperimentalSwitch(
        name: "learnEachLanguage",
        title: "Learn each language separately",
        detail: "Words Typr learned from your typing in English are not suggested in a German sentence, and the other way round. Words typed in both languages stay in both."
    )
}

/// Why the last dictation went in as spoken while Translate what I say was on.
nonisolated enum TranslationFailure: String, Sendable {
    /// Apple's German or English pack is not on the iPhone.
    case notDownloaded
    /// Translating failed twice or took too long.
    case failed

    /// What the keyboard says after pasting as spoken.
    var note: String {
        switch self {
        case .notDownloaded: "Pasted as spoken: download the languages in Typr"
        case .failed: "Couldn't translate, pasted as spoken"
        }
    }
}

/// Typr switches, stored in the App Group so the keyboard reads them too.
/// Each switch documents its default. Dictation log deliberately retains saved history while off;
/// other switches keep upstream's behavior when off.
nonisolated struct TyprSettings {
    private enum Key {
        static let aiCleanup = "typr.aiCleanup"
        static let dictationLog = "typr.dictationLog"
        static let autocorrectGerman = "typr.autocorrectGerman"
        static let autocorrectEnglish = "typr.autocorrectEnglish"
        static let autocorrectLanguageOrder = "typr.autocorrectLanguageOrder"
        static let hideSuggestionBar = "typr.hideSuggestionBar"
        static let personalLearning = "keyboard.personalLearning"
        static let dictationLanguage = "typr.dictationLanguage"
        static let preferredSpeechEngine = "typr.preferredSpeechEngine"
        static let dictationEndsWithPeriod = "typr.dictationEndsWithPeriod"
        static let dictationLowercase = "typr.dictationLowercase"
        static let dictationFormatLists = "typr.dictationFormatLists"
        static let dictationSpokenPunctuation = "typr.dictationSpokenPunctuation"
        static let translateDictation = "typr.translateDictation"
        static let translationTarget = "typr.translationTarget"
        static let translationFailure = "typr.translationFailure"
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

    /// On by default: each style ends its text as before. Off, no dictated line ends with a full
    /// stop (`TranscriptFormatter.format(_:style:language:lists:punctuation:endsWithPeriod:)`).
    var dictationEndsWithPeriod: Bool {
        get { defaults?.object(forKey: Key.dictationEndsWithPeriod) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationEndsWithPeriod) }
    }

    /// Off by default. On, dictation is lowercased after its style and vocabulary.
    var dictationLowercase: Bool {
        get { defaults?.object(forKey: Key.dictationLowercase) as? Bool ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationLowercase) }
    }

    /// Hex's Format lists (anomalyco/hex #2131, `SpokenLists`), on by default as in Hex.
    var dictationFormatLists: Bool {
        get { defaults?.object(forKey: Key.dictationFormatLists) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationFormatLists) }
    }

    /// Hex's Spoken punctuation (anomalyco/hex #2198, `SpokenPunctuation`), on by default as in Hex.
    var dictationSpokenPunctuation: Bool {
        get { defaults?.object(forKey: Key.dictationSpokenPunctuation) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationSpokenPunctuation) }
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

    /// Translate what I say (Hex #2015): dictations go in as `translationTarget`. Off by default.
    var translateDictation: Bool {
        get { defaults?.object(forKey: Key.translateDictation) as? Bool ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.translateDictation) }
    }

    /// German or English; English by default and for any other stored value.
    var translationTarget: DictationLanguage {
        get { defaults?.string(forKey: Key.translationTarget) == DictationLanguage.german.rawValue ? .german : .english }
        nonmutating set { defaults?.set(newValue.rawValue, forKey: Key.translationTarget) }
    }

    /// Why the last translated dictation went in as spoken, until one translates.
    var translationFailure: TranslationFailure? {
        get { defaults?.string(forKey: Key.translationFailure).flatMap(TranslationFailure.init(rawValue:)) }
        nonmutating set { defaults?.set(newValue?.rawValue, forKey: Key.translationFailure) }
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
