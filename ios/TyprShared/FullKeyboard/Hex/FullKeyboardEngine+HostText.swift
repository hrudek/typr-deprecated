import Foundation
import UIKit

// Hex's text-target protocol only; Hex's document proxy target and engine host text arrive with Hex's engine.
/// The text field the keys type into. `UITextDocumentProxy` in the keyboard; a fake in tests.
@MainActor
protocol KeyboardTextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var hasText: Bool { get }
    var autocapitalizationType: UITextAutocapitalizationType? { get }
    var autocorrectionType: UITextAutocorrectionType? { get }
    var keyboardType: UIKeyboardType? { get }
    var returnKeyType: UIReturnKeyType? { get }
    var enablesReturnKeyAutomatically: Bool? { get }
    var keyboardAppearance: UIKeyboardAppearance? { get }
    var textContentType: UITextContentType? { get }
    var isSecureTextEntry: Bool? { get }
    var smartQuotesType: UITextSmartQuotesType? { get }
    var smartDashesType: UITextSmartDashesType? { get }
    var selectedText: String? { get }
    /// `UITextDocumentProxy.documentIdentifier`: the field, where UIKit names it.
    var documentIdentifier: UUID? { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
}

extension KeyboardTextTarget {
    var autocorrectionType: UITextAutocorrectionType? { .default }
    var enablesReturnKeyAutomatically: Bool? { false }
    var textContentType: UITextContentType? { nil }
    var isSecureTextEntry: Bool? { nil }
    var selectedText: String? { nil }
    var documentIdentifier: UUID? { nil }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
