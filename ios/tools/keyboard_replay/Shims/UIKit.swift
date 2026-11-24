@_exported import Foundation
@_exported import CoreGraphics

// The UIKit names the shared keyboard sources mention; the replay never reaches UIKit behavior.

public enum UITextAutocapitalizationType: Sendable { case none, words, sentences, allCharacters }
public enum UITextAutocorrectionType: Sendable { case `default`, no, yes }
public enum UITextInlinePredictionType: Sendable { case `default`, no, yes }
public enum UITextSmartQuotesType: Sendable { case `default`, no, yes }
public enum UITextSmartDashesType: Sendable { case `default`, no, yes }
public enum UITextSmartInsertDeleteType: Sendable { case `default`, no, yes }
public enum UITextSpellCheckingType: Sendable { case `default`, no, yes }
public enum UIKeyboardType: Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad
    case emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}
public enum UIReturnKeyType: Sendable {
    case `default`, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`
}
public enum UIKeyboardAppearance: Sendable { case `default`, dark, light }
public struct UITextContentType: Hashable, Sendable {
    public let rawValue: String
    public static let oneTimeCode = UITextContentType(rawValue: "one-time-code")
    public static let password = UITextContentType(rawValue: "password")
    public static let newPassword = UITextContentType(rawValue: "newPassword")
    public static let username = UITextContentType(rawValue: "username")
    public static let emailAddress = UITextContentType(rawValue: "emailAddress")
    public static let URL = UITextContentType(rawValue: "URL")
    public static let creditCardNumber = UITextContentType(rawValue: "creditCardNumber")
    public static let telephoneNumber = UITextContentType(rawValue: "telephoneNumber")
}

public struct UIEdgeInsets: Equatable, Sendable {
    public var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    public static let zero = UIEdgeInsets()
}

public struct UILexiconEntry {
    public let userInput: String
    public let documentText: String
}

public final class UILexicon {
    public let entries: [UILexiconEntry] = []
}

/// System spelling is unavailable here; the replay injects its own checkers. The listed languages are
/// the ones it has word lists for, so Hex sets up autocorrect for German and English.
public final class UITextChecker {
    public static let availableLanguages = ["de_DE", "en_US"]
    public init() {}
    public func rangeOfMisspelledWord(in string: String, range: NSRange, startingAt: Int, wrap: Bool,
                                      language: String) -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }
    public func guesses(forWordRange range: NSRange, in string: String, language: String) -> [String]? { nil }
    public func completions(forPartialWordRange range: NSRange, in string: String, language: String) -> [String]? {
        nil
    }
}

@MainActor
public protocol UITextDocumentProxy: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    var hasText: Bool { get }
    var autocapitalizationType: UITextAutocapitalizationType { get }
    var autocorrectionType: UITextAutocorrectionType { get }
    var isSecureTextEntry: Bool { get }
    var keyboardType: UIKeyboardType { get }
    var inlinePredictionType: UITextInlinePredictionType { get }
    var returnKeyType: UIReturnKeyType { get }
    var enablesReturnKeyAutomatically: Bool { get }
    var keyboardAppearance: UIKeyboardAppearance { get }
    var textContentType: UITextContentType? { get }
    var smartQuotesType: UITextSmartQuotesType { get }
    var smartDashesType: UITextSmartDashesType { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
}

/// Only the trackpad measures text, and the replay never moves the cursor.
public final class UIFont: Equatable, Sendable {
    public enum TextStyle: Sendable { case body }
    public let pointSize: CGFloat
    public var lineHeight: CGFloat { pointSize * 1.2 }
    init(pointSize: CGFloat) { self.pointSize = pointSize }
    public static func systemFont(ofSize size: CGFloat) -> UIFont { UIFont(pointSize: size) }
    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont { UIFont(pointSize: 17) }
    public static func == (a: UIFont, b: UIFont) -> Bool { a.pointSize == b.pointSize }
}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
}

extension NSString {
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize {
        CGSize(width: CGFloat(length) * 9, height: 17)
    }
}
