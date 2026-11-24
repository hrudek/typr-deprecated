import Foundation
import UIKit

/// Hex's system spelling stand-in: the bundled list of the language `useLanguage` picks, with no guesses.
@MainActor
final class HexLexiconChecker: TextChecking {
    private let lexicons: [Language: SpatialWordLexicon]
    private var lexicon: SpatialWordLexicon?

    init(_ lexicons: [Language: SpatialWordLexicon], language: KeyboardLanguage) {
        self.lexicons = lexicons
        useLanguage(language.rawValue)
    }

    func useLanguage(_ code: String) {
        lexicon = code.hasPrefix("de") ? lexicons[.german] : code.hasPrefix("en") ? lexicons[.english] : nil
    }

    func isWordValid(_ word: String) -> Bool { lexicon?.logPrior(for: word.lowercased()) != nil }
    func guesses(for word: String) -> [String] { [] }
    func completions(for prefix: String) -> [String] { [] }
}

@MainActor
final class HexReplayTarget: KeyboardTextTarget {
    var text: String

    init(text: String) { self.text = text }

    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var hasText: Bool { !text.isEmpty }
    var autocapitalizationType: UITextAutocapitalizationType? { .sentences }
    var keyboardType: UIKeyboardType? { .default }
    var returnKeyType: UIReturnKeyType? { .default }
    var keyboardAppearance: UIKeyboardAppearance? { .default }
    var smartQuotesType: UITextSmartQuotesType? { nil }
    var smartDashesType: UITextSmartDashesType? { nil }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}

extension Replayer {
    /// The keyboard language and bilingual partner Hex types the word with: German when the keys
    /// are QWERTZ or English is not among the word's languages.
    static func hexLanguages(_ word: TypingLogWord) -> (current: KeyboardLanguage, partner: KeyboardLanguage?)? {
        let codes = Set(word.languages)
        let german = codes.contains(KeyboardLanguage.german.rawValue)
        let english = codes.contains(KeyboardLanguage.english.rawValue)
        guard german || english else { return nil }
        let current: KeyboardLanguage = german && (!english || word.layout?.letters == "qwertz") ? .german : .english
        let other: KeyboardLanguage = current == .german ? .english : .german
        return (current, codes.contains(other.rawValue) ? other : nil)
    }

    /// A tap logged on Typr's keys, at the same place relative to the same key on Hex's.
    static func hexPoint(_ tap: TypingLogTap, from typr: TyprKeyboardLayout, to hex: KeyboardLayout) -> CGPoint? {
        guard let x = tap.x, let y = tap.y else { return nil }
        let text = tap.key ?? tap.text.lowercased()
        let kinds: (TyprKeyKind, KeyKind) = text == " " ? (.space, .space) : (.character(text), .character(text))
        guard let from = typr.key(kinds.0, nearest: CGPoint(x: x, y: y))?.frame, let to = hex.key(kinds.1)?.frame,
              from.width > 0, from.height > 0 else { return nil }
        return CGPoint(x: to.midX + (x - from.midX) / from.width * to.width,
                       y: to.midY + (y - from.midY) / from.height * to.height)
    }

    /// The word's logged input through Hex's keyboard and autocorrect with its default settings and no
    /// personal learning: Hex keeps its own, which the export does not carry.
    func replayHex(_ word: TypingLogWord, _ prepared: PreparedWord, context: String) -> Result<ReplayedWord, SkipReason> {
        guard let logged = word.layout, let typr = logged.keyboardLayout else { return .failure(.unknownLayout) }
        guard let languages = Self.hexLanguages(word) else { return .failure(.noHexLanguage) }
        let autocorrect = AutocorrectEngine(checker: HexLexiconChecker(words.lexicons, language: languages.current),
                                            learnedWords: LearnedWordsStore(defaults: nil))
        let target = HexReplayTarget(text: context)
        let engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        var now: TimeInterval = 1_000
        engine.clock = { now }
        engine.width = typr.width
        engine.orientation = typr.orientation == .landscape ? .landscape : .portrait
        engine.showsStrip = logged.showsStrip
        engine.language = languages.current
        autocorrect.setPartner(languages.partner, available: UITextChecker.availableLanguages,
                               checker: languages.partner.map { HexLexiconChecker(words.lexicons, language: $0) })
        engine.configureForField()
        // As FullKeyboardView.syncSpatialAutocorrect with Hex's default settings and no learned key centres.
        let settings = FullKeyboardSettings(defaults: nil)
        let model = settings.typingModel(for: languages.current)
        engine.letterOdds = model
        if settings.spatialAutocorrect {
            autocorrect.decoder = model.map { TypingDecoder(model: $0) }
            autocorrect.partnerDecoder = languages.partner.flatMap(settings.typingModel(for:)).map { TypingDecoder(model: $0) }
        }
        engine.tapOffsets = TypingDecoder.offsets(from: [:], layout: engine.layout)

        var touch = 0
        func press(_ point: CGPoint) {
            touch += 1
            engine.touchBegan(id: touch, at: point)
            engine.touchEnded(id: touch, at: point)
        }
        func press(_ kind: KeyKind) -> Bool {
            guard let key = engine.layout.key(kind) else { return false }
            press(CGPoint(x: key.frame.midX, y: key.frame.midY))
            return true
        }
        func typed() -> String { String(target.text.dropFirst(context.count)) }
        let start = now
        for step in prepared.plan.steps {
            switch step {
            case .tap(let tap):
                guard let point = Self.hexPoint(tap, from: typr, to: engine.layout) else { return .failure(.noHexKey) }
                let time = start + Double(tap.t) / 1000
                if tap.text.first?.isLetter == true, (tap.text != tap.text.lowercased()) != engine.isUppercase {
                    now = max(now + 0.001, time - 0.05)
                    guard press(.shift) else { return .failure(.noHexKey) }
                }
                now = max(now + 0.001, time)
                press(point)
            case .delete(let count):
                for _ in 0..<count {
                    now += 0.001
                    guard press(.delete) else { return .failure(.noHexKey) }
                }
            }
        }
        let literal = typed()
        now += 0.2
        switch prepared.plan.end {
        case .none:
            return .success(ReplayedWord(literal: literal, committed: literal))
        case .separator(let separator):
            guard press(separator == "\n" ? .returnKey : .space) else { return .failure(.noHexKey) }
        case .pick(let to, let chip):
            engine.refreshSuggestions()
            guard let suggestion = engine.suggestions.first(where: {
                $0.replacement == to && FullKeyboardEngine.typrTypingLogChip($0.kind) == chip
            }) else { return .failure(.pickNotOffered) }
            engine.acceptSuggestion(suggestion)
            guard typed() != literal else { return .failure(.pickNotOffered) }
        }
        var committed = typed()
        if committed.last?.isWhitespace == true { committed.removeLast() }
        return .success(ReplayedWord(literal: literal, committed: committed))
    }
}
