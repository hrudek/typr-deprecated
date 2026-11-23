import UIKit


/// The keyboard's text target while the emoji panel is up: the field, or the emoji search's
/// query while you search, so the letter keys type into the search instead of the field.
@MainActor
final class EmojiRoutedTarget: KeyboardTextTarget {
    let document: KeyboardTextTarget
    /// Set while searching; the keys type here.
    var query: String?
    /// Return while searching.
    var onSearchReturn: (() -> Void)?

    init(document: KeyboardTextTarget) {
        self.document = document
    }

    var isSearching: Bool { query != nil }

    var documentContextBeforeInput: String? { query ?? document.documentContextBeforeInput }
    var documentContextAfterInput: String? { isSearching ? nil : document.documentContextAfterInput }
    var hasText: Bool { query.map { !$0.isEmpty } ?? document.hasText }
    var autocapitalizationType: UITextAutocapitalizationType? { isSearching ? UITextAutocapitalizationType.none : document.autocapitalizationType }
    var autocorrectionType: UITextAutocorrectionType? { isSearching ? .no : document.autocorrectionType }
    var keyboardType: UIKeyboardType? { isSearching ? .default : document.keyboardType }
    var returnKeyType: UIReturnKeyType? { isSearching ? .done : document.returnKeyType }
    var enablesReturnKeyAutomatically: Bool? { isSearching ? false : document.enablesReturnKeyAutomatically }
    var keyboardAppearance: UIKeyboardAppearance? { document.keyboardAppearance }
    var textContentType: UITextContentType? { isSearching ? nil : document.textContentType }
    /// Typr: a secure field stays secure while you search, so nothing typed there is learned.
    var isSecureTextEntry: Bool? { document.isSecureTextEntry }
    var smartQuotesType: UITextSmartQuotesType? { isSearching ? .no : document.smartQuotesType }
    var smartDashesType: UITextSmartDashesType? { isSearching ? .no : document.smartDashesType }
    var selectedText: String? { isSearching ? nil : document.selectedText }
    var documentIdentifier: UUID? { document.documentIdentifier }

    func insertText(_ text: String) {
        guard let current = query else {
            document.insertText(text)
            return
        }
        if text.contains("\n") {
            onSearchReturn?()
        } else {
            query = current + text
        }
    }

    func deleteBackward() {
        guard var current = query else {
            document.deleteBackward()
            return
        }
        if !current.isEmpty { current.removeLast() }
        query = current
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard !isSearching else { return }
        document.adjustTextPosition(byCharacterOffset: offset)
    }
}
