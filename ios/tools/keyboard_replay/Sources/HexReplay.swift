import Foundation
import UIKit

@MainActor
final class HexLexiconChecker: TextChecking {
    private let lexicons: [Language: SpatialWordLexicon]
    private var lexicon: SpatialWordLexicon?
    var recording = false
    private(set) var deviated = false

    init(_ lexicons: [Language: SpatialWordLexicon], language: KeyboardLanguage) {
        self.lexicons = lexicons
        useLanguage(language.rawValue)
    }

    func useLanguage(_ code: String) {
        lexicon = code.hasPrefix("de") ? lexicons[.german] : code.hasPrefix("en") ? lexicons[.english] : nil
    }

    func isWordValid(_ word: String) -> Bool {
        if recording, word != word.lowercased() { deviated = true }
        return lexicon?.logPrior(for: word.lowercased()) != nil
    }

    func guesses(for word: String) -> [String] {
        if recording, !word.isEmpty { deviated = true }
        return []
    }

    func completions(for prefix: String) -> [String] {
        if recording, !prefix.isEmpty { deviated = true }
        return []
    }
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
    static func requireHexResources() throws {
        guard FullKeyboardSettings(defaults: nil).typingModel(for: .english) != nil else {
            throw ReplayError("Hex's typing model en.hextm is missing or invalid next to keyboard-replay; run build.sh again")
        }
        for (name, type) in [("never-suggest", "tsv"), ("de", "capitals")] {
            guard let url = Bundle.main.url(forResource: name, withExtension: type) else {
                throw ReplayError("Hex's \(name).\(type) is missing next to keyboard-replay; run build.sh again")
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8), isValid(text, type: type) else {
                throw ReplayError("Hex's \(name).\(type) next to keyboard-replay is invalid; run build.sh again")
            }
        }
        guard GermanCapitals.bundled() != nil, !OffensiveWords.bundled(KeyboardLanguage.english.rawValue).isEmpty,
              !OffensiveWords.bundled(KeyboardLanguage.german.rawValue).isEmpty else {
            throw ReplayError("Hex's never-suggest.tsv or de.capitals next to keyboard-replay is invalid; run build.sh again")
        }
    }

    private static func isValid(_ text: String, type: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }
        return !lines.isEmpty && lines.allSatisfy { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if type == "capitals" {
                return fields.count == 2 && !fields[0].isEmpty && UInt8(fields[1]).map { $0 <= 100 } == true
            }
            return fields.count == 3 && !fields[0].isEmpty && ["slur", "swear"].contains(fields[1]) && !fields[2].isEmpty
        }
    }

    static func hexLanguages(_ word: TypingLogWord) -> (current: KeyboardLanguage, partner: KeyboardLanguage?)? {
        let codes = Set(word.languages)
        let german = codes.contains(KeyboardLanguage.german.rawValue)
        let english = codes.contains(KeyboardLanguage.english.rawValue)
        guard german || english else { return nil }
        let current: KeyboardLanguage = german && (!english || word.layout?.letters == "qwertz") ? .german : .english
        let other: KeyboardLanguage = current == .german ? .english : .german
        return (current, codes.contains(other.rawValue) ? other : nil)
    }

    static func hexPoint(_ tap: TypingLogTap, from typr: TyprKeyboardLayout, keys: TypingDecoder.Keys) -> CGPoint? {
        guard let x = tap.x, let y = tap.y else { return nil }
        let point = CGPoint(x: x, y: y)
        let text = tap.key ?? tap.text.lowercased()
        if text == " " {
            guard let hex = keys.space, let space = typr.key(.space, nearest: point)?.frame else { return nil }
            return TyprAutocorrectAdapter.spacePoint(point, from: space, to: hex)
        }
        guard text.count == 1, let letter = text.first, let key = typr.key(.character(text), nearest: point) else { return nil }
        return TyprAutocorrectAdapter.hexPoint(point, letter: letter, keys: keys, from: key, in: typr)
    }

    func hexEngine(target: HexReplayTarget, width: CGFloat, landscape: Bool, showsStrip: Bool,
                   languages: (current: KeyboardLanguage, partner: KeyboardLanguage?))
        -> (FullKeyboardEngine, AutocorrectEngine, HexLexiconChecker, HexLexiconChecker?) {
        let checker = HexLexiconChecker(words.lexicons, language: languages.current)
        let partnerChecker = languages.partner.map { HexLexiconChecker(words.lexicons, language: $0) }
        let autocorrect = AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: nil))
        let engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = width
        engine.orientation = landscape ? .landscape : .portrait
        engine.showsStrip = showsStrip
        engine.language = languages.current
        autocorrect.setPartner(languages.partner, available: UITextChecker.availableLanguages, checker: partnerChecker)
        engine.configureForField()
        let settings = FullKeyboardSettings(defaults: nil)
        let model = settings.typingModel(for: languages.current)
        engine.letterOdds = model
        if settings.spatialAutocorrect {
            autocorrect.decoder = model.map { TypingDecoder(model: $0) }
            autocorrect.partnerDecoder = languages.partner.flatMap(settings.typingModel(for:)).map { TypingDecoder(model: $0) }
        }
        engine.tapOffsets = TypingDecoder.offsets(from: [:], layout: engine.layout)
        return (engine, autocorrect, checker, partnerChecker)
    }

    func tapMappingReport() throws -> String {
        var report: [String: [String: Double]] = [:]
        for language in [KeyboardLanguage.english, .german] {
            let typr = TyprAutocorrectEngine(checker: LexiconChecker(nil), learning: KeyboardLearningSession(store: nil, defaults: nil),
                                             spatialDecoder: nil)
            let adapter = TyprAutocorrectAdapter(engine: typr, makeGerman: { GermanAutocorrect(checker: nil) })
            let app = FullKeyboardEngine(target: HexReplayTarget(text: ""), autocorrect: adapter)
            app.width = 393
            app.language = language
            app.configureForField()
            let replay = hexEngine(target: HexReplayTarget(text: ""), width: 393, landscape: false, showsStrip: true,
                                   languages: (language, nil)).1
            guard let appKeys = adapter.decoderBaselineKeys ?? adapter.decoderKeys, let appSpace = appKeys.space,
                  let keys = replay.decoderBaselineKeys ?? replay.decoderKeys else {
                throw ReplayError("Hex's keys are unknown")
            }
            var taps = 0.0, unmapped = 0.0, maxError = 0.0
            func check(_ point: CGPoint, text: String, logged: (point: CGPoint?, key: String?, layout: TyprKeyboardLayout)) {
                guard let p = logged.point, let layout = TypingLogLayout(logged.layout).keyboardLayout,
                      let back = Self.hexPoint(TypingLogTap(t: 0, x: p.x, y: p.y, key: logged.key, text: text),
                                               from: layout, keys: keys) else { unmapped += 1; return }
                taps += 1
                maxError = max(maxError, hypot(back.x - point.x, back.y - point.y))
            }
            for (letter, centre) in appKeys.centres {
                for dx in [-9.0, 0, 7] {
                    for dy in [-8.0, 0, 6] {
                        let point = CGPoint(x: centre.x + dx, y: centre.y + dy)
                        check(point, text: String(letter), logged: adapter.typingLogTap(point, text: String(letter)))
                    }
                }
            }
            for dx in [-40.0, 0, 25] {
                let point = CGPoint(x: appSpace.midX + dx, y: appSpace.midY + 5)
                let space = adapter.typingLogSpace(point)
                check(point, text: " ", logged: (space.point, nil, space.layout))
            }
            report[language.rawValue] = ["taps": taps, "unmapped": unmapped, "maxError": maxError]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }

    func replayHex(_ word: TypingLogWord, _ prepared: PreparedWord, context: String) -> Result<ReplayedWord, SkipReason> {
        guard let logged = word.layout, let typr = logged.keyboardLayout else { return .failure(.unknownLayout) }
        guard let languages = Self.hexLanguages(word) else { return .failure(.noHexLanguage) }
        let target = HexReplayTarget(text: context)
        var now: TimeInterval = 1_000
        let hex = hexEngine(target: target, width: typr.width, landscape: typr.orientation == .landscape,
                            showsStrip: logged.showsStrip, languages: languages)
        let (engine, autocorrect, checker, partnerChecker) = hex
        engine.clock = { now }
        guard let keys = autocorrect.decoderBaselineKeys ?? autocorrect.decoderKeys else { return .failure(.noHexKey) }

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
                guard let point = Self.hexPoint(tap, from: typr, keys: keys) else { return .failure(.noHexKey) }
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
        for recorder in [checker] + (partnerChecker.map { [$0] } ?? []) { recorder.recording = true }
        func deviated() -> Bool { checker.deviated || partnerChecker?.deviated == true }
        switch prepared.plan.end {
        case .none:
            return .success(ReplayedWord(literal: literal, committed: literal))
        case .separator(let separator):
            guard press(separator == "\n" ? .returnKey : .space) else { return .failure(.noHexKey) }
            if deviated() { return .failure(.systemSpelling) }
        case .pick(let to, let chip):
            engine.refreshSuggestions()
            if deviated() { return .failure(.systemSpelling) }
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
