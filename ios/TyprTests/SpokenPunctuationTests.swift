import XCTest
@testable import Typr

final class SpokenPunctuationTests: XCTestCase {
    private func german(_ text: String) -> String {
        SpokenPunctuation.format(text, language: .german)
    }

    private func english(_ text: String) -> String {
        SpokenPunctuation.format(text, language: .english)
    }

    func testGermanCommands() {
        XCTAssertEqual(german("Hallo Komma wie geht es dir Fragezeichen"), "Hallo, wie geht es dir?")
        XCTAssertEqual(german("Ich bin gleich da Punkt bis bald"), "Ich bin gleich da. Bis bald")
        XCTAssertEqual(german("Danke für das Update Punkt"), "Danke für das Update.")
        XCTAssertEqual(german("Ruf mich an Punkt"), "Ruf mich an.")
        XCTAssertEqual(german("Das ist toll Ausrufezeichen"), "Das ist toll!")
        XCTAssertEqual(german("Der Plan Doppelpunkt, wir gehen um 12."), "Der Plan: wir gehen um 12.")
        XCTAssertEqual(german("Ich kam Semikolon ich sah"), "Ich kam; ich sah")
        XCTAssertEqual(german("Ich kam Strichpunkt ich sah"), "Ich kam; ich sah")
        XCTAssertEqual(german("Warte Auslassungspunkte"), "Warte…")
        XCTAssertEqual(german("Schick mir eine E Bindestrich Mail"), "Schick mir eine E-Mail")
        XCTAssertEqual(german("Es war gut Gedankenstrich und dann kam Regen"), "Es war gut – und dann kam Regen")
    }

    func testGermanQuotesAndBrackets() {
        XCTAssertEqual(
            german("Er sagte Anführungszeichen unten Hallo Anführungszeichen oben"),
            "Er sagte „Hallo“"
        )
        XCTAssertEqual(
            german("Er sagte Anführungszeichen unten Hallo, Anführungszeichen oben."),
            "Er sagte „Hallo“."
        )
        XCTAssertEqual(german("Er sagte Anführungszeichen Hallo Anführungszeichen"), "Er sagte „Hallo“")
        XCTAssertEqual(german("Er sagte Anführungszeichen Hallo, Abführungszeichen."), "Er sagte „Hallo“.")
        XCTAssertEqual(
            german("Ruf mich an Klammer auf nach dem Essen Klammer zu"),
            "Ruf mich an (nach dem Essen)"
        )
        XCTAssertEqual(german("Er war fertig Klammer zu"), "Er war fertig Klammer zu", "nothing open")
    }

    func testGermanProseStaysAsSaid() {
        for sentence in [
            "Das ist ein wichtiger Punkt.",
            "Das Komma ist optional.",
            "Der Punkt ist, dass wir gehen.",
            "Wir treffen uns um Punkt acht.",
            "Das ist der springende Punkt.",
            "Ohne Komma geht es nicht.",
            "Zwei Komma fünf Prozent.",
            "Ein Fragezeichen bleibt.",
            "Setz einen Punkt dahinter.",
            "Das war ein guter Punkt.",
            "Der Doppelpunkt fehlt.",
            "Er hat ein Komma vergessen.",
            "Hallo, wie geht es dir?",
            "Er sagte „Hallo“ und ging.",
        ] {
            XCTAssertEqual(german(sentence), sentence)
        }
        XCTAssertEqual(german("Der Wert ist zwei Komma fünf"), "Der Wert ist zwei Komma fünf")
        XCTAssertEqual(german("Es kostet 3 Komma 5 Euro"), "Es kostet 3 Komma 5 Euro")
    }

    func testEnglishCommands() {
        XCTAssertEqual(english("Hi Sarah comma how are you question mark"), "Hi Sarah, how are you?")
        XCTAssertEqual(english("I'm almost there period see you soon"), "I'm almost there. See you soon")
        XCTAssertEqual(english("Note to self colon buy milk"), "Note to self: buy milk")
        XCTAssertEqual(english("Thanks so much exclamation point see you tomorrow period"), "Thanks so much! See you tomorrow.")
        XCTAssertEqual(english("I came semicolon I saw"), "I came; I saw")
        XCTAssertEqual(english("He said open quote no way close quote period"), "He said “no way”.")
        XCTAssertEqual(english("Bring snacks open paren chips or pretzels close paren"), "Bring snacks (chips or pretzels)")
        XCTAssertEqual(english("It is a well hyphen known fact"), "It is a well-known fact")
        XCTAssertEqual(english("Email ana at sign gmail.com"), "Email ana@gmail.com")
        XCTAssertEqual(english("I'll be there at noon, comma, see you soon, period"), "I'll be there at noon, see you soon.")
        XCTAssertEqual(english("Are you coming tonight question mark?"), "Are you coming tonight?", "never doubled")
    }

    func testEnglishProseStaysAsSaid() {
        for sentence in [
            "It was a long period of time.",
            "The comma is optional here.",
            "She put a dash of salt in the soup.",
            "He has a question mark tattoo on his arm.",
            "He was diagnosed with colon cancer.",
            "The trial period ends tomorrow.",
            "Do you use the Oxford comma?",
            "Can you quote me on that?",
            "It's a quote unquote expert opinion.",
            "The comma-separated list is attached.",
            "I'll text Dash later.",
            "It costs two comma five million",
            "The meeting is at 3 colon 30",
        ] {
            XCTAssertEqual(english(sentence), sentence)
        }
    }

    func testAutomaticLanguage() {
        XCTAssertEqual(
            SpokenPunctuation.format("Ich bin gleich da Punkt bis bald", language: .automatic),
            "Ich bin gleich da. Bis bald"
        )
        XCTAssertEqual(
            SpokenPunctuation.format("I'm almost there period see you soon", language: .automatic),
            "I'm almost there. See you soon"
        )
    }

    func testStyles() {
        let heard = "Hallo Komma wie geht es dir Fragezeichen ich bin gleich da Punkt bis bald"
        let formatted = DictationStyle.allCases.map {
            TranscriptFormatter.format(heard, style: $0, language: .german, punctuation: true)
        }
        XCTAssertEqual(formatted, [
            "Hallo, wie geht es dir? Ich bin gleich da. Bis bald.",
            "Hallo, wie geht es dir? Ich bin gleich da. Bis bald",
            "hallo, wie geht es dir? ich bin gleich da. bis bald",
            "Hallo, wie geht es dir? Ich bin gleich da. Bis bald",
            heard,
        ])
        XCTAssertEqual(
            TranscriptFormatter.format("Okay comma see you there exclamation point", style: .polished, language: .english, punctuation: true),
            "Okay, see you there!"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("Das ist ein wichtiger Punkt", style: .polished, language: .german, punctuation: true),
            "Das ist ein wichtiger Punkt."
        )
    }

    func testNotesMarkersKeepWorking() {
        XCTAssertEqual(
            TranscriptFormatter.format(
                "Einkaufen bullet Milch Komma Butter bullet Eier Punkt new paragraph danke dir Ausrufezeichen",
                style: .notes, language: .german, punctuation: true
            ),
            "Einkaufen\n- Milch, Butter\n- Eier.\n\nDanke dir!"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("Milch Punkt new line Eier", style: .notes, language: .german, punctuation: true),
            "Milch.\nEier"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("First item bullet check signing bullet test keyboard", style: .notes, punctuation: true),
            "First item\n- Check signing\n- Test keyboard"
        )
    }

    func testCleanedTextIsNotConvertedTwice() {
        for cleaned in [
            "Hallo, wie geht es dir? Ich komme morgen.",
            "Er sagte „Hallo“ (nach dem Essen).",
            "Das ist ein wichtiger Punkt.",
            "Der Wert ist 2,5.",
        ] {
            XCTAssertEqual(TranscriptFormatter.format(cleaned, style: .polished, language: .german, punctuation: true), cleaned)
        }
        XCTAssertEqual(
            TranscriptFormatter.format("Hallo, Komma, wie geht es dir, Fragezeichen?", style: .polished, language: .german, punctuation: true),
            "Hallo, wie geht es dir?"
        )
    }

    func testGermanSweep() {
        let cases: [(String, String)] = [
            ("Das ist ein sehr wichtiger Punkt.", "Das ist ein sehr wichtiger Punkt."),
            ("Das ist ein unglaublich wichtiger Punkt.", "Das ist ein unglaublich wichtiger Punkt."),
            ("Das ist ein nicht unwichtiger Punkt.", "Das ist ein nicht unwichtiger Punkt."),
            ("Das ist ein ganz besonders wichtiger Punkt", "Das ist ein ganz besonders wichtiger Punkt"),
            ("Das ist der wirklich entscheidende Punkt", "Das ist der wirklich entscheidende Punkt"),
            ("Er setzt einen dicken fetten Punkt", "Er setzt einen dicken fetten Punkt"),
            ("Da fehlt ein überflüssiges Komma", "Da fehlt ein überflüssiges Komma"),
            ("Hier fehlt das letzte Komma", "Hier fehlt das letzte Komma"),
            ("Ich habe es gemacht Punkt", "Ich habe es gemacht."),
            ("Das ist wirklich gut Punkt", "Das ist wirklich gut."),
            ("Ich brauche Brot Komma zwei Eier und Milch.", "Ich brauche Brot, zwei Eier und Milch."),
            ("Wir treffen uns Punkt acht", "Wir treffen uns Punkt acht"),
            ("Er sagte „Anführungszeichen unten Hallo Anführungszeichen oben“.", "Er sagte „Hallo“."),
            ("Er sagte Anführungszeichen unten „Hallo“ Anführungszeichen oben.", "Er sagte „Hallo“."),
            ("Er sagte „Anführungszeichen Hallo Anführungszeichen“.", "Er sagte „Hallo“."),
            ("Er sagte Anführungszeichen „Hallo“ Anführungszeichen", "Er sagte „Hallo“"),
            ("Ruf an (Klammer auf morgen Klammer zu).", "Ruf an (morgen)."),
            ("Ruf an Klammer auf (morgen) Klammer zu", "Ruf an (morgen)"),
            ("Er sagte Anführungszeichen unten Hallo Punkt Anführungszeichen oben.", "Er sagte „Hallo.“"),
            ("Er sagte Anführungszeichen unten Hallo Fragezeichen Anführungszeichen oben.", "Er sagte „Hallo?“"),
            ("Er sagte Anführungszeichen unten Hallo Ausrufezeichen Anführungszeichen oben!", "Er sagte „Hallo!“"),
            ("Ruf an Klammer auf gleich Punkt Klammer zu.", "Ruf an (gleich.)"),
            ("Er sagte Anführungszeichen unten Hallo Anführungszeichen oben.", "Er sagte „Hallo“."),
            ("Er sagte Anführungszeichen unten Hallo Anführungszeichen oben Komma und ging", "Er sagte „Hallo“, und ging"),
        ]
        for (heard, expected) in cases {
            XCTAssertEqual(german(heard), expected, heard)
        }
    }

    func testEnglishSweep() {
        let cases: [(String, String)] = [
            ("It was a really important period.", "It was a really important period."),
            ("That is a very long period", "That is a very long period"),
            ("Thank you so much period", "Thank you so much."),
            ("He said “open quote no way close quote”.", "He said “no way”."),
            ("He said open quote “no way” close quote.", "He said “no way”."),
            ("He said \"open quote no way close quote\".", "He said \"no way\"."),
            ("He said open quote see you period close quote.", "He said “see you.”"),
            ("Bring snacks (open paren chips close paren).", "Bring snacks (chips)."),
            ("Bring snacks open paren chips question mark close paren.", "Bring snacks (chips?)"),
        ]
        for (heard, expected) in cases {
            XCTAssertEqual(english(heard), expected, heard)
        }
    }

    func testPolishedAddsNoPeriodAfterClosedSentence() {
        let cases: [(String, String)] = [
            ("Er sagte Anführungszeichen unten Hallo Punkt Anführungszeichen oben.", "Er sagte „Hallo.“"),
            ("Ruf an Klammer auf gleich Punkt Klammer zu.", "Ruf an (gleich.)"),
        ]
        for (heard, expected) in cases {
            XCTAssertEqual(
                TranscriptFormatter.format(heard, style: .polished, language: .german, punctuation: true), expected, heard
            )
        }
        XCTAssertEqual(
            TranscriptFormatter.format("Er sagte „Hallo“", style: .polished, language: .german),
            "Er sagte „Hallo“."
        )
    }

    @MainActor
    func testExperimentalSwitch() {
        let defaults = UserDefaults(suiteName: "typr.tests.\(UUID().uuidString)")!
        XCTAssertTrue(ExperimentalSwitch.all.contains(.spokenPunctuation))
        XCTAssertFalse(TyprSettings(defaults: defaults)[experiment: .spokenPunctuation])
        TyprSettings(defaults: defaults)[experiment: .spokenPunctuation] = true
        XCTAssertTrue(TyprSettings(defaults: defaults)[experiment: .spokenPunctuation])
    }

    private static let germanNounPhrases = [
        "Das ist ein sehr wichtiger Punkt.",
        "Das ist ein unglaublich wichtiger Punkt.",
        "Das ist ein nicht unwichtiger Punkt.",
        "Das ist ein für mich sehr wichtiger Punkt.",
        "Hier fehlt das erste und wichtigste Komma.",
        "Das ist aus meiner Sicht ein wichtiger Punkt.",
        "Das ist ein kleiner, aber wichtiger Punkt.",
        "Das ist ein wirklich sehr ganz besonders extrem wichtiger Punkt.",
        "Das ist ein ganz besonders wichtiger Punkt",
        "Das ist der wirklich entscheidende Punkt",
        "Er setzt einen dicken fetten Punkt",
        "Da fehlt ein überflüssiges Komma",
        "Hier fehlt das letzte Komma",
        "Das ist ein wichtiger Punkt.",
        "Das war ein guter Punkt.",
        "Das ist der springende Punkt.",
        "Das ist der wichtigste Punkt.",
        "Wir kommen zum nächsten Punkt.",
        "Der dritte Punkt fehlt noch.",
        "Das ist ein großes Fragezeichen.",
        "Am Ende steht ein dickes Ausrufezeichen.",
        "Er vergisst immer das zweite Komma.",
        "Wir besprechen den letzten Punkt.",
        "Ein weiterer Punkt ist die Miete.",
        "Bitte achte auf jedes einzelne Komma.",
        "Das ist ein heikler Punkt.",
        "Ein ganz anderer Punkt.",
        "Mir fehlt ein entscheidender Punkt",
        "Da steht ein falscher Doppelpunkt",
        "Er setzt ein unnötiges Semikolon",
        "Das ist mein liebster Punkt",
        "Wir treffen uns um Punkt acht.",
        "Zwei Komma fünf Prozent.",
        "Das Komma ist optional.",
        "Ohne Komma geht es nicht.",
        "Der Doppelpunkt fehlt.",
        "Das ist ein rosa Punkt.",
        "Hier fehlt ein lila Komma.",
        "Das ist ein ganz rosa Punkt.",
        "Wir gehen Punkt für Punkt.",
        "Er kennt Punkt und Komma.",
        "Setz Punkt oder Komma.",
        "Er kennt Klammer auf und Klammer zu.",
        "Er nutzt das Zeichen Hashtag sehr oft.",
        "Klammer auf bedeutet den Beginn der Klammer.",
        "Das Wort Komma ist kurz.",
        "Die Taste Punkt klemmt.",
        "Ein langer Bindestrich fehlt.",
        "Das ist ein schöner Gedankenstrich",
        "Anführungszeichen unten sind im Deutschen üblich.",
    ]

    private static let englishNounPhrases = [
        "That was an important period.",
        "This is an awkward period.",
        "That is an unusual comma.",
        "It was a really important period.",
        "That is a very long period",
        "It was a difficult period for everyone",
        "This was the most productive period",
        "It is a critical period",
        "He made a terrible period",
        "That was an amazing period",
        "We went through a rough period",
        "It was a historic period",
        "That is a decisive comma",
        "It is the final period",
        "That was a confusing question mark",
        "They had a successful period",
        "It was a wonderful period",
        "This is the third period",
        "We had a frustrating period",
        "She drew a big question mark",
        "That was an emotional period",
        "My dash cam caught the whole thing.",
        "The comma is optional here.",
        "It was a long period of time.",
        "The trial period ends tomorrow.",
        "This was a short, bizarre period.",
        "Please compare comma and semicolon.",
        "Use a period or a comma.",
        "The word comma is short.",
        "He typed the hashtag symbol.",
        "Open paren is a token in this grammar.",
        "A long dash looks odd.",
        "It ends with a big, bold period",
    ]

    func testNounPhrasesStayAsSaidInEveryStyle() {
        let cases = Self.germanNounPhrases.map { ($0, DictationLanguage.german) }
            + Self.englishNounPhrases.map { ($0, DictationLanguage.english) }
        XCTAssertGreaterThanOrEqual(cases.count, 60)
        for (sentence, language) in cases {
            for style in DictationStyle.allCases {
                XCTAssertEqual(
                    TranscriptFormatter.format(sentence, style: style, language: language, punctuation: true),
                    TranscriptFormatter.format(sentence, style: style, language: language),
                    "\(style) \(sentence)"
                )
            }
        }
    }

    func testSupportedConversionsInPolished() {
        let cases: [(String, DictationLanguage, String)] = [
            ("Hallo Komma wie geht es dir Fragezeichen", .german, "Hallo, wie geht es dir?"),
            ("Ich bin gleich da Punkt bis bald", .german, "Ich bin gleich da. Bis bald."),
            ("Danke für das Update Punkt", .german, "Danke für das Update."),
            ("Ruf mich an Punkt", .german, "Ruf mich an."),
            ("Ich habe es gemacht Punkt", .german, "Ich habe es gemacht."),
            ("Ich brauche Brot Komma zwei Eier und Milch", .german, "Ich brauche Brot, zwei Eier und Milch."),
            ("Der Plan Doppelpunkt wir gehen um 12", .german, "Der Plan: wir gehen um 12."),
            ("Ich kam Semikolon ich sah", .german, "Ich kam; ich sah."),
            ("Das ist toll Ausrufezeichen", .german, "Das ist toll!"),
            ("Er sagte Anführungszeichen unten Hallo Anführungszeichen oben", .german, "Er sagte „Hallo“."),
            ("Ruf mich an Klammer auf nach dem Essen Klammer zu", .german, "Ruf mich an (nach dem Essen)"),
            ("Hi Sarah comma how are you question mark", .english, "Hi Sarah, how are you?"),
            ("I'm almost there period see you soon", .english, "I'm almost there. See you soon."),
            ("Note to self colon buy milk", .english, "Note to self: buy milk."),
            ("Thanks so much exclamation point", .english, "Thanks so much!"),
            ("He said open quote see you close quote", .english, "He said “see you”"),
        ]
        for (heard, language, expected) in cases {
            XCTAssertEqual(
                TranscriptFormatter.format(heard, style: .polished, language: language, punctuation: true), expected, heard
            )
        }
    }
}
