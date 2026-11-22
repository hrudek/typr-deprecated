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
                        TranscriptFormatter.format(raw, style: style, lists: lists, endsWithPeriod: true),
                        TranscriptFormatter.format(raw, style: style, lists: lists),
                        "\(style) \(raw)"
                    )
                }
            }
        }
    }

    func testOffLeavesVerbatimUnchanged() {
        for raw in Self.germanInputs + Self.englishInputs {
            XCTAssertEqual(TranscriptFormatter.format(raw, style: .verbatim, endsWithPeriod: false),
                           TranscriptFormatter.format(raw, style: .verbatim), raw)
        }
    }

    func testOffDropsTheFinalPeriodInGerman() {
        let cases: [(String, DictationStyle, String)] = [
            ("ich komme morgen", .polished, "Ich komme morgen"),
            ("Ich komme. Du auch.", .polished, "Ich komme. Du auch"),
            ("Ich komme. Du auch.", .notes, "Ich komme. Du auch"),
            ("Ich komme. Du auch.", .casual, "Ich komme. Du auch"),
            ("Ich komme. Du auch.", .veryCasual, "ich komme. du auch"),
            ("Wir treffen uns um 13 Uhr bzw. später.", .polished, "Wir treffen uns um 13 Uhr bzw. später"),
            ("Er sagte „Hallo.“", .notes, "Er sagte „Hallo“"),
            ("Er sagte „Hallo.“", .casual, "Er sagte „Hallo“"),
            ("Hallo bullet Milch. bullet Brot.", .notes, "Hallo\n- Milch\n- Brot"),
            ("Ich treffe Anna im Büro. Danach komme ich.\nGegen 13 Uhr bin ich zurück.", .polished,
             "Ich treffe Anna im Büro. Danach komme ich\nGegen 13 Uhr bin ich zurück"),
            ("Ich treffe Anna im Büro.\nGegen 13 Uhr bin ich zurück.", .casual,
             "Ich treffe Anna im Büro\nGegen 13 Uhr bin ich zurück"),
        ]
        for (raw, style, expected) in cases {
            XCTAssertEqual(TranscriptFormatter.format(raw, style: style, language: .german, endsWithPeriod: false),
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
            XCTAssertEqual(TranscriptFormatter.format(raw, style: style, language: .german, endsWithPeriod: false),
                           expected, "\(style) \(raw)")
        }
    }

    func testOffDropsTheFinalPeriodInEnglish() {
        let cases: [(String, DictationStyle, String)] = [
            ("see you tomorrow", .polished, "See you tomorrow"),
            ("Sounds good. See you tomorrow.", .polished, "Sounds good. See you tomorrow"),
            ("Sounds good. See you tomorrow.", .notes, "Sounds good. See you tomorrow"),
            ("Sounds good. See you tomorrow.\nBring the keys.", .casual, "Sounds good. See you tomorrow\nBring the keys"),
            ("She said \"hi.\"", .notes, "She said \"hi\""),
            ("Are you coming?", .polished, "Are you coming?"),
            ("That's great!", .notes, "That's great!"),
            ("We met in the U.S.", .polished, "We met in the U.S."),
            ("Bring pens, paper etc.", .polished, "Bring pens, paper etc."),
            ("Use a fork, e.g.", .notes, "Use a fork, e.g."),
        ]
        for (raw, style, expected) in cases {
            XCTAssertEqual(TranscriptFormatter.format(raw, style: style, language: .english, endsWithPeriod: false),
                           expected, "\(style) \(raw)")
        }
    }

    func testOffAppliesToEveryListLine() {
        XCTAssertEqual(
            TranscriptFormatter.format("Einkaufsliste: erstens Milch, zweitens Eier.", style: .polished,
                                       language: .german, lists: true, endsWithPeriod: false),
            "Einkaufsliste:\n1. Milch\n2. Eier"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("My list: first milk, second eggs.", style: .polished,
                                       language: .english, lists: true, endsWithPeriod: false),
            "My list:\n1. Milk\n2. Eggs"
        )
    }

    func testLowercaseLowersEverythingButVerbatim() {
        let cases: [(String, String)] = [
            ("Ich treffe Anna im Büro. Danach komme ich.", "ich treffe anna im büro. danach komme ich."),
            ("ÄRGER mit der Straße? Über GitHub!", "ärger mit der straße? über github!"),
            ("I use the iPhone in the U.S.", "i use the iphone in the u.s."),
            ("Einkaufsliste:\n1. Milch\n2. Eier", "einkaufsliste:\n1. milch\n2. eier"),
        ]
        for (text, lowered) in cases {
            for style in DictationStyle.allCases where style != .verbatim {
                XCTAssertEqual(TranscriptFormatter.lowercased(text, style: style), lowered, "\(style) \(text)")
            }
            XCTAssertEqual(TranscriptFormatter.lowercased(text, style: .verbatim), text)
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
        settings.dictationEndsWithPeriod = false
        settings.dictationLowercase = true
        XCTAssertFalse(TyprSettings(defaults: defaults).dictationEndsWithPeriod)
        XCTAssertTrue(TyprSettings(defaults: defaults).dictationLowercase)
    }
}
