import CoreGraphics
import UIKit

extension FullKeyboardEngine {
    private var typrTyping: TyprAutocorrectAdapter? { autocorrect as? TyprAutocorrectAdapter }

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

    func logTyprSpace(at point: CGPoint) {
        guard typrTypingLog != nil, let typr = typrTyping else { return }
        let space = typr.typingLogSpace(point)
        logTyprTyping { $0.spaceTapped(at: space.point, layout: space.layout, time: clock()) }
    }

    func endTyprTypingLogWord(_ reason: String) {
        guard let typrTypingLog else { return }
        if typrTyping?.engine.learning.isLearningEnabled == true { typrTypingLog.end(reason) } else { typrTypingLog.discard() }
    }

    var typrTypingLogCorrection: TypingLogWord.Commit.CorrectionKind? { typrTyping?.engine.typingLogCorrection }

    static func typrTypingLogEnding(_ ending: String) -> String { ending.isEmpty ? " " : ending }

    static func typrTypingLogChip(_ kind: KeyboardSuggestion.Kind) -> String {
        switch kind {
        case .keepLiteral: "keep"
        case .primary: "primary"
        default: "secondary"
        }
    }
}
