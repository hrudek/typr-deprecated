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

/// SwipeTyping.swift ends with this CoreAnimation view; build.sh drops it there. The replay never swipes.
@MainActor
final class SwipeTrailView {
    var isShowing: Bool { false }
    func begin(_ start: [CGPoint]) {}
    func add(_ point: CGPoint) {}
    func fade() {}
    func clear() {}
}

/// TypingLogSession.swift reads UIKit's input traits by reflection. Hex's own typing log is never
/// connected in the replay, and it has no host proxy.
nonisolated enum TypingLogTraits {
    @MainActor static func documentIdentifier(of proxy: UITextDocumentProxy) -> UUID? { nil }
    static func name<Trait>(_ trait: Trait) -> String { "\(trait)" }
}

/// Hex's own typing log (TypingLogger.swift, TypingLogSession.swift) reads UIKit touches and traits.
/// The replay never connects it, so the engine's calls into it are no-ops.
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

/// KeyboardTheme.swift holds UIKit colours; settings only store the theme's name.
nonisolated enum KeyboardTheme: String, CaseIterable, Sendable {
    case automatic, black, white, navy, forest, ember
}
