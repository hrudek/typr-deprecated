import Foundation

/// An error Typr wrote for people: its description is shown as it is. Every other error's
/// description (Apple's, Foundation's, a package's) is for logs, however readable it looks:
/// Speech's "transcription.ru asset not found after attempted download." reads as a sentence.
protocol HexDescribedError: LocalizedError {}

extension Locale {
    /// The language Typr's own words are in: the app's localization, else English.
    static var typrInterface: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
