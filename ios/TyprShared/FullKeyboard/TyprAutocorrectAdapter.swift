import UIKit

/// Typr's typing and autocorrect (`TyprAutocorrectEngine`) behind Hex's `FullKeyboardEngine`.
/// Typr reads German and English only; any other language on the keys gets no dictionary.
/// Hex's taps are read on Typr's keys; Hex's typing models and journal are not: Typr keeps its own.
@MainActor
final class TyprAutocorrectAdapter: KeyboardAutocorrecting {
    let engine: TyprAutocorrectEngine
    private let makeGerman: @MainActor () -> GermanAutocorrect
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
    private var reverting: [String: TyprAutocorrectEngine.AppliedCorrection] = [:]
    private var lastRevision: (from: String, to: String, context: String?)?
    private var touchLayout = TyprKeyboardLayout(width: TyprAutocorrectAdapter.touchWidth)
    private var spaceDecision: (beforeInput: String, result: (original: String, replacement: String)?)?
    private var strip: [TyprKeyboardSuggestion] = []
    private var typing: (field: KeyboardFieldKind, autocorrection: UITextAutocorrectionType?)?
    private var keptByPick: String?
    var isSecureField = false
    private var learnsFromTyping: Bool {
        !isSecureField && hasDictionary && typing?.field == .text && typing?.autocorrection != UITextAutocorrectionType.no
    }
    private static let touchWidth: CGFloat = 393

    private static let languages: Set<KeyboardLanguage> = [.english, .german]

    init(engine: TyprAutocorrectEngine, makeGerman: @escaping @MainActor () -> GermanAutocorrect = GermanAutocorrect.system) {
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
        touchLayout = TyprKeyboardLayout(width: Self.touchWidth, letters: engine.letters)
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
        typing = (field, autocorrectionType)
        strip = []
        guard hasDictionary, !isSecureField else { return [] }
        loadTouches(beforeInput: beforeInput)
        let finishedWord = TyprAutocorrectEngine.currentToken(in: beforeInput) == nil
        strip = engine.suggestions(beforeInput: beforeInput, field: Self.field(field), autocorrectionType: autocorrectionType)
        return strip
            .compactMap { suggestion in
                guard suggestion.boundary == nil, !suggestion.isSwipe else { return nil }
                let kind: KeyboardSuggestion.Kind
                switch suggestion.kind {
                case .revert: return nil
                case _ where suggestion.isEmoji: kind = .emoji
                case _ where finishedWord: kind = .nextWord
                case .keepLiteral: kind = .keepLiteral
                case .primary(let autoReplace): kind = .primary(autoReplace: autoReplace)
                case .secondary: kind = .secondary
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
        defer { spaceDecision = nil }
        guard hasDictionary, !isSecureField, let beforeInput, let token = TyprAutocorrectEngine.currentToken(in: beforeInput) else { return nil }
        if let spaceDecision, spaceDecision.beforeInput == beforeInput { return spaceDecision.result }
        loadTouches(beforeInput: beforeInput)
        let result = engine.replacementOnSpace(beforeInput: beforeInput, field: Self.field(field), autocorrectionType: autocorrectionType)
        if let result, result.original != token {
            engine.discardFeedback()
            return nil
        }
        return result
    }

    func revision(of word: String, before: String, next: String, field: KeyboardFieldKind, autocorrectionType: UITextAutocorrectionType?) -> String? {
        lastRevision = nil
        guard field == .text, autocorrectionType != .no, hasDictionary,
              let nextWord = next.split(separator: " ").first.map(String.init),
              let revised = engine.revision(of: word, before: before, next: nextWord) else { return nil }
        lastRevision = (word, revised, RejectedCorrection.context(before: before, token: word))
        return revised
    }

    func merge(first: String, firstTaps: [CGPoint], space: CGPoint, second: String, before: String) -> String? {
        spaceDecision = nil
        guard learnsFromTyping, let typing,
              loadTouches(first: first, firstTaps: firstTaps, space: space, second: second, before: before) else { return nil }
        let beforeInput = before + " " + second
        let result = engine.replacementOnSpace(beforeInput: beforeInput, field: Self.field(typing.field),
                                               autocorrectionType: typing.autocorrection)
        if let result, result.original == first + " " + second, !result.replacement.contains(" ") {
            return result.replacement
        }
        if let result, result.original != second { engine.discardFeedback() }
        spaceDecision = (beforeInput, result?.original == second ? result : nil)
        return nil
    }

    private func loadTouches(beforeInput: String?) {
        engine.touchInput.clear()
        guard let beforeInput, let token = TyprAutocorrectEngine.currentToken(in: beforeInput),
              let taps = decoderTaps else { return }
        appendTouches(taps, word: token, following: String(beforeInput.dropLast(token.count)))
    }

    @discardableResult
    func loadTouches(first: String, firstTaps: [CGPoint], space: CGPoint, second: String, before: String) -> Bool {
        engine.touchInput.clear()
        guard before.hasSuffix(first), let taps = decoderTaps, let spacePoint = typrSpacePoint(space),
              let spaceKey = touchLayout.key(.space),
              appendTouches(firstTaps, word: first, following: String(before.dropLast(first.count))) else { return false }
        engine.touchInput.append(text: " ", point: spacePoint, key: spaceKey, layout: touchLayout,
                                 before: before, after: before + " ")
        return appendTouches(taps, word: second, following: before + " ")
    }

    @discardableResult
    private func appendTouches(_ taps: [CGPoint], word: String, following head: String) -> Bool {
        guard taps.count == word.count else { return false }
        var before = head
        for (tap, letter) in zip(taps, word) {
            let text = String(letter)
            guard let key = touchLayout.key(.character(text.lowercased())),
                  let point = typrPoint(tap, on: key, letter: Character(text.lowercased())) else {
                engine.touchInput.clear()
                return false
            }
            engine.touchInput.append(text: text, point: point, key: key, layout: touchLayout,
                                     before: before, after: before + text)
            before += text
        }
        return true
    }

    private func typrPoint(_ tap: CGPoint, on key: TyprKeyboardKey, letter: Character) -> CGPoint? {
        guard let keys = decoderBaselineKeys ?? decoderKeys, let centre = keys.centres[letter], keys.pitch.width > 0, keys.pitch.height > 0,
              let pitch = touchLayout.key(.character("g"))?.hitFrame.size else { return nil }
        return CGPoint(x: key.frame.midX + (tap.x - centre.x) / keys.pitch.width * pitch.width,
                       y: key.frame.midY + (tap.y - centre.y) / keys.pitch.height * pitch.height)
    }

    private func typrSpacePoint(_ tap: CGPoint) -> CGPoint? {
        guard let hex = (decoderBaselineKeys ?? decoderKeys)?.space, hex.width > 0, hex.height > 0,
              let space = touchLayout.key(.space)?.frame else { return nil }
        return CGPoint(x: space.midX + (tap.x - hex.midX) / hex.width * space.width,
                       y: space.midY + (tap.y - hex.midY) / hex.height * space.height)
    }

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
        guard !isSecureField else { return }
        if keptByPick == word.lowercased() {
            keptByPick = nil
            return
        }
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
        let join = applied?.boundary.flatMap { $0.original == original ? $0 : nil }
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
                    kind: applied?.kind ?? .autoRule, context: applied?.context, boundary: join
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

    func typedLetter(_ letter: String, before: String?, after: String?) {
        guard learnsFromTyping else { return }
        engine.settleFeedback(beforeInput: before, insertedLetter: letter, afterInput: after)
    }

    func pickedSuggestion(_ suggestion: KeyboardSuggestion, replacing token: String?, before: String?) {
        keptByPick = nil
        guard learnsFromTyping else { return }
        guard let token else {
            if suggestion.kind == .nextWord { engine.recordPredictionFeedback(suggestion.replacement, beforeInput: before) }
            return
        }
        guard let picked = strip.first(where: {
            $0.replacement == suggestion.replacement && $0.displayText == suggestion.displayText
        }) else { return }
        engine.recordSuggestionFeedback(picked, literal: token, evidence: engine.touchInput.evidence(beforeInput: before))
        if suggestion.kind == .keepLiteral { keptByPick = token.lowercased() }
    }

    func tappedSpace(at point: CGPoint, after: String?) {
        guard learnsFromTyping, let typrPoint = typrSpacePoint(point) else { return }
        engine.spaceTyped(at: typrPoint, layout: touchLayout, afterInput: after)
    }

    func textEdited() {
        engine.discardFeedback(keepingCorrection: correction != nil)
        engine.forgetSpaceTaps()
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
