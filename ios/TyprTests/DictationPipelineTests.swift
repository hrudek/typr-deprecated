import XCTest
@testable import Typr

/// `DictationPipeline`, which the app and in-keyboard dictation share: Hex's order and the Typr
/// variants.
@MainActor
final class DictationPipelineTests: XCTestCase {
    private let thin = "\u{202F}"

    func testVocabularyCasingSurvivesTheStyle() async {
        let pipeline = DictationPipeline(style: .polished, language: "en-US", vocabulary: ["iPhone"])
        let stages = await pipeline.run("iphone works")
        XCTAssertEqual(stages.spelled, "iPhone works")
        XCTAssertTrue(stages.formatted.hasPrefix("iPhone works"), stages.formatted)
    }

    func testLearnedFixesComeFirst() async {
        let fix = DictationCorrection(heard: "wal", meant: "Wahl", caseIsKnown: true)
        let pipeline = DictationPipeline(style: .polished, language: "de-DE", corrections: [fix])
        let stages = await pipeline.run("die wal ist morgen")
        XCTAssertEqual(stages.spelled, "die Wahl ist morgen")
        XCTAssertEqual(stages.formatted, pipeline.format("die Wahl ist morgen", language: "de-DE"))
    }

    /// Verbatim keeps the model's words with the vocabulary's spellings; as in Hex, Lowercase
    /// still applies.
    func testVerbatimKeepsTheWordsAndLowercaseStillApplies() async {
        var pipeline = DictationPipeline(style: .verbatim, language: "en-US", vocabulary: ["GitHub"])
        var stages = await pipeline.run("um push to github")
        XCTAssertEqual(stages.formatted, "um push to GitHub")
        pipeline.lowercase = true
        stages = await pipeline.run("um push to github")
        XCTAssertEqual(stages.formatted, "um push to github")
    }

    /// `refine` sees the spelled text and its terms; a translation is formatted in its own
    /// language, French spacing included.
    func testRefineAndTranslationRunInHexOrder() async {
        let pipeline = DictationPipeline(style: .polished, language: "en-US", vocabulary: ["GitHub"])
        var refined: [String] = []
        var terms: [[String]] = []
        var translated: [String] = []
        let stages = await pipeline.run(
            "do you come to github",
            refine: { text, cleanupTerms in
                refined.append(text)
                terms.append(cleanupTerms)
                return text + " tonight"
            },
            translate: { text in
                translated.append(text)
                return .translated("tu viens sur GitHub ce soir ?", language: "fr-FR")
            }
        )
        XCTAssertEqual(refined, ["do you come to GitHub"])
        XCTAssertEqual(terms.first?.first, "GitHub")
        XCTAssertEqual(translated, ["do you come to GitHub tonight"])
        XCTAssertEqual(stages.translated, "tu viens sur GitHub ce soir ?")
        XCTAssertEqual(stages.formatted, pipeline.format("tu viens sur GitHub ce soir ?", language: "fr-FR"))
        XCTAssertTrue(stages.formatted.hasSuffix("soir\(thin)?"), stages.formatted)
    }

    func testAsSpokenFormatsInTheDictationLanguage() async {
        let pipeline = DictationPipeline(style: .polished, language: "en-US")
        let stages = await pipeline.run("see you tomorrow", translate: { _ in .asSpoken })
        XCTAssertNil(stages.translated)
        XCTAssertEqual(stages.formatted, pipeline.format("see you tomorrow", language: "en-US"))
    }

    /// Chinese is written without spaces and ends with "。" (Hex's CJK rules).
    func testChineseKeepsItsPunctuation() async {
        var pipeline = DictationPipeline(style: .polished, language: "zh-CN", formatLists: true)
        pipeline.endsWithPeriod = false
        XCTAssertEqual(pipeline.format("首先，买牛奶。其次，给妈妈打电话。", language: "zh-CN"), "首先，买牛奶。其次，给妈妈打电话")
    }

    /// Typr's Automatic: German unless the text reads as English.
    func testAutomaticLanguageReadsTheText() {
        XCTAssertEqual(DictationPipeline.resolved(nil, for: "Ich komme morgen"), "de")
        XCTAssertEqual(DictationPipeline.resolved(nil, for: "let's ship the build tonight"), "en")
        XCTAssertEqual(DictationPipeline.resolved("fr-FR", for: "let's ship"), "fr-FR")
        XCTAssertEqual(DictationLanguage(formattingLanguage: "de-AT"), .german)
        XCTAssertEqual(DictationLanguage(formattingLanguage: "en-US"), .english)
        XCTAssertEqual(DictationLanguage(formattingLanguage: "fr-FR"), .automatic)
        XCTAssertEqual(DictationLanguage(formattingLanguage: nil), .automatic)
        XCTAssertNil(DictationLanguage.automatic.formattingIdentifier)
        XCTAssertEqual(DictationLanguage.german.formattingIdentifier, "de")
    }

    /// Off by default: Hex's styles and rules. On, Typr's formatter and German lists.
    func testTyprVariantsSelectTyprsFormatterAndRules() {
        let suite = "pipeline.variants.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        let vocabulary = DictationVocabulary(userTerms: [])
        let heard = "Einkaufsliste: erstens Milch, zweitens Eier."
        func pipeline(_ style: DictationStyle = .polished) -> DictationPipeline {
            DictationPipeline(style: style, language: .german, vocabulary: vocabulary, settings: settings)
        }

        XCTAssertFalse(pipeline().typrStyles)
        XCTAssertFalse(pipeline().typrFormattingRules)
        XCTAssertTrue(pipeline().formatLists, "Hex's Format lists is on by default")
        XCTAssertTrue(pipeline().spokenPunctuation, "Hex's Spoken punctuation is on by default")
        XCTAssertEqual(pipeline().format(heard, language: "de"), heard, "Hex writes no German lists")
        XCTAssertEqual(pipeline().format(heard, language: "de"),
                       TranscriptFormatter.format(heard, style: .polished, language: "de", lists: true, punctuation: true))

        settings[experiment: .typrGermanFormattingRules] = true
        XCTAssertFalse(pipeline().formatLists, "the old experiment switches Typr's rules, off by default")
        settings[experiment: .formatLists] = true
        let listed = pipeline().format(heard, language: "de")
        XCTAssertTrue(listed.contains("\n1. Milch") && listed.contains("\n2. Eier"), listed)

        settings[experiment: .typrDictationStyles] = true
        XCTAssertEqual(pipeline(.typrCasual).style, .typrCasual)
        XCTAssertEqual(pipeline(.casual).format("Ich komme. Du auch.", language: "de"),
                       TyprTranscriptFormatter.format("Ich komme. Du auch.", style: .casual, language: .german,
                                                      lists: true, punctuation: false))
    }

    /// Typr fix on the Hex base: German abbreviations end no sentence, on the default path.
    func testGermanAbbreviationsOnTheDefaultPath() {
        let suite = "pipeline.abbreviations.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        func format(_ text: String) -> String {
            DictationPipeline(style: .polished, language: .german, vocabulary: DictationVocabulary(userTerms: []),
                              settings: settings).format(text, language: "de")
        }
        XCTAssertEqual(format("das dauert ca. zehn Minuten"), "Das dauert ca. zehn Minuten.")
        XCTAssertEqual(format("exportiert werden, bzw. in die Zwischenablage kopiert"),
                       "Exportiert werden, bzw. in die Zwischenablage kopiert.")
        XCTAssertEqual(format("zum Beispiel z. B. die Logs, d. h. alle"), "Zum Beispiel z. B. die Logs, d. h. alle.")
        XCTAssertEqual(format("Logs, Daten usw. kommen später"), "Logs, Daten usw. kommen später.")
        // Real sentence ends still capitalize, and nothing is lowercased.
        XCTAssertEqual(format("das ist gut. danach weiter"), "Das ist gut. Danach weiter.")
        XCTAssertEqual(format("bzw. Das bleibt"), "Bzw. Das bleibt.")

        settings.dictationEndsWithPeriod = false
        for text in ["Das dauert ca.", "Das ist z. B.", "Bring Brot usw.", "Heute bzw."] {
            XCTAssertEqual(format(text), text)
        }
        XCTAssertEqual(format("Das ist gut."), "Das ist gut")
    }
}
