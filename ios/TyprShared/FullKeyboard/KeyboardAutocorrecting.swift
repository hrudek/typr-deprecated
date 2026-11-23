import UIKit

/// What Hex's `FullKeyboardEngine` and `FullKeyboardView` ask of their autocorrect backend;
/// Hex's `AutocorrectEngine` is the default.
@MainActor
protocol KeyboardAutocorrecting: AnyObject {
    var checker: TextChecking { get }
    var isEnabled: Bool { get set }
    var allowsSwearing: Bool { get set }
    var addsCapitals: Bool { get set }
    var learnsPerLanguage: Bool { get set }
    var language: KeyboardLanguage { get }
    var partner: AutocorrectEngine? { get }
    var hasDictionary: Bool { get }
    var layoutLetters: KeyboardLetterLayout? { get }
    var lastFixLanguage: KeyboardLanguage? { get }
    var lastRevisionLanguage: KeyboardLanguage? { get }

    var decoder: TypingDecoder? { get set }
    var decoderKeys: TypingDecoder.Keys? { get set }
    var decoderBaselineKeys: TypingDecoder.Keys? { get set }
    var decoderTaps: [CGPoint]? { get set }
    var contextModel: TypingDecoderModel? { get set }
    var germanCapitals: GermanCapitals? { get set }

    var vocabulary: [String] { get }
    var ownWords: [String] { get }
    var ownWordsRevision: Int { get }
    var offensiveWords: OffensiveWords { get }

    func setLanguage(_ language: KeyboardLanguage, available: [String])
    func setPartner(_ other: KeyboardLanguage?, available: [String], checker: TextChecking?)
    func setKeys(_ language: KeyboardLanguage, letters: KeyboardLetterLayout)
    func setVocabulary(_ terms: [String])
    func loadLexicon(_ lexicon: UILexicon)
    func applyLearning(_ learning: TypingLearning, partner partnerLearning: TypingLearning?)

    func suggestions(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?,
        predictionModel: TypingDecoderModel?,
        capitalizesNext: Bool
    ) -> [KeyboardSuggestion]
    func replacementOnSpace(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> (original: String, replacement: String)?
    func revision(of word: String, before: String, next: String, field: KeyboardFieldKind, autocorrectionType: UITextAutocorrectionType?) -> String?
    func merge(first: String, firstTaps: [CGPoint], space: CGPoint, second: String, before: String) -> String?
    func textReplacement(before: String?) -> (typed: String, replacement: String)?
    func mayOffer(_ candidate: String, after previous: String?) -> Bool
    func isOwnSpelling(_ word: String) -> Bool
    func withoutStrayCapital(_ word: String, typed: String) -> String
    func vocabularyTerm(for token: String) -> String?

    func suppressAndKeep(_ word: String)
    func revertibleCorrection(before: String?) -> AutocorrectEngine.AppliedCorrection?
    func recordAppliedCorrection(original: String, corrected: String, anchor: String, changes: [AutocorrectEngine.AppliedCorrection.Change])
    func forgetCorrection()
}

extension KeyboardAutocorrecting {
    func suggestions(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?,
        predictionModel: TypingDecoderModel?
    ) -> [KeyboardSuggestion] {
        suggestions(beforeInput: beforeInput, field: field, autocorrectionType: autocorrectionType,
                    predictionModel: predictionModel, capitalizesNext: false)
    }
}

extension AutocorrectEngine: KeyboardAutocorrecting {}
