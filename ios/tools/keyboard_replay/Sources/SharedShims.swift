import Foundation
import UIKit

// Stand-ins for shared files that need app-only frameworks.

/// KeyboardBridge.swift needs SwiftUI and Metal. Only default arguments name the App Group, and the
/// replay passes its own; this suite keeps any accidental use away from Typr's data.
enum KeyboardBridge {
    nonisolated static let appGroup = "dev.rudek.typr.keyboard-replay"
}

/// TyprAccentPicker.swift also holds a UIKit view. Only the key view opens accent menus, which the
/// replay never does; with no options no menu opens.
nonisolated enum TyprAccentCatalog {
    static let periodKey: [String] = []
    static func options(for base: String, uppercase: Bool) -> [String]? { nil }
}

nonisolated struct TyprAccentMenu: Equatable, Sendable {
    let options: [String]
    var selectedIndex: Int
    var selectedOption: String { options[selectedIndex] }

    static func build(for keyFrame: CGRect, rawOptions: [String], in layoutWidth: CGFloat,
                      horizontalInset: CGFloat = 0) -> TyprAccentMenu {
        TyprAccentMenu(options: rawOptions, selectedIndex: 0)
    }

    func index(for x: CGFloat) -> Int { selectedIndex }
}

@MainActor
final class SwipeTrailView {
    var isShowing: Bool { false }
    func begin(_ start: [CGPoint]) {}
    func add(_ point: CGPoint) {}
    func fade() {}
    func clear() {}
}

nonisolated enum TypingLogTraits {
    @MainActor static func documentIdentifier(of proxy: UITextDocumentProxy) -> UUID? { nil }
    static func name<Trait>(_ trait: Trait) -> String { "\(trait)" }
}

@MainActor
final class TypingLogger {
    func context(_ why: String, force: Bool = false) {}
    func edit(_ op: String, _ fields: [TypingLogField] = []) {}
    func ui(_ action: String, _ fields: [TypingLogField] = []) {}
    func touch(_ phase: TypingLogTouchPhase, id: Int, sample: TypingLogTouchSample, key: KeyboardKey?, under: KeyboardKey? = nil) {}
    func keyboardState(layout: KeyboardLayout, shift: ShiftStateMachine, cause: String) {}
    func viewGeometry(size: CGSize, safeArea: UIEdgeInsets) {}
    func commitGeometry() {}
    func suggestionsChanged(_ suggestions: [KeyboardSuggestion]) {}
    static func candidates(_ suggestions: [KeyboardSuggestion]) -> TypingLogValue { .string("") }
    nonisolated static func keyID(_ kind: KeyKind) -> String { "" }
}

nonisolated enum TypingLogTouchPhase { case began, moved, ended, cancelled }

nonisolated struct TypingLogTouchSample {
    var point: CGPoint
    var timestamp: TimeInterval
}

nonisolated enum KeyboardTheme: String, CaseIterable, Sendable {
    case automatic, black, white, navy, forest, ember
}
