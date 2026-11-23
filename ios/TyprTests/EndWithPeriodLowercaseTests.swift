import XCTest
@testable import Typr

final class EndWithPeriodLowercaseTests: XCTestCase {
    private static let germanInputs = [
        "ich komme morgen",
        "Kommst du morgen?",
        "Ich komme. Du auch.",
        "Wir treffen uns um 13 Uhr bzw. später.",
        "Bring Brot, Milch usw.",
        "Das ist z. B. so.",
        "Er sagte „Hallo.“",
        "Warte...",
        "Einkaufsliste: erstens Milch, zweitens Eier.",
        "Hallo bullet Milch. bullet Brot.",
        "Ich treffe Anna im Büro. Danach komme ich.\nGegen 13 Uhr bin ich zurück.",
    ]

    private static let englishInputs = [
        "see you tomorrow",
        "Are you coming?",
        "We met in the U.S.",
        "Bring pens, paper etc.",
        "That's great!",
        "My list: first milk, second eggs.",
        "Sounds good. See you tomorrow.\nBring the keys.",
    ]

    func testOnKeepsEveryStyleAsBefore() {
        for raw in Self.germanInputs + Self.englishInputs {
            for style in DictationStyle.allCases {
                for lists in [false, true] {
                    XCTAssertEqual(
                        TranscriptFormatter.typrRules(raw, style: style, lists: lists, endsWithPeriod: true),
                        TranscriptFormatter.typrRules(raw, style: style, lists: lists),
                        "\(style) \(raw)"
                    )
                }
            }
        }
    }

    func testOffLeavesVerbatimUnchanged() {
        for raw in Self.germanInputs + Self.englishInputs {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: .verbatim, endsWithPeriod: false),
                           TranscriptFormatter.typrRules(raw, style: .verbatim), raw)
        }
    }

    func testOffDropsTheFinalPeriodInGerman() {
        let cases: [(String, DictationStyle, String)] = [
            ("ich komme morgen", .polished, "Ich komme morgen"),
            ("Ich komme. Du auch.", .polished, "Ich komme. Du auch"),
            ("Ich komme. Du auch.", .notes, "- Ich komme\n- Du auch"),
            ("Ich komme. Du auch.", .casual, "ich komme. du auch"),
            ("Wir treffen uns um 13 Uhr bzw. später.", .polished, "Wir treffen uns um 13 Uhr bzw. später"),
            ("Er sagte „Hallo.“", .notes, "Er sagte „Hallo.“"),
            ("Hallo bullet Milch. bullet Brot.", .notes, "Hallo\n- Milch\n- Brot"),
            ("Ich treffe Anna im Büro. Danach komme ich.\nGegen 13 Uhr bin ich zurück.", .polished,
             "Ich treffe Anna im Büro. Danach komme ich\nGegen 13 Uhr bin ich zurück"),
        ]
        for (raw, style, expected) in cases {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: style, language: .german, endsWithPeriod: false),
                           expected, "\(style) \(raw)")
        }
    }

    func testOffKeepsQuestionsExclamationsEllipsesAndAbbreviationsInGerman() {
        let cases: [(String, DictationStyle, String)] = [
            ("Kommst du morgen?", .polished, "Kommst du morgen?"),
            ("Hallo! Bis gleich!", .polished, "Hallo! Bis gleich!"),
            ("Warte...", .polished, "Warte..."),
            ("Warte…", .notes, "Warte…"),
            ("Bring Brot, Milch usw.", .polished, "Bring Brot, Milch usw."),
            ("Bring Brot, Milch usw.", .notes, "Bring Brot, Milch usw."),
            ("Frag bitte Dr.", .polished, "Frag bitte Dr."),
            ("Das gilt auch für Teile, Schrauben o. ä.", .polished, "Das gilt auch für Teile, Schrauben o. ä."),
        ]
        for (raw, style, expected) in cases {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: style, language: .german, endsWithPeriod: false),
                           expected, "\(style) \(raw)")
        }
    }

    func testOffDropsTheFinalPeriodInEnglish() {
        let cases: [(String, DictationStyle, String)] = [
            ("see you tomorrow", .polished, "See you tomorrow"),
            ("Sounds good. See you tomorrow.", .polished, "Sounds good. See you tomorrow"),
            ("Sounds good. See you tomorrow.", .notes, "- Sounds good\n- See you tomorrow"),
            ("She said \"hi.\"", .notes, "She said \"hi\""),
            ("Are you coming?", .polished, "Are you coming?"),
            ("That's great!", .notes, "That's great!"),
            ("We met in the U.S.", .polished, "We met in the U.S."),
            ("Bring pens, paper etc.", .polished, "Bring pens, paper etc."),
            ("Use a fork, e.g.", .notes, "Use a fork, e.g."),
        ]
        for (raw, style, expected) in cases {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: style, language: .english, endsWithPeriod: false),
                           expected, "\(style) \(raw)")
        }
    }

    /// Typr fix on the Hex base: an abbreviation's or initialism's period stays, inside quotes and
    /// brackets too.
    func testOffKeepsAbbreviationsAndInitialismsInsideQuotesAndBrackets() {
        let german = [
            "Wir waren in den (U.S.)", "Wir waren in den \"U.S.\"", "Er sagte „U.S.“", "Sie schrieb «U.S.»",
            "Er sagte ‚z.B.‘", "Das ist ein Beispiel (z.B.)", "Das heißt „d.h.“", "Das heißt [d.h.]",
            "Brot, Milch (usw.)", "Brot, Milch „usw.“", "Morgen oder übermorgen (bzw.)", "Frag bitte „Dr.“",
            "Das ist z.B.", "Das ist d.h.", "Bring Brot usw.", "Heute bzw.", "Frag Dr.",
        ]
        let english = ["We met in the (U.S.)", "She wrote \"e.g.\"", "Bring pens ('etc.')", "We met in the U.S."]
        for style in [DictationStyle.polished, .notes] {
            for (texts, language) in [(german, DictationLanguage.german), (english, .english)] {
                for text in texts {
                    XCTAssertEqual(TranscriptFormatter.typrRules(text, style: style, language: language, endsWithPeriod: false),
                                   text, "\(style) \(text)")
                }
            }
        }
    }

    /// Typr fix on the Hex base: in German, Notes splits no sentence at an abbreviation's or a
    /// date's period, and Casual lowercases no word after one.
    func testGermanAbbreviationsAndDatesEndNoSentenceInNotesAndCasual() {
        let notes: [(String, String)] = [
            ("Wir treffen uns um 13 Uhr bzw. später.", "Wir treffen uns um 13 Uhr bzw. später"),
            ("Das kostet ca. 5 Euro, d. h. nicht viel. Danke.", "- Das kostet ca. 5 Euro, d. h. nicht viel\n- Danke"),
            ("Wir sehen uns am 3. Oktober. Bis dann.", "- Wir sehen uns am 3. Oktober\n- Bis dann"),
            ("Es fehlen noch 50. März ist schon vorbei.", "- Es fehlen noch 50\n- März ist schon vorbei"),
            ("Die Temperatur steigt auf +5. März bleibt kühl.", "- Die Temperatur steigt auf +5\n- März bleibt kühl"),
            ("Ich habe u.a. Milch gekauft. Und Brot.", "- Ich habe u.a. Milch gekauft\n- Und Brot"),
            ("Bring Brot, Milch usw.", "Bring Brot, Milch usw."),
        ]
        for (raw, expected) in notes {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: .notes, language: .german), expected, raw)
        }
        let casual: [(String, String)] = [
            ("Ich treffe Anna z. B. morgen. Danach komme ich.", "ich treffe Anna z. B. morgen. danach komme ich"),
            ("Ich habe u.a. Milch gekauft. Und Brot.", "ich habe u.a. Milch gekauft. und Brot"),
            ("Wir sehen uns am 3. Oktober. Bis dann.", "wir sehen uns am 3. Oktober. bis dann"),
            ("Bring Brot usw.", "bring Brot usw."),
        ]
        for (raw, expected) in casual {
            XCTAssertEqual(TranscriptFormatter.typrRules(raw, style: .casual, language: .german), expected, raw)
        }
        // A number that ends a sentence still ends it.
        XCTAssertEqual(TranscriptFormatter.typrRules("Wir kommen um 13. Danach weiter.", style: .casual, language: .german),
                       "wir kommen um 13. danach weiter")
    }

    func testOffAppliesToEveryListLine() {
        XCTAssertEqual(
            TranscriptFormatter.typrRules("Einkaufsliste: erstens Milch, zweitens Eier.", style: .polished,
                                       language: .german, lists: true, endsWithPeriod: false),
            "Einkaufsliste:\n1. Milch\n2. Eier"
        )
        XCTAssertEqual(
            TranscriptFormatter.typrRules("My list: first milk, second eggs.", style: .polished,
                                       language: .english, lists: true, endsWithPeriod: false),
            "My list:\n1. Milk\n2. Eggs"
        )
    }

    /// Lowercase runs after the style on every path (`DictationPipeline.finish`). As in Hex it
    /// lowercases Verbatim too.
    func testLowercaseLowersEverythingAfterTheStyle() {
        let cases: [(String, String)] = [
            ("Ich treffe Anna im Büro. Danach komme ich.", "ich treffe anna im büro. danach komme ich."),
            ("ÄRGER mit der Straße? Über GitHub!", "ärger mit der straße? über github!"),
            ("I use the iPhone in the U.S.", "i use the iphone in the u.s."),
            ("Einkaufsliste:\n1. Milch\n2. Eier", "einkaufsliste:\n1. milch\n2. eier"),
        ]
        for (text, lowered) in cases {
            for style in DictationStyle.allCases {
                let pipeline = DictationPipeline(style: style, language: "de-DE", lowercase: true)
                XCTAssertEqual(pipeline.finish(text, language: "de-DE"), lowered, "\(style) \(text)")
            }
        }
    }

    @MainActor
    func testSettingsDefaultsKeepCurrentBehavior() {
        let suite = "end-period-lowercase.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.dictationEndsWithPeriod)
        XCTAssertFalse(settings.dictationLowercase)
        XCTAssertTrue(settings.dictationFormatLists, "Hex: on by default")
        XCTAssertTrue(settings.dictationSpokenPunctuation, "Hex: on by default")
        settings.dictationEndsWithPeriod = false
        settings.dictationLowercase = true
        XCTAssertFalse(TyprSettings(defaults: defaults).dictationEndsWithPeriod)
        XCTAssertTrue(TyprSettings(defaults: defaults).dictationLowercase)
    }
}
