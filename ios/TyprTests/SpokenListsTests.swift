import XCTest
@testable import Typr

final class SpokenListsTests: XCTestCase {
    private let styles: [DictationStyle] = [.polished, .casual, .veryCasual, .notes]

    private func assertRows(
        _ rows: [(String, [String])], language: DictationLanguage, punctuation: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for (heard, expected) in rows {
            let formatted = styles.map {
                TranscriptFormatter.format(heard, style: $0, language: language, lists: true, punctuation: punctuation)
            }
            XCTAssertEqual(formatted, expected, heard, file: file, line: line)
            XCTAssertEqual(
                TranscriptFormatter.format(heard, style: .verbatim, language: language, lists: true, punctuation: punctuation),
                TranscriptFormatter.format(heard, style: .verbatim, language: language),
                "Verbatim keeps the model's words: \(heard)", file: file, line: line
            )
        }
    }

    func testGermanListsInEveryStyle() {
        assertRows(Self.germanLists, language: .german, punctuation: false)
    }

    func testGermanListsWithSpokenPunctuation() {
        assertRows(Self.germanListsWithSpokenPunctuation, language: .german, punctuation: true)
    }

    func testEnglishListsInEveryStyle() {
        assertRows(Self.englishLists, language: .english, punctuation: false)
        assertRows(Self.englishListsWithSpokenPunctuation, language: .english, punctuation: true)
    }

    func testProseStaysAsSaidInEveryStyle() {
        for (corpus, languages) in [
            (Self.germanProse, [DictationLanguage.german]),
            (Self.englishProse, [DictationLanguage.english]),
        ] {
            for heard in corpus {
                for language in languages {
                    XCTAssertEqual(SpokenLists.format(heard, language: language), heard, "\(language) \(heard)")
                    for style in DictationStyle.allCases {
                        for punctuation in [false, true] {
                            XCTAssertEqual(
                                TranscriptFormatter.format(heard, style: style, language: language, lists: true, punctuation: punctuation),
                                TranscriptFormatter.format(heard, style: style, language: language, punctuation: punctuation),
                                "\(language) \(style) punctuation \(punctuation): \(heard)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testAutomaticLanguage() {
        XCTAssertEqual(
            SpokenLists.format("Ich habe zwei Punkte: erstens Milch, zweitens Eier.", language: .automatic),
            "Ich habe zwei Punkte:\n1. Milch\n2. Eier"
        )
        XCTAssertEqual(
            SpokenLists.format("I need two things: first, eggs, second, milk.", language: .automatic),
            "I need two things:\n1. Eggs\n2. Milk"
        )
    }

    func testNotesBulletsKeepWorking() {
        XCTAssertEqual(
            TranscriptFormatter.format("First item bullet check signing bullet test keyboard", style: .notes, lists: true),
            "First item\n- Check signing\n- Test keyboard"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("Einkaufen bullet Milch bullet Eier", style: .notes, language: .german, lists: true),
            "Einkaufen\n- Milch\n- Eier"
        )
    }

    @MainActor
    func testFormatListsSetting() {
        let defaults = UserDefaults(suiteName: "typr.tests.\(UUID().uuidString)")!
        XCTAssertTrue(TyprSettings(defaults: defaults).formatLists, "on by default, as in Hex")
        TyprSettings(defaults: defaults).formatLists = false
        XCTAssertFalse(TyprSettings(defaults: defaults).formatLists)
        XCTAssertEqual(
            TranscriptFormatter.format("Erstens Milch, zweitens Eier.", style: .polished, language: .german),
            "Erstens Milch, zweitens Eier.",
            "off: as before"
        )
    }

    /// Heard, then Polished, Casual, Very casual and Notes.
    private static let germanLists: [(String, [String])] = [
        ("Einkaufsliste: erstens Milch, zweitens Eier, drittens Brot.", ["Einkaufsliste:\n1. Milch.\n2. Eier.\n3. Brot.", "Einkaufsliste:\n1. Milch\n2. Eier\n3. Brot", "einkaufsliste:\n1. milch\n2. eier\n3. brot", "Einkaufsliste:\n1. Milch\n2. Eier\n3. Brot"]),
        ("Erstens Milch zweitens Eier drittens Brot", ["1. Milch.\n2. Eier.\n3. Brot.", "1. Milch\n2. Eier\n3. Brot", "1. milch\n2. eier\n3. brot", "1. Milch\n2. Eier\n3. Brot"]),
        ("Erstens habe ich keine Zeit und zweitens keine Lust.", ["1. Habe ich keine Zeit.\n2. Keine Lust.", "1. Habe ich keine Zeit\n2. Keine Lust", "1. habe ich keine zeit\n2. keine lust", "1. Habe ich keine Zeit\n2. Keine Lust"]),
        ("Erstens mal Milch, zweitens mal Eier.", ["1. Milch.\n2. Eier.", "1. Milch\n2. Eier", "1. milch\n2. eier", "1. Milch\n2. Eier"]),
        ("Als Erstes gehen wir einkaufen, als Zweites kochen wir.", ["1. Gehen wir einkaufen.\n2. Kochen wir.", "1. Gehen wir einkaufen\n2. Kochen wir", "1. gehen wir einkaufen\n2. kochen wir", "1. Gehen wir einkaufen\n2. Kochen wir"]),
        ("Punkt eins Budget. Punkt zwei Personal. Punkt drei Sonstiges.", ["1. Budget.\n2. Personal.\n3. Sonstiges.", "1. Budget\n2. Personal\n3. Sonstiges", "1. budget\n2. personal\n3. sonstiges", "1. Budget\n2. Personal\n3. Sonstiges"]),
        ("Punkt 1 Budget, Punkt 2 Personal.", ["1. Budget.\n2. Personal.", "1. Budget\n2. Personal", "1. budget\n2. personal", "1. Budget\n2. Personal"]),
        ("Nummer eins, die Bank anrufen. Nummer zwei, Miete zahlen.", ["1. Die Bank anrufen.\n2. Miete zahlen.", "1. Die Bank anrufen\n2. Miete zahlen", "1. die bank anrufen\n2. miete zahlen", "1. Die Bank anrufen\n2. Miete zahlen"]),
        ("Schritt eins Ofen vorheizen, Schritt zwei Teig rühren.", ["1. Ofen vorheizen.\n2. Teig rühren.", "1. Ofen vorheizen\n2. Teig rühren", "1. ofen vorheizen\n2. teig rühren", "1. Ofen vorheizen\n2. Teig rühren"]),
        ("Eins, Tickets kaufen. Zwei, Hotel buchen.", ["1. Tickets kaufen.\n2. Hotel buchen.", "1. Tickets kaufen\n2. Hotel buchen", "1. tickets kaufen\n2. hotel buchen", "1. Tickets kaufen\n2. Hotel buchen"]),
        ("Erstens Milch, zweitens Eier und zu guter Letzt Brot. Danke!", ["1. Milch.\n2. Eier.\n3. Brot.\nDanke!", "1. Milch\n2. Eier\n3. Brot\nDanke!", "1. milch\n2. eier\n3. brot\ndanke!", "1. Milch\n2. Eier\n3. Brot\nDanke!"]),
        ("Der Plan: erstens anrufen, zweitens zahlen. Bis morgen.", ["Der Plan:\n1. Anrufen.\n2. Zahlen.\nBis morgen.", "Der Plan:\n1. Anrufen\n2. Zahlen\nBis morgen", "der plan:\n1. anrufen\n2. zahlen\nbis morgen", "Der Plan:\n1. Anrufen\n2. Zahlen\nBis morgen."]),
        ("Hallo Anna, neue Zeile, danke für alles, neuer Absatz, bis bald.", ["Hallo Anna,\nDanke für alles\n\nBis bald.", "Hallo Anna,\nDanke für alles\n\nBis bald", "hallo anna,\ndanke für alles\n\nbis bald", "Hallo Anna,\nDanke für alles\n\nBis bald."]),
        ("Spiegelstrich Milch Spiegelstrich Eier Spiegelstrich Brot", ["- Milch.\n- Eier.\n- Brot.", "- Milch\n- Eier\n- Brot", "- milch\n- eier\n- brot", "- Milch\n- Eier\n- Brot"]),
        ("Aufzählungspunkt Milch, Aufzählungspunkt Eier.", ["- Milch.\n- Eier.", "- Milch\n- Eier", "- milch\n- eier", "- Milch\n- Eier"]),
        ("Äh, erstens, ähm, Milch, zweitens Eier.", ["1. Milch.\n2. Eier.", "1. Milch\n2. Eier", "1. milch\n2. eier", "1. Milch\n2. Eier"]),
    ]

    private static let germanListsWithSpokenPunctuation: [(String, [String])] = [
        ("Erstens Milch Komma zweitens Eier Komma drittens Brot Punkt", ["1. Milch.\n2. Eier.\n3. Brot.", "1. Milch\n2. Eier\n3. Brot", "1. milch\n2. eier\n3. brot", "1. Milch\n2. Eier\n3. Brot"]),
        ("Einkaufsliste Doppelpunkt erstens Milch zweitens Eier", ["Einkaufsliste:\n1. Milch.\n2. Eier.", "Einkaufsliste:\n1. Milch\n2. Eier", "einkaufsliste:\n1. milch\n2. eier", "Einkaufsliste:\n1. Milch\n2. Eier"]),
        ("Hallo Anna Komma neue Zeile wie geht es dir Fragezeichen", ["Hallo Anna,\nWie geht es dir?", "Hallo Anna,\nWie geht es dir?", "hallo anna,\nwie geht es dir?", "Hallo Anna,\nWie geht es dir?"]),
        ("Punkt eins Budget Punkt zwei Personal", ["1. Budget.\n2. Personal.", "1. Budget\n2. Personal", "1. budget\n2. personal", "1. Budget\n2. Personal"]),
        ("Erstens Milch Punkt zweitens Eier Punkt", ["1. Milch.\n2. Eier.", "1. Milch\n2. Eier", "1. milch\n2. eier", "1. Milch\n2. Eier"]),
        ("Das ist ein wichtiger Punkt Punkt erstens Milch zweitens Eier", ["Das ist ein wichtiger Punkt.\n1. Milch.\n2. Eier.", "Das ist ein wichtiger Punkt.\n1. Milch\n2. Eier", "das ist ein wichtiger punkt.\n1. milch\n2. eier", "Das ist ein wichtiger Punkt.\n1. Milch\n2. Eier"]),
    ]

    private static let englishLists: [(String, [String])] = [
        ("Here is my shopping list. First, eggs. Second, milk, third, bread.", ["Here is my shopping list.\n1. Eggs.\n2. Milk.\n3. Bread.", "Here is my shopping list.\n1. Eggs\n2. Milk\n3. Bread", "here is my shopping list.\n1. eggs\n2. milk\n3. bread", "Here is my shopping list.\n1. Eggs\n2. Milk\n3. Bread"]),
        ("Number one, call the bank. Number two, pay rent.", ["1. Call the bank.\n2. Pay rent.", "1. Call the bank\n2. Pay rent", "1. call the bank\n2. pay rent", "1. Call the bank\n2. Pay rent"]),
        ("Dear Sam, new line, thanks for the help, new paragraph see you soon.", ["Dear Sam\nThanks for the help\n\nSee you soon.", "Dear Sam\nThanks for the help\n\nSee you soon", "dear sam\nthanks for the help\n\nsee you soon", "Dear Sam,\nThanks for the help,\n\nSee you soon."]),
        ("Groceries, bullet, eggs, bullet, milk, bullet bread.", ["Groceries:\n- Eggs.\n- Milk.\n- Bread.", "Groceries:\n- Eggs\n- Milk\n- Bread", "groceries:\n- eggs\n- milk\n- bread", "Groceries,\n- Eggs,\n- Milk,\n- Bread."]),
        ("Um, so the plan is, first, um, call the bank, second, pay rent. Thanks!", ["So the plan is:\n1. Call the bank.\n2. Pay rent.\nThanks!", "So the plan is:\n1. Call the bank\n2. Pay rent\nThanks!", "so the plan is:\n1. call the bank\n2. pay rent\nthanks!", "So the plan is:\n1. Call the bank\n2. Pay rent\nThanks!"]),
    ]

    private static let englishListsWithSpokenPunctuation: [(String, [String])] = [
        ("First eggs comma second milk period", ["1. Eggs.\n2. Milk.", "1. Eggs\n2. Milk", "1. eggs\n2. milk", "1. Eggs\n2. Milk"]),
    ]

    private static let germanProse = [
        "Das ist erstens teuer und zweitens hässlich.",
        "Er hat erstens keine Zeit, und das ist zweitens auch egal.",
        "Erstens, das ist gut.",
        "Erstens bin ich müde.",
        "Zweitens ist das egal.",
        "Das war erstens.",
        "Ich habe zum ersten Mal gewonnen und zum zweiten Mal verloren.",
        "Er kam als Erster an und sie als Zweite.",
        "Wir treffen uns um Punkt eins und gehen um Punkt zwei.",
        "Punkt eins ist erledigt, kommen wir jetzt zu Punkt zwei.",
        "Das ist ein wichtiger Punkt.",
        "Punkt für Punkt gehen wir das durch.",
        "Der Punkt ist, dass ich keine Zeit habe.",
        "Um Punkt zwölf essen wir.",
        "Eins, zwei, drei, los.",
        "Eins zwei drei vier.",
        "Test 1, 2, 3.",
        "Eins, zwei oder drei Tage.",
        "Wir brauchen 1, 2 oder 3 Tage.",
        "Termine: 1. Mai, 2. Juni.",
        "Am 1. Mai und am 2. Juni sind Feiertage.",
        "Er wurde 1. und sie 2.",
        "Platz 1. Platz 2.",
        "Nummer eins der Charts ist neu.",
        "Er ist die Nummer eins und sie die Nummer zwei.",
        "Schritt für Schritt kommen wir weiter.",
        "Der erste Schritt ist schwer, der zweite leichter.",
        "Das ist eine neue Zeile.",
        "Das ist eine ganz neue Zeile.",
        "Wir schreiben eine völlig neue Zeile.",
        "Die neue Zeile ist zu lang.",
        "Neue Zeile einfügen geht so.",
        "Er beginnt einen neuen Absatz.",
        "Ein neuer Absatz im Gesetz regelt das.",
        "Das Gesetz hat einen neuer Absatz bekommen.",
        "Das ist komplett neuer Absatz.",
        "Der Zeilenumbruch ist kaputt.",
        "Ein Spiegelstrich reicht.",
        "Der Spiegelstrich ist zu lang.",
        "Mach hier einen Spiegelstrich und dort einen Spiegelstrich.",
        "Zuletzt war ich in Berlin.",
        "Zu guter Letzt danke ich euch.",
        "Als Erstes möchte ich mich bedanken.",
        "Was machst du als Erstes?",
        "Ich habe erstens nein gesagt.",
        "Zum einen ist es teuer, zum anderen hässlich.",
        "Einerseits ja, andererseits nein.",
        "Zuerst essen wir, dann gehen wir.",
        "Ich bin zweitens Erster geworden.",
        "Erstens kommt es anders und zweitens als man denkt.",
        "Eins ist klar: Wir kommen.",
        "Zwei Komma fünf Liter Milch.",
        "Punkt zwei Uhr bin ich da.",
        "Er sagte eins, dann zwei.",
        "Sie hat zwei Kinder und drei Katzen.",
        "Drei, zwei, eins, Start.",
        "Erstens heißt auf Englisch first.",
        "Seite eins, Seite zwei.",
        "Kapitel eins und zwei sind fertig.",
        "Die Bullet Points sind auf der Folie.",
        "Ein Bullet traf die Wand.",
    ]

    private static let englishProse = [
        "The first time I saw it, I loved it.",
        "She is one of the best.",
        "I have two dogs and three cats.",
        "Don't second guess yourself.",
        "At first I didn't like it, but then I did.",
        "First things first, let's eat.",
        "He finished first and I finished second.",
        "One day we'll go there.",
        "Give me one second.",
        "It's the second time this week.",
        "We bought a new line of shoes.",
        "The bullet points are on the slide.",
        "I need to dash, see you.",
        "Number one fans only.",
        "One, two, three, go!",
        "Step by step, we got there.",
        "Who came first, the chicken or the egg?",
        "My first car was red and my second was blue.",
        "Two, maybe three people came.",
        "One more thing, call me later.",
        "First of all, thank you for coming.",
        "A bullet hit the wall.",
        "In the first place, it was not my fault.",
        "Add a new paragraph about pricing.",
        "Firstly, I disagree.",
        "We'll meet at 1, 2, or 3.",
        "Chapter one, two and three are done.",
        "One, two, buckle my shoe. Three, four, shut the door.",
        "He said one thing, then another.",
        "I was second in line, and first in my heart.",
        "The second half was better than the first.",
        "First come, first served.",
        "Second to none.",
        "Item one is missing.",
        "Point taken, next item please.",
        "Meet me at 1:30. 2 people are coming.",
        "That's a new line for me.",
        "Our new line of credit is ready.",
        "Third time's the charm.",
        "Last, but not least, thanks.",
        "One, I'm tired.",
        "First, let me say thanks for coming.",
        "Finally, we're done. Lastly, go home.",
        "The dash cam caught it.",
        "Number two pencils only.",
        "There are two options. One, we wait.",
        "Test 1, 2, 3.",
    ]
}
