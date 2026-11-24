import CoreGraphics
import UIKit

/// Typr's typing log (`TypingLogRecorder`) on Hex's keys, with Typr typing on: the words Typr's
/// keyboard keeps while its learning is on, with taps on Typr's own layout for replay.
extension FullKeyboardEngine {
    private var typrTyping: TyprAutocorrectAdapter? { autocorrect as? TyprAutocorrectAdapter }

    /// Where Typr's keyboard records: prose fields that allow autocorrection, never secure, URL or
    /// email fields, and only while learning is on. Anywhere else drops open words.
    private var typrTypingLogAllowed: Bool {
        guard let typr = typrTyping else { return false }
        return field == .text && target.isSecureTextEntry != true && target.autocorrectionType != .no
            && typr.engine.learning.isLearningEnabled
    }

    func logTyprTyping(_ event: (TypingLogRecorder) -> Void) {
        guard let typrTypingLog else { return }
        guard typrTypingLogAllowed, let typr = typrTyping else { typrTypingLog.discard(); return }
        typrTypingLog.languages = typr.engine.suggestionLanguages.map(\.rawValue).sorted()
        event(typrTypingLog)
    }

    /// A key's text went in; `point` is its tap as on the unsplit keyboard.
    func logTyprTyped(_ text: String, at point: CGPoint?) {
        guard typrTypingLog != nil, let typr = typrTyping else { return }
        if text.isEmpty || text == " " || text == "\n" || (text.count == 1 && text.first.map(Self.wordEnders.contains) == true) {
            logTyprTyping { $0.boundary(Self.typrTypingLogEnding(text)) }
            return
        }
        let tap = typr.typingLogTap(point, text: text)
        logTyprTyping {
            $0.typed(text, point: tap.point, key: tap.key, layout: tap.layout, time: clock(), field: textBefore)
        }
    }

    /// The user left the word without a separator (field change, host edit, cursor, dismissal).
    func endTyprTypingLogWord(_ reason: String) {
        guard let typrTypingLog else { return }
        if typrTyping?.engine.learning.isLearningEnabled == true { typrTypingLog.end(reason) } else { typrTypingLog.discard() }
    }

    /// Which decision made the automatic change Typr typing is waiting feedback on.
    var typrTypingLogCorrection: TypingLogWord.Commit.CorrectionKind? { typrTyping?.engine.typingLogCorrection }

    /// A held space (`holdsTypedSpace`) types nothing yet, but ends the word as a space.
    static func typrTypingLogEnding(_ ending: String) -> String { ending.isEmpty ? " " : ending }

    static func typrTypingLogChip(_ kind: KeyboardSuggestion.Kind) -> String {
        switch kind {
        case .keepLiteral: "keep"
        case .primary: "primary"
        default: "secondary"
        }
    }
}
