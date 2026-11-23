import Foundation

/// Everything one dictation needs from vocabulary, frozen at recording start: the Apple Speech
/// hints, the spelling fixes before AI cleanup (fixes learned from your edits, then Custom
/// vocabulary, then the built-in tech glossary), the terms named to cleanup, and the spelling
/// restore after formatting.
/// Callers never order the passes or merge the lists themselves.
nonisolated struct DictationVocabulary: Sendable {
    enum Source: String, Sendable {
        case custom
        case builtIn = "built-in"
    }

    struct Prepared: Equatable, Sendable {
        /// The recognized text with spellings fixed, handed to cleanup or formatting.
        let text: String
        /// Spellings for AI cleanup: every active user term, then the glossary terms that
        /// appear in this dictation.
        let cleanupTerms: [String]
    }

    /// Apple's documented limit for contextual strings.
    static let maxSpeechHints = CustomVocabularySettings.maxTermCount

    /// Active Custom vocabulary terms (empty while that experiment is off).
    let userTerms: [String]
    private let userRules: [VocabularySpelling.Rule]
    /// Fixes Learn from my edits learned (empty unless Typr dictation edit learning is on).
    let learnedFixes: [TyprDictationCorrection]
    /// Fixes Hex's Learn how I type learned, applied with Hex's rules (`DictationCorrections`).
    let hexFixes: [DictationCorrection]
    private let restoreRules: [VocabularySpelling.Rule]

    init(userTerms: [String], soundsLike: [String: [String]] = [:], learnedFixes: [TyprDictationCorrection] = [],
         hexFixes: [DictationCorrection] = []) {
        self.userTerms = userTerms
        self.learnedFixes = learnedFixes
        self.hexFixes = hexFixes
        userRules = CustomVocabularySettings.rules(terms: userTerms, soundsLike: soundsLike)
        let learnedSpellings = TyprDictationCorrections.spellings(learnedFixes) + DictationCorrections.spellings(hexFixes)
        restoreRules = userRules + learnedSpellings.map(VocabularySpelling.Rule.init(term:))
    }

    /// Reads the Custom vocabulary switch, terms and sounds-like forms once.
    init(settings: CustomVocabularySettings, learnedFixes: [TyprDictationCorrection] = [],
         hexFixes: [DictationCorrection] = []) {
        if settings.isEnabled {
            self.init(userTerms: settings.terms, soundsLike: settings.soundsLike, learnedFixes: learnedFixes, hexFixes: hexFixes)
        } else {
            self.init(userTerms: [], learnedFixes: learnedFixes, hexFixes: hexFixes)
        }
    }

    @MainActor
    init(settings: CustomVocabularySettings, typr: TyprSettings, language: String?,
         learning: DictationLearningStore, journal: @MainActor (String?) -> [DictationCorrection]) {
        if typr[experiment: .typrDictationEditLearning] {
            self.init(settings: settings, learnedFixes: typr[experiment: .learnFromEdits] ? learning.corrections : [])
        } else {
            self.init(settings: settings, hexFixes: journal(language))
        }
    }

    /// The user's terms first, then learned spellings, then the glossary's listed terms, without
    /// duplicate spellings, capped at Apple's limit of 100.
    var speechHints: [String] {
        var seen = Set<String>()
        let all = (userTerms + hexFixes.map(\.meant) + learnedFixes.map(\.meant) + TechGlossary.listedTerms).filter {
            seen.insert(VocabularySpelling.normalizedKey($0)).inserted
        }
        return Array(all.prefix(Self.maxSpeechHints))
    }

    /// Spelling keys the glossary must leave alone, so the user's own terms and forms win:
    /// every form, every term and each word of a term (a user's "Herdr Tool" keeps its "Herdr").
    private var protectedKeys: Set<String> {
        var keys = Set<String>()
        for rule in userRules {
            keys.insert(VocabularySpelling.normalizedKey(rule.match))
            keys.insert(VocabularySpelling.normalizedKey(rule.spelling))
            for word in rule.spelling.split(whereSeparator: { $0.isWhitespace || $0 == "-" }) {
                keys.insert(VocabularySpelling.normalizedKey(String(word)))
            }
        }
        return keys
    }

    /// Fixes spellings in the recognized text before cleanup, reporting each replacement.
    func beforeCleanup(_ recognized: String,
                       onReplacement: ((_ before: String, _ after: String, _ term: String, _ source: Source) -> Void)? = nil)
        -> Prepared {
        let reportCustom: ((String, String, String) -> Void)? = onReplacement.map { report in
            { before, after, term in report(before, after, term, .custom) }
        }
        let reportBuiltIn: ((String, String, String) -> Void)? = onReplacement.map { report in
            { before, after, term in report(before, after, term, .builtIn) }
        }
        let protected = protectedKeys
        let learned = DictationCorrections.apply(hexFixes, to: TyprDictationCorrections.apply(learnedFixes, to: recognized))
        let custom = VocabularySpelling.apply(rules: userRules, to: learned, onReplacement: reportCustom)
        let glossary = TechGlossary.apply(to: custom, protectedKeys: protected, onReplacement: reportBuiltIn)
        let glossaryTerms = glossary.terms.filter { !protected.contains(VocabularySpelling.normalizedKey($0)) }
        return Prepared(text: glossary.text, cleanupTerms: userTerms + hexFixes.map(\.meant) + glossaryTerms)
    }

    /// Restores the user's spellings and learned ones with inner capitals after a style changed
    /// their case ("iPhone" → "IPhone"). The glossary does not run again: its fixes are already
    /// in the text cleanup received.
    func afterFormatting(_ formatted: String,
                         onReplacement: ((_ before: String, _ after: String, _ term: String) -> Void)? = nil) -> String {
        VocabularySpelling.apply(rules: restoreRules, to: formatted, onReplacement: onReplacement)
    }
}
