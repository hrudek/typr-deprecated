import Foundation

/// The steps between the speech model and the text Typr inserts, the same wherever Typr
/// dictates: `DictationController` (the app, the keyboard's warm session and cold start, the
/// Action Button, Control Center and Siri) and in-keyboard dictation
/// (`KeyboardLocalDictation`), so a style, the formatting switches and the vocabulary apply on
/// every path. Adapted from Hex (anomalyco/hex `ios/HEXShared/DictationPipeline.swift` at
/// 0c1c13d7, MIT); see THIRD_PARTY_NOTICES.md.
///
/// In Hex's order: learned fixes, custom vocabulary (and Typr's tech glossary,
/// `DictationVocabulary`), Clean up what I say (`SpokenCleanup`), `refine` (AI cleanup, only in
/// the app), translation (only in the app), the style (`TranscriptFormatter`, with Format lists'
/// `SpokenLists` and Spoken punctuation's `SpokenPunctuation` inside it), the spellings again,
/// Lowercase, then French spacing (`FrenchSpacing`, in every style but Verbatim). Without
/// `refine` and translation every step is a string rule with no model, so in-keyboard dictation
/// needs no more memory to run them.
///
/// Typr variants (Settings › Experimental): Typr dictation styles formats with
/// `TyprTranscriptFormatter`; Typr German formatting rules writes lists and punctuation with
/// `TyprSpokenLists` and `TyprSpokenPunctuation`, switched by the old Format lists and Spoken
/// punctuation experiments instead of the Dictation settings.
nonisolated struct DictationPipeline: Sendable {
    var style: DictationStyle
    /// The dictation language (BCP 47); nil is Typr's Automatic: German unless the text reads as
    /// English (`TyprTranscriptFormatter.readsAsEnglish`).
    var language: String?
    var vocabulary = DictationVocabulary(userTerms: [])
    /// Clean up what I say (`SpokenCleanup`).
    var spokenCleanup = false
    var lowercase = false
    /// Format lists, inside the style.
    var formatLists = false
    /// Spoken punctuation, inside the style.
    var spokenPunctuation = false
    /// End with a period; off, no line ends with a full stop.
    var endsWithPeriod = true
    /// Typr dictation styles: `TyprTranscriptFormatter` instead of Hex's `TranscriptFormatter`.
    var typrStyles = false
    /// Typr German formatting rules: Typr's list and punctuation rules instead of Hex's.
    var typrFormattingRules = false

    /// Hex's pipeline: `vocabulary` and `corrections` as Custom vocabulary's terms and learned
    /// fixes.
    init(
        style: DictationStyle,
        language: String?,
        vocabulary: [String] = [],
        corrections: [DictationCorrection] = [],
        lowercase: Bool = false,
        formatLists: Bool = false,
        spokenPunctuation: Bool = false,
        endsWithPeriod: Bool = true
    ) {
        self.style = style
        self.language = language
        self.vocabulary = DictationVocabulary(userTerms: vocabulary, learnedFixes: corrections)
        self.lowercase = lowercase
        self.formatLists = formatLists
        self.spokenPunctuation = spokenPunctuation
        self.endsWithPeriod = endsWithPeriod
    }

    /// The pipeline for one dictation, from the settings at its start. A style that isn't on
    /// offer (Typr's Casual while Typr dictation styles is off) writes as Polished.
    init(
        style: DictationStyle,
        language: DictationLanguage,
        vocabulary: DictationVocabulary,
        settings: TyprSettings
    ) {
        let typrStyles = settings[experiment: .typrDictationStyles]
        let typrFormattingRules = settings[experiment: .typrGermanFormattingRules]
        self.init(
            style: style.resolved(typrStyles: typrStyles),
            language: language.formattingIdentifier
        )
        self.typrStyles = typrStyles
        self.typrFormattingRules = typrFormattingRules
        self.vocabulary = vocabulary
        spokenCleanup = settings[experiment: .cleanUpWhatISay] && self.style != .verbatim
        lowercase = settings.dictationLowercase
        endsWithPeriod = settings.dictationEndsWithPeriod
        formatLists = typrFormattingRules ? settings[experiment: .formatLists] : settings.dictationFormatLists
        spokenPunctuation = typrFormattingRules
            ? settings[experiment: .spokenPunctuation] : settings.dictationSpokenPunctuation
    }

    /// What translation did with the cleaned text.
    enum Translation: Sendable {
        /// Translated into `language` (BCP 47), which the style then formats in.
        case translated(String, language: String?)
        /// Not translated: it goes in as spoken.
        case asSpoken
    }

    /// Each step's text, for the dictation log.
    struct Stages: Equatable, Sendable {
        /// What the speech model heard.
        var heard: String
        /// After learned fixes, custom vocabulary and the glossary.
        var spelled: String
        /// The spellings AI cleanup is told to keep.
        var cleanupTerms: [String]
        /// After Clean up what I say.
        var tagged: String
        /// After `refine`.
        var cleaned: String
        var translated: String?
        /// After the style, before the spellings are restored.
        var styled: String
        /// What Typr inserts.
        var formatted: String
    }

    /// `onSpelling` and `onRespelling` see each vocabulary replacement; `onSpelled` the text
    /// after the spelling step. `refine` and `translate` are the app's model steps; a caller that
    /// is cancelled meanwhile discards the result.
    @MainActor
    func run(
        _ heard: String,
        onSpelling: ((_ before: String, _ after: String, _ term: String, _ source: DictationVocabulary.Source) -> Void)? = nil,
        onSpelled: ((String) -> Void)? = nil,
        refine: ((_ text: String, _ terms: [String]) async -> String)? = nil,
        translate: ((String) async -> Translation)? = nil,
        onRespelling: ((_ before: String, _ after: String, _ term: String) -> Void)? = nil
    ) async -> Stages {
        // Spaced compounds first, so spelling and cleanup see "Pull Request" and a hyphenated
        // user term is restored.
        let prepared = vocabulary.beforeCleanup(CleanupHyphens.spaceCompounds(heard), onReplacement: onSpelling)
        onSpelled?(prepared.text)
        let tagged = spokenCleanup ? SpokenCleanup.clean(prepared.text, language: typrLanguage) : prepared.text
        let cleaned = await refine?(tagged, prepared.cleanupTerms) ?? tagged
        var translated: String?
        var formatLanguage = language
        if let translate, case .translated(let text, let target) = await translate(cleaned) {
            translated = text
            formatLanguage = target
        }
        let styled = applyStyle(translated ?? cleaned, language: formatLanguage)
        return Stages(
            heard: heard,
            spelled: prepared.text,
            cleanupTerms: prepared.cleanupTerms,
            tagged: tagged,
            cleaned: cleaned,
            translated: translated,
            styled: styled,
            formatted: finish(styled, language: formatLanguage, onReplacement: onRespelling)
        )
    }

    /// `text` in the style and language (BCP 47; nil is Automatic).
    func applyStyle(_ text: String, language: String?) -> String {
        if typrStyles {
            return TyprTranscriptFormatter.format(
                text, style: style, language: DictationLanguage(formattingLanguage: language),
                lists: formatLists, punctuation: spokenPunctuation, endsWithPeriod: endsWithPeriod,
                rules: typrFormattingRules ? .typr : .hex
            )
        }
        return TranscriptFormatter.format(
            text, style: style, language: Self.resolved(language, for: text),
            lists: formatLists, punctuation: spokenPunctuation, endsWithPeriod: endsWithPeriod,
            rules: typrFormattingRules ? .typr : .hex
        )
    }

    /// After the style: the vocabulary's and learned fixes' spellings again (a style can
    /// lowercase a term or capitalize a sentence start: "iPhone" -> "IPhone"), then Lowercase,
    /// with Unicode's context-aware mapping, then, in French, the spaces before `? ! ; :` and
    /// inside `« »` that the styles take out (`FrenchSpacing`). Verbatim keeps the model's
    /// spacing; as in Hex, Lowercase applies to it too, except with Typr dictation styles.
    func finish(
        _ styled: String,
        language: String?,
        onReplacement: ((_ before: String, _ after: String, _ term: String) -> Void)? = nil
    ) -> String {
        let spelled = vocabulary.afterFormatting(styled, onReplacement: onReplacement)
        let lowercases = lowercase && !(typrStyles && style == .verbatim)
        let cased = lowercases ? spelled.lowercased(with: nil) : spelled
        return style == .verbatim ? cased : FrenchSpacing.apply(cased, language: Self.resolved(language, for: cased))
    }

    /// The style, the spellings, Lowercase and French spacing.
    func format(_ text: String, language: String?) -> String {
        finish(applyStyle(text, language: language), language: language)
    }

    private var typrLanguage: DictationLanguage { DictationLanguage(formattingLanguage: language) }

    /// `language`, or for Automatic, English when `text` reads as English, else German.
    static func resolved(_ language: String?, for text: String) -> String {
        language ?? (TyprTranscriptFormatter.readsAsEnglish(text) ? "en" : "de")
    }
}

extension DictationLanguage {
    /// The language the pipeline formats in: an explicit language's code, nil for Automatic.
    nonisolated var formattingIdentifier: String? { self == .automatic ? nil : rawValue }

    /// German or English for a BCP 47 language of that family; any other (and nil) is Automatic.
    nonisolated init(formattingLanguage: String?) {
        let code = formattingLanguage.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        self = code.flatMap(DictationLanguage.init(rawValue:)) ?? .automatic
    }

    /// The text's language for Typr's Automatic rules: English when it reads as English, else
    /// German. An explicit language is itself.
    nonisolated func formattingLanguage(for text: String) -> String {
        DictationPipeline.resolved(formattingIdentifier, for: text)
    }
}
