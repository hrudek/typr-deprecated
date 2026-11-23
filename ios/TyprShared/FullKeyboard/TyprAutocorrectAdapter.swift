import UIKit

/// Typr's typing and autocorrect (`TyprAutocorrectEngine`) behind Hex's `FullKeyboardEngine`.
/// Typr reads German and English only; any other language on the keys gets no dictionary.
/// Hex's taps, typing models and journal are not read: Typr keeps its own models and learning.
@MainActor
final class TyprAutocorrectAdapter: KeyboardAutocorrecting {
    let engine: TyprAutocorrectEngine
    private let makeGerman: () -> GermanAutocorrect
    let checker: TextChecking

    var isEnabled: Bool {
        get { engine.isEnabled }
        set { engine.isEnabled = newValue }
    }
    var allowsSwearing: Bool {
        get { engine.allowsSwearing }
        set { engine.allowsSwearing = newValue }
    }
    var learnsPerLanguage: Bool {
        get { engine.learnsLanguagesSeparately }
        set { engine.learnsLanguagesSeparately = newValue }
    }
    var addsCapitals = true

    private(set) var language: KeyboardLanguage = .english
    private(set) var partnerLanguage: KeyboardLanguage?
    private(set) var layoutLetters: KeyboardLetterLayout?
    let lastFixLanguage: KeyboardLanguage? = nil
    let lastRevisionLanguage: KeyboardLanguage? = nil
    var hasDictionary: Bool { Self.languages.contains(language) }

    var decoder: TypingDecoder?
    var decoderKeys: TypingDecoder.Keys?
    var decoderBaselineKeys: TypingDecoder.Keys?
    var decoderTaps: [CGPoint]?
    var contextModel: TypingDecoderModel?
    var germanCapitals: GermanCapitals?
    var partnerDecoder: TypingDecoder?

    private(set) var vocabulary: [String] = []
    private(set) var ownWordsRevision = 0
    private(set) var offensiveWords: OffensiveWords
    var ownWords: [String] {
        engine.lexiconTerms + engine.lexiconShortcuts.values.filter { !$0.contains(" ") }
    }

    private var correction: AutocorrectEngine.AppliedCorrection?
    private var undos: [String: TyprAutocorrectEngine.AppliedCorrection] = [:]
    /// `undos` of a correction being reverted: Hex forgets it, then keeps each typed word.
    private var reverting: [String: TyprAutocorrectEngine.AppliedCorrection] = [:]
    private var lastRevision: (from: String, to: String, context: String?)?

    private static let languages: Set<KeyboardLanguage> = [.english, .german]

    init(engine: TyprAutocorrectEngine, makeGerman: @escaping () -> GermanAutocorrect = GermanAutocorrect.system) {
        self.engine = engine
        self.makeGerman = makeGerman
        checker = TyprTextCheckerBridge(engine.checker)
        offensiveWords = .bundled(KeyboardLanguage.english.rawValue)
        applyLanguages()
    }

    func setLanguage(_ language: KeyboardLanguage, available: [String]) {
        self.language = language
        if partnerLanguage == language { partnerLanguage = nil }
        offensiveWords = .bundled(language.rawValue)
        applyLanguages()
    }

    func setPartner(_ other: KeyboardLanguage?, available: [String], checker: TextChecking?) {
        partnerLanguage = other == language ? nil : other
        applyLanguages()
    }

    private func applyLanguages() {
        let languages: Set<KeyboardLanguage?> = [language, partnerLanguage]
        engine.englishEnabled = languages.contains(.english)
        if languages.contains(.german) {
            if engine.german == nil { engine.german = makeGerman() }
        } else {
            engine.german = nil
        }
        engine.preferredLanguage = language == .german ? .german : .english
    }

    func setKeys(_ language: KeyboardLanguage, letters: KeyboardLetterLayout) {
        layoutLetters = letters
        engine.letters = TyprKeyboardLetterLayout(rawValue: letters.rawValue) ?? (language == .german ? .qwertz : .qwerty)
    }

    func setVocabulary(_ terms: [String]) {
        vocabulary = terms
        if engine.loadCustomWords(terms) { ownWordsRevision += 1 }
    }

    func loadLexicon(_ lexicon: UILexicon) {
        engine.loadLexicon(lexicon)
        ownWordsRevision += 1
    }

    func applyLearning(_ learning: TypingLearning, partner partnerLearning: TypingLearning?) {}

    func suggestions(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?,
        predictionModel: TypingDecoderModel?,
        capitalizesNext: Bool
    ) -> [KeyboardSuggestion] {
        reverting = [:]
        guard hasDictionary else { return [] }
        let finishedWord = TyprAutocorrectEngine.currentToken(in: beforeInput) == nil
        return engine.suggestions(beforeInput: beforeInput, field: Self.field(field), autocorrectionType: autocorrectionType)
            .compactMap { suggestion in
                guard suggestion.boundary == nil, !suggestion.isSwipe, suggestion.kind != .revert else { return nil }
                let kind: KeyboardSuggestion.Kind = switch suggestion.kind {
                case _ where suggestion.isEmoji: .emoji
                case _ where finishedWord: .nextWord
                case .keepLiteral: .keepLiteral
                case .primary(let autoReplace): .primary(autoReplace: autoReplace)
                case .secondary, .revert: .secondary
                }
                return KeyboardSuggestion(displayText: suggestion.displayText, replacement: suggestion.replacement, kind: kind)
            }
    }

    func replacementOnSpace(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> (original: String, replacement: String)? {
        reverting = [:]
        guard hasDictionary else { return nil }
        return engine.replacementOnSpace(beforeInput: beforeInput, field: Self.field(field), autocorrectionType: autocorrectionType)
    }

    func revision(of word: String, before: String, next: String, field: KeyboardFieldKind, autocorrectionType: UITextAutocorrectionType?) -> String? {
        lastRevision = nil
        guard field == .text, autocorrectionType != .no, hasDictionary,
              let nextWord = next.split(separator: " ").first.map(String.init),
              let revised = engine.revision(of: word, before: before, next: nextWord) else { return nil }
        lastRevision = (word, revised, RejectedCorrection.context(before: before, token: word))
        return revised
    }

    func merge(first: String, firstTaps: [CGPoint], space: CGPoint, second: String, before: String) -> String? { nil }

    func textReplacement(before: String?) -> (typed: String, replacement: String)? {
        guard let token = TyprAutocorrectEngine.currentToken(in: before),
              before?.hasSuffix(token) == true,
              let replacement = engine.shortcut(for: token) else { return nil }
        return (token, replacement)
    }

    func mayOffer(_ candidate: String, after previous: String?) -> Bool {
        engine.mayOffer(candidate, after: previous)
    }

    func isOwnSpelling(_ word: String) -> Bool {
        engine.lexiconShortcuts.values.contains(word) || engine.lexiconTerms.contains(word)
    }

    func withoutStrayCapital(_ word: String, typed: String) -> String { word }

    func vocabularyTerm(for token: String) -> String? {
        vocabulary.lazy.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .first { $0.caseInsensitiveCompare(token) == .orderedSame }
    }

    func suppressAndKeep(_ word: String) {
        if let undo = reverting.removeValue(forKey: word.lowercased()) {
            engine.recordUndo(undo)
        } else {
            engine.suppressAndKeep(word)
        }
    }

    func recordAppliedCorrection(original: String, corrected: String, anchor: String, changes: [AutocorrectEngine.AppliedCorrection.Change]) {
        correction = AutocorrectEngine.AppliedCorrection(original: original, corrected: corrected, changes: changes, anchor: anchor)
        reverting = [:]
        engine.recordAppliedCorrection(original: original, corrected: corrected, separator: "", before: anchor)
        let applied = engine.revertOffer(before: anchor)?.correction
        engine.clearRevertOffer()
        engine.discardFeedback()
        undos = [:]
        for change in changes {
            if let lastRevision, lastRevision.from == change.from, lastRevision.to == change.to {
                undos[change.from.lowercased()] = .init(
                    original: change.from, insertedText: change.to, context: lastRevision.context,
                    revised: RejectedCorrection(typed: change.from, replacement: change.to)
                )
            } else {
                undos[change.from.lowercased()] = .init(
                    original: change.from, insertedText: change.to,
                    kind: applied?.kind ?? .autoRule, context: applied?.context
                )
            }
        }
        lastRevision = nil
    }

    func revertibleCorrection(before: String?) -> AutocorrectEngine.AppliedCorrection? {
        guard let correction, correction.isAtEnd(of: before) else { return nil }
        return correction
    }

    func forgetCorrection() {
        correction = nil
        reverting = undos
        undos = [:]
    }

    private static func field(_ field: KeyboardFieldKind) -> TyprKeyboardFieldKind {
        switch field {
        case .text: .text
        case .url: .url
        case .email: .email
        }
    }
}

/// Typr's spelling dictionary as Hex's `TextChecking`; Typr picks its dictionaries itself.
private final class TyprTextCheckerBridge: TextChecking {
    private let checker: TyprTextChecking

    init(_ checker: TyprTextChecking) {
        self.checker = checker
    }

    func isWordValid(_ word: String) -> Bool { checker.isWordValid(word) }
    func guesses(for word: String) -> [String] { checker.guesses(for: word) }
    func completions(for prefix: String) -> [String] { checker.completions(for: prefix) }
    func useLanguage(_ code: String) {}
}
