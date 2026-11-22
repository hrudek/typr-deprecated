import UIKit
@testable import Typr

/// Hex's `FixtureTextTarget` (HEXMobile/FullKeyboardSnapshotStage.swift), renamed beside Typr's own; Hex's engine tests type into it.
@MainActor
class HexFixtureTextTarget: KeyboardTextTarget {
    private(set) var text: String
    private(set) var cursorIndex: Int
    let keyboardAppearance: UIKeyboardAppearance?
    var autocapitalizationType: UITextAutocapitalizationType? = .sentences
    var autocorrectionType: UITextAutocorrectionType? = .default
    var keyboardType: UIKeyboardType? = .default
    var returnKeyType: UIReturnKeyType? = .default
    var enablesReturnKeyAutomatically: Bool? = false
    var smartQuotesType: UITextSmartQuotesType?
    var smartDashesType: UITextSmartDashesType?
    var selectedText: String?
    var documentIdentifier: UUID?
    /// Simulates a host whose window reports no text after the cursor.
    var hidesAfterText = false

    init(text: String = "", appearance: UIKeyboardAppearance? = nil) {
        self.text = text
        self.cursorIndex = text.count
        keyboardAppearance = appearance
    }

    var documentContextBeforeInput: String? {
        let clamped = max(0, min(text.count, cursorIndex))
        let idx = text.index(text.startIndex, offsetBy: clamped)
        return String(text[..<idx])
    }

    var documentContextAfterInput: String? {
        hidesAfterText ? nil : String(text.dropFirst(max(0, min(text.count, cursorIndex))))
    }

    var hasText: Bool { !text.isEmpty }

    func insertText(_ inserted: String) {
        let clamped = max(0, min(text.count, cursorIndex))
        let idx = text.index(text.startIndex, offsetBy: clamped)
        text.insert(contentsOf: inserted, at: idx)
        cursorIndex = clamped + inserted.count
    }

    func deleteBackward() {
        let clamped = max(0, min(text.count, cursorIndex))
        guard clamped > 0 else { return }
        let removeIdx = text.index(text.startIndex, offsetBy: clamped - 1)
        text.remove(at: removeIdx)
        cursorIndex = clamped - 1
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorIndex = max(0, min(text.count, cursorIndex + offset))
    }
}
