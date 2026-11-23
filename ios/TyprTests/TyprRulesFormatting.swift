@testable import Typr

extension TranscriptFormatter {
    /// Hex's styles with Typr German formatting rules, in `language` as `DictationPipeline`
    /// resolves it (Automatic: English when the text reads as English, else German).
    static func typrRules(
        _ raw: String,
        style: DictationStyle,
        language: DictationLanguage = .automatic,
        lists: Bool = false,
        punctuation: Bool = false,
        endsWithPeriod: Bool = true
    ) -> String {
        format(raw, style: style, language: DictationPipeline.resolved(language.formattingIdentifier, for: raw),
               lists: lists, punctuation: punctuation, endsWithPeriod: endsWithPeriod, rules: .typr)
    }
}
