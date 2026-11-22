import XCTest
@testable import Typr

// Hex's formatting tests (anomalyco/hex `ios/HEXMobileTests/TranscriptCleanupTests.swift` at
// 0c1c13d7, MIT): the default `TranscriptFormatter`, `SpokenLists`, `SpokenPunctuation`,
// `FrenchSpacing` and `DictationPipeline.format`. Only the settings reads are Typr's.

final class HexSpokenListsTests: XCTestCase {
    private func lists(_ text: String, _ language: String = "en-US") -> String {
        SpokenLists.format(text, language: language)
    }

    func testNumberedListsInEnglish() {
        XCTAssertEqual(
            lists("Here is my shopping list. First, eggs. Second, milk, third, bread."),
            "Here is my shopping list.\n1. Eggs\n2. Milk\n3. Bread"
        )
        XCTAssertEqual(
            lists("My shopping list, 1st egg, 2nd milk, and 3rd bread."),
            "My shopping list:\n1. Egg\n2. Milk\n3. Bread"
        )
        XCTAssertEqual(
            lists("Number one, call the bank. Number two, pay rent. Number three, email Sam."),
            "1. Call the bank\n2. Pay rent\n3. Email Sam"
        )
        XCTAssertEqual(
            lists("One, buy tickets. Two, book the hotel. Three, pack."),
            "1. Buy tickets\n2. Book the hotel\n3. Pack"
        )
        XCTAssertEqual(
            lists("Step one preheat the oven, step two, mix the flour, step three, bake for 20 minutes."),
            "1. Preheat the oven\n2. Mix the flour\n3. Bake for 20 minutes"
        )
        XCTAssertEqual(lists("1. Eggs. 2. Milk."), "1. Eggs\n2. Milk")
        XCTAssertEqual(lists("First of all, thanks. Second of all, sorry."), "1. Thanks\n2. Sorry")
    }

    /// "finally" ends a list of two or more; what follows the last item's sentence is its own
    /// line, and a later list is found too.
    func testListEndsAndWhatFollows() {
        XCTAssertEqual(
            lists("First, preheat the oven. Second, mix. And finally, bake. Thanks!"),
            "1. Preheat the oven\n2. Mix\n3. Bake\nThanks!"
        )
        XCTAssertEqual(
            lists("Third, bake for 20 minutes. Let it cool. First, preheat. Second, mix."),
            "Third, bake for 20 minutes. Let it cool.\n1. Preheat\n2. Mix"
        )
        XCTAssertEqual(
            lists("Who's coming? First, Ana. Second, who else?"),
            "Who's coming?\n1. Ana\n2. Who else?"
        )
        XCTAssertEqual(
            lists("Packing: first, the iPhone charger, second, passport."),
            "Packing:\n1. The iPhone charger\n2. Passport"
        )
    }

    func testBulletsAndLineBreaks() {
        XCTAssertEqual(lists("Groceries, bullet, eggs, bullet, milk, bullet bread."), "Groceries:\n- Eggs\n- Milk\n- Bread")
        XCTAssertEqual(lists("Todo bullet ship it bullet tell Ravi"), "Todo:\n- Ship it\n- Tell Ravi")
        XCTAssertEqual(lists("Agenda: next item, budget. Next item, hiring."), "Agenda:\n- Budget\n- Hiring")
        XCTAssertEqual(lists("Dash, eggs. Dash, milk."), "- Eggs\n- Milk")
        XCTAssertEqual(
            lists("Dear Sam, new line, thanks for the help, new paragraph see you soon."),
            "Dear Sam\nthanks for the help\n\nsee you soon."
        )
        XCTAssertEqual(lists("Shopping new line bullet eggs new line bullet milk"), "Shopping\n- Eggs\n- Milk")
    }

    func testSpanish() {
        XCTAssertEqual(
            lists("Mi lista de compras. Primero, huevos, segundo, leche, tercero, pan.", "es-ES"),
            "Mi lista de compras.\n1. Huevos\n2. Leche\n3. Pan"
        )
        XCTAssertEqual(
            lists("Uno, Comprar boletos. Dos, reservar el hotel. Tres, hacer la maleta.", "es-MX"),
            "1. Comprar boletos\n2. Reservar el hotel\n3. Hacer la maleta"
        )
        XCTAssertEqual(lists("Viñeta, huevos, viñeta, leche, viñeta, pan.", "es-ES"), "- Huevos\n- Leche\n- Pan")
        XCTAssertEqual(
            lists("En primer lugar, gracias. En segundo lugar, perdón. Y por último, adiós.", "es-ES"),
            "1. Gracias\n2. Perdón\n3. Adiós"
        )
        XCTAssertEqual(
            lists("Hola Ana, nueva línea. Gracias por todo nuevo párrafo. Nos vemos.", "es-ES"),
            "Hola Ana\nGracias por todo\n\nNos vemos."
        )
        XCTAssertEqual(lists("Paso uno, lavar. Paso dos, secar.", "es-ES"), "1. Lavar\n2. Secar")
    }

    func testOtherLanguagesStayAsSaid() {
        XCTAssertEqual(lists("First, eggs. Second, milk.", "fr-FR"), "First, eggs. Second, milk.")
        XCTAssertEqual(lists("Erstens, Eier. Zweitens, Milch.", "de-DE"), "Erstens, Eier. Zweitens, Milch.")
    }

    /// Prose that only looks like a list stays exactly as it was heard.
    func testProseStaysAsSaid() {
        let english = [
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
            "The 1st time I saw it, I had to 2nd guess myself, one of the best, I have 2 dogs.",
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
            "One of them said two words.",
            "First come, first served.",
            "Second to none.",
            "We'll do it in one, two weeks.",
            "Item one is missing.",
            "Point taken, next item please.",
            "Meet me at 1:30. 2 people are coming.",
            "That's a new line for me.",
            "Our new line of credit is ready.",
            "Third time's the charm.",
            "I came in second, and then first the next year.",
            "Last, but not least, thanks.",
            "One, I'm tired.",
            "First, let me say thanks for coming.",
            "Finally, we're done. Lastly, go home.",
            "The dash cam caught it.",
            "Number two pencils only.",
            "There are two options. One, we wait.",
        ]
        for sentence in english {
            XCTAssertEqual(lists(sentence), sentence)
        }
        let spanish = [
            "La primera vez que lo vi, me encantó.",
            "Es uno de los mejores.",
            "Tengo dos perros.",
            "Espera un segundo.",
            "Una nueva línea de productos.",
            "Primero llegó Ana y segundo llegó Luis.",
            "Uno nunca sabe.",
            "Vivo en el segundo piso.",
            "Compré una viñeta de Mafalda.",
            "Es mi primer día.",
            "Uno, dos, tres, ¡ya!",
            "En primer lugar estaba Ana.",
        ]
        for sentence in spanish {
            XCTAssertEqual(lists(sentence, "es-ES"), sentence)
        }
    }

    /// A counted microphone test is no list, in digits or still in words, and each style
    /// ends it its own way.
    func testCountsAreNoList() {
        for heard in [
            "Test 1, 2, 3.", "Test, 1, 2, 3.", "Test 1 2 3", "test one, two, three", "testing one two three",
            "counting one, two, three, four", "Counting 1, 2, 3, 4.", "1, 2, 3, testing.", "One, two, three, testing.",
        ] {
            XCTAssertEqual(lists(heard), heard)
        }
        XCTAssertEqual(
            DictationStyle.allCases.map { TranscriptFormatter.format("Test 1, 2, 3", style: $0, language: "en-US", lists: true) },
            ["Test 1, 2, 3.", "test 1, 2, 3", "Test 1, 2, 3", "Test 1, 2, 3"]
        )
    }

    /// Each style ends the lines its own way; Verbatim keeps the model's words.
    func testStylesEndTheLines() {
        let heard = "Um, so the plan is, first, um, call the bank, second, pay rent. Thanks!"
        let formatted = DictationStyle.allCases.map {
            TranscriptFormatter.format(heard, style: $0, language: "en-US", lists: true)
        }
        XCTAssertEqual(formatted, [
            "So the plan is:\n1. Call the bank.\n2. Pay rent.\nThanks!",
            "so the plan is:\n1. Call the bank\n2. Pay rent\nthanks!",
            "So the plan is:\n1. Call the bank\n2. Pay rent\nThanks!",
            heard,
        ])
        XCTAssertEqual(
            TranscriptFormatter.format("Groceries, bullet, eggs, bullet, milk.", style: .polished, language: "en-US", lists: true),
            "Groceries:\n- Eggs.\n- Milk."
        )
        XCTAssertEqual(
            TranscriptFormatter.format(heard, style: .polished, language: "en-US"),
            "So the plan is, first, call the bank, second, pay rent. Thanks!",
            "off: as before"
        )
    }

    /// End with a period off ends no list line with a full stop; "!" stays.
    func testListLinesWithoutAPeriod() {
        let heard = "Um, so the plan is, first, um, call the bank, second, pay rent. Thanks!"
        let formatted = DictationStyle.allCases.map {
            TranscriptFormatter.format(heard, style: $0, language: "en-US", lists: true, endsWithPeriod: false)
        }
        XCTAssertEqual(formatted, [
            "So the plan is:\n1. Call the bank\n2. Pay rent\nThanks!",
            "so the plan is:\n1. Call the bank\n2. Pay rent\nthanks!",
            "So the plan is:\n1. Call the bank\n2. Pay rent\nThanks!",
            heard,
        ])
        XCTAssertEqual(
            TranscriptFormatter.format("首先，买牛奶。其次，给妈妈打电话。", style: .polished, language: "zh-CN", lists: true, endsWithPeriod: false),
            "首先，买牛奶。其次，给妈妈打电话",
            "Chinese lists stay as said; the last 。 goes"
        )

        var pipeline = DictationPipeline(style: .polished, language: "en-US", formatLists: true)
        XCTAssertEqual(pipeline.format("Groceries, bullet, eggs, bullet, milk.", language: "en-US"), "Groceries:\n- Eggs.\n- Milk.")
        pipeline.endsWithPeriod = false
        XCTAssertEqual(pipeline.format("Groceries, bullet, eggs, bullet, milk.", language: "en-US"), "Groceries:\n- Eggs\n- Milk")

        let defaults = UserDefaults(suiteName: "hex.tests.\(UUID().uuidString)")!
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.dictationEndsWithPeriod, "on by default")
        settings.dictationEndsWithPeriod = false
        XCTAssertFalse(TyprSettings(defaults: defaults).dictationEndsWithPeriod)
    }

    /// The pipeline formats lists only with the switch on, and Lowercase still lowercases them.
    func testPipelineSwitchAndLowercase() {
        let heard = "First, eggs. Second, milk."
        var pipeline = DictationPipeline(style: .notes, language: "en-US")
        XCTAssertEqual(pipeline.format(heard, language: "en-US"), "- Eggs\n- Milk", "off: Notes as before")
        pipeline.formatLists = true
        XCTAssertEqual(pipeline.format(heard, language: "en-US"), "1. Eggs\n2. Milk")
        pipeline.lowercase = true
        XCTAssertEqual(pipeline.format(heard, language: "en-US"), "1. eggs\n2. milk")

        let defaults = UserDefaults(suiteName: "hex.tests.\(UUID().uuidString)")!
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.dictationFormatLists, "on by default")
        settings.dictationFormatLists = false
        XCTAssertFalse(TyprSettings(defaults: defaults).dictationFormatLists)
    }
}

/// iOS 27's speech models write "gonna", "wanna" and "gotta" (macOS 27.2's SpeechTranscriber
/// too: "I'm gonna call you later."); Polished writes them out, Casual and Verbatim keep them.
final class HexInformalContractionTests: XCTestCase {
    private func polished(_ text: String) -> String {
        TranscriptFormatter.format(text, style: .polished, language: "en-US")
    }

    func testPolishedWritesThemOut() {
        XCTAssertEqual(
            polished("I'm gonna call you later. I wanna finish this first."),
            "I'm going to call you later. I want to finish this first."
        )
        XCTAssertEqual(polished("I gotta go, lemme know. It's kinda late"), "I got to go, let me know. It's kind of late.")
        XCTAssertEqual(polished("Gonna be a long day."), "Going to be a long day.")
        XCTAssertEqual(polished("ok. wanna grab lunch?"), "Ok. Want to grab lunch?")
    }

    func testQuotesNamesAndOtherWordsStay() {
        XCTAssertEqual(polished("He said \"I'm gonna win\" and left."), "He said \"I'm gonna win\" and left.")
        XCTAssertEqual(polished("She sang “Wanna Be Startin' Somethin'” all night."), "She sang “Wanna Be Startin' Somethin'” all night.")
        XCTAssertEqual(polished("We played Gonna Fly Now on repeat."), "We played Gonna Fly Now on repeat.")
        XCTAssertEqual(polished("The gonnabe kinds and the wannabes."), "The gonnabe kinds and the wannabes.")
        XCTAssertEqual(
            TranscriptFormatter.format("Voy a gonna mañana.", style: .polished, language: "es-ES"),
            "Voy a gonna mañana.",
            "English only"
        )
    }

    func testCasualAndVerbatimKeepThem() {
        let heard = "I'm gonna be late, wanna start without me?"
        XCTAssertEqual(TranscriptFormatter.format(heard, style: .casual, language: "en-US"), "i'm gonna be late, wanna start without me?")
        XCTAssertEqual(TranscriptFormatter.format(heard, style: .verbatim, language: "en-US"), heard)
    }

    func testListItems() {
        XCTAssertEqual(
            TranscriptFormatter.format("First, gonna call Sam. Second, wanna book the hotel.", style: .polished, language: "en-US", lists: true),
            "1. Going to call Sam.\n2. Want to book the hotel."
        )
        XCTAssertEqual(
            TranscriptFormatter.format("Todo bullet gotta pack bullet lemme check the car", style: .polished, language: "en-US", lists: true),
            "Todo:\n- Got to pack.\n- Let me check the car."
        )
    }
}

/// X (Philippe): "When dictating, in some languages punctuation has a space before, like
/// question and exclamation marks in French. Right now they're not inserted." French puts a
/// narrow no-break space before ? ! ; and a no-break space before : and inside « » (Canada none
/// before ? ! ;, Switzerland narrow ones inside « »). The texts are Apple Speech's (macOS 27.2.1,
/// say -v Thomas and Amélie): fr-FR and fr-CH write "ça va ?" with a plain space, fr-CA's
/// DictationTranscriber "ça va?", and the styles took the space out.
final class HexFrenchSpacingTests: XCTestCase {
    private let thin = "\u{202F}"
    private let nbsp = "\u{00A0}"

    func testFrenchGetsItsSpacesAfterTheStyle() {
        let heard = "Bonjour, comment ça va ? Tu viens ce soir ?"
        let pipeline = DictationPipeline(style: .polished, language: "fr-FR")
        XCTAssertEqual(pipeline.format(heard, language: "fr-FR"), "Bonjour, comment ça va\(thin)? Tu viens ce soir\(thin)?")
        XCTAssertEqual(
            pipeline.format("il y a trois choses: le pain; le lait et «les œufs» ! c'est tout", language: "fr-FR"),
            "Il y a trois choses\(nbsp): le pain\(thin); le lait et «\(nbsp)les œufs\(nbsp)»\(thin)! C'est tout."
        )
        var casual = DictationPipeline(style: .casual, language: "fr-FR")
        XCTAssertEqual(casual.format("Tu viens ce soir ? Génial !", language: "fr-FR"), "tu viens ce soir\(thin)? génial\(thin)!")
        casual.lowercase = true
        XCTAssertEqual(casual.format("Tu viens ?", language: "fr-FR"), "tu viens\(thin)?")
        XCTAssertEqual(DictationPipeline(style: .notes, language: "fr-FR").format("Tu viens ?", language: "fr-FR"), "Tu viens\(thin)?")
        XCTAssertEqual(
            DictationPipeline(style: .verbatim, language: "fr-FR").format(heard, language: "fr-FR"), heard,
            "Verbatim keeps the model's spaces"
        )
        XCTAssertEqual(DictationPipeline(style: .polished, language: "en-US").format("Really ? Yes", language: "en-US"), "Really? Yes.")
        XCTAssertEqual(
            DictationPipeline(style: .polished, language: "en-US").format("Tu viens ?", language: "fr-FR"),
            "Tu viens\(thin)?",
            "a translation into French is spaced as French"
        )
    }

    func testCanadaAndSwitzerlandFollowTheirOwn() {
        let canada = DictationPipeline(style: .polished, language: "fr-CA")
        XCTAssertEqual(canada.format("Bonjour, comment ça va? Tu viens ce soir?", language: "fr-CA"), "Bonjour, comment ça va? Tu viens ce soir?")
        XCTAssertEqual(FrenchSpacing.apply("ça va ? Oui ! Voici : «tout»", language: "fr-CA"), "ça va? Oui! Voici\(nbsp): «\(nbsp)tout\(nbsp)»")
        XCTAssertEqual(
            FrenchSpacing.apply("ça va ? Voici : « tout »", language: "fr-CH"),
            "ça va\(thin)? Voici\(nbsp): «\(thin)tout\(thin)»"
        )
        XCTAssertEqual(FrenchSpacing.convention(for: "fr-BE"), .france)
        XCTAssertEqual(FrenchSpacing.convention(for: "fr"), .france)
        XCTAssertNil(FrenchSpacing.convention(for: "en-CA"))
        XCTAssertNil(FrenchSpacing.convention(for: nil))
    }

    func testNoDoubledSpacesAndNothingOutsideWords() {
        let once = FrenchSpacing.apply("ça va  ?\nOui\(nbsp)! Quoi ?!", language: "fr-FR")
        XCTAssertEqual(once, "ça va\(thin)?\nOui\(thin)! Quoi\(thin)?!")
        XCTAssertEqual(FrenchSpacing.apply(once, language: "fr-FR"), once, "running twice changes nothing")
        let untouched = [
            "Rendez-vous à 10:30 ou 18:45",
            "Super :) et ;-) puis :D et :(",
            "Va sur https://exemple.fr/page?q=1",
            "Écris moi@exemple.fr! ou www.exemple.fr?",
            "Tape `a ? b : c` puis `x::y`",
            "? au début\n: en début de ligne",
        ]
        for text in untouched {
            XCTAssertEqual(FrenchSpacing.apply(text, language: "fr-FR"), text, text)
        }
        XCTAssertEqual(FrenchSpacing.apply("Il m'a dit «Tu viens?»", language: "fr-FR"), "Il m'a dit «\(nbsp)Tu viens\(thin)?\(nbsp)»")
    }
}

/// Settings › Dictation › Spoken punctuation. The inputs are what the speech models wrote for
/// spoken punctuation (macOS 27.2.1, `say` voices Samantha, Paulina, Thomas, Anna, Alice and
/// Luciana): Apple's SpeechTranscriber, which leaves most names as words, and Parakeet (desktop
/// Hex's unified English model), which leaves every one.
final class HexSpokenPunctuationTests: XCTestCase {
    private func punctuated(_ text: String, _ language: String = "en-US") -> String {
        SpokenPunctuation.format(text, language: language)
    }

    func testEnglishFromSpeechTranscriber() {
        XCTAssertEqual(punctuated("That is amazing exclamation point."), "That is amazing!")
        XCTAssertEqual(punctuated("That is amazing exclamation mark."), "That is amazing!")
        XCTAssertEqual(punctuated("I came semicolon, I saw semicolon, I conquered."), "I came; I saw; I conquered.")
        XCTAssertEqual(punctuated("It was good dash really good."), "It was good – really good.")
        XCTAssertEqual(punctuated("It is a well hyphen known fact."), "It is a well-known fact.")
        XCTAssertEqual(punctuated("She said, open quote, hello, their close quote, and left."), "She said, “hello, their”, and left.")
        XCTAssertEqual(punctuated("Call me, open Paren after lunch close, Paren, please."), "Call me, (after lunch), please.")
        XCTAssertEqual(punctuated("Wait for it, ellipsis."), "Wait for it…")
        XCTAssertEqual(punctuated("Feeling great hashtag blessed."), "Feeling great #blessed.")
        XCTAssertEqual(punctuated("Great job, Smiley."), "Great job :-)")
        XCTAssertEqual(punctuated("It is John Apostrophe S Carr."), "It is John's Carr.")
        XCTAssertEqual(punctuated("Open parenthesis, just getting close parenthesis."), "(just getting).")
        XCTAssertEqual(punctuated("Thanks so much, exclamation point CU tomorrow period."), "Thanks so much! CU tomorrow.")
        XCTAssertEqual(
            punctuated("Okay, comma, so here is the thing, comment, I can't make it."),
            "Okay, so here is the thing, comment, I can't make it."
        )
        XCTAssertEqual(punctuated("I'll be there at noon, see you soon."), "I'll be there at noon, see you soon.", "converted already")
    }

    func testEnglishFromParakeet() {
        XCTAssertEqual(punctuated("I'll be there at noon, comma, see you soon, period"), "I'll be there at noon, see you soon.")
        XCTAssertEqual(punctuated("Are you coming tonight question mark?"), "Are you coming tonight?", "never doubled")
        XCTAssertEqual(punctuated("Here is the plan colon we leave at noon full stop."), "Here is the plan: we leave at noon.")
        XCTAssertEqual(punctuated("It is a well-hyphen known fact"), "It is a well-known fact")
        XCTAssertEqual(punctuated("She said open quote hello there close quote and left."), "She said “hello there” and left.")
        XCTAssertEqual(punctuated("Open parenthesis just kidding close parenthesis."), "(just kidding).")
        XCTAssertEqual(
            punctuated("Thanks so much exclamation point see you tomorrow period."),
            "Thanks so much! See you tomorrow."
        )
        XCTAssertEqual(punctuated("Hi Sarah comma\nthanks for the update period"), "Hi Sarah,\nthanks for the update.")
    }

    func testEnglishCommands() {
        XCTAssertEqual(punctuated("Hi Sarah comma how are you question mark"), "Hi Sarah, how are you?")
        XCTAssertEqual(punctuated("I'm on my way period see you soon"), "I'm on my way. See you soon")
        XCTAssertEqual(punctuated("Note to self colon buy milk"), "Note to self: buy milk")
        XCTAssertEqual(punctuated("Dear John comma"), "Dear John,")
        XCTAssertEqual(punctuated("Can you send it today question mark thanks"), "Can you send it today? Thanks")
        XCTAssertEqual(punctuated("Meet me at 5 period"), "Meet me at 5.")
        XCTAssertEqual(punctuated("Who are you going with question mark"), "Who are you going with?")
        XCTAssertEqual(punctuated("He said open quote no way close quote period"), "He said “no way”.")
        XCTAssertEqual(punctuated("He said quote I'm fine unquote and left"), "He said “I'm fine” and left")
        XCTAssertEqual(punctuated("Hashtag throwback"), "#throwback")
        XCTAssertEqual(punctuated("It costs dollar sign 50"), "It costs $50")
        XCTAssertEqual(punctuated("Escríbeme a ana arroba gmail.com", "es-ES"), "Escríbeme a ana@gmail.com")
        XCTAssertEqual(punctuated("Bring snacks open paren chips or pretzels close paren"), "Bring snacks (chips or pretzels)")
        XCTAssertEqual(punctuated("Love you smiley face"), "Love you :-)")
        XCTAssertEqual(punctuated("Okay comma sounds good period"), "Okay, sounds good.")
        XCTAssertEqual(punctuated("Thanks exclamation point exclamation point"), "Thanks!")
    }

    /// Apple's DictationTranscriber writes the marks itself; its text passes through.
    func testDictationTranscriberTextStays() {
        for text in [
            "That is amazing!", "Here is the plan: we leave at noon.", "I came; I saw; I conquered",
            "It was good – really good", "She said \"hello there\" and left", "Call me (after lunch) please",
            "Wait for it…", "Email me a john@gmail.com", "Feeling great. #Blessed.", "Great job :-)",
            "It is John's car", "Hi Sarah,\nThanks for the update.", "He has a? Tattoo on his arm.",
            "Thanks so much! See you tomorrow.",
        ] {
            XCTAssertEqual(punctuated(text), text)
        }
    }

    func testSpanish() {
        XCTAssertEqual(punctuated("Llego mañana, punto nos vemos", "es-ES"), "Llego mañana. Nos vemos")
        XCTAssertEqual(punctuated("Dijo abrir comillas sola, cerrar comillas si se fue.", "es-ES"), "Dijo “sola” si se fue.")
        XCTAssertEqual(
            punctuated("Llámame a abrir paréntesis después de comer, cerrar paréntesis.", "es-MX"),
            "Llámame a (después de comer)."
        )
        XCTAssertEqual(punctuated("Espera puntos suspensivos.", "es-ES"), "Espera…")
        XCTAssertEqual(
            punctuated("Abrir signo de interrogación vienes cerrar signo de interrogación", "es-ES"),
            "¿vienes?"
        )
        XCTAssertEqual(punctuated("Hola coma Juan punto y aparte nos vemos", "es-ES"), "Hola, Juan.\n\nNos vemos")
        XCTAssertEqual(punctuated("Gracias coma nos vemos mañana punto", "es-ES"), "Gracias, nos vemos mañana.")
        XCTAssertEqual(punctuated("Vine punto y coma vi", "es-ES"), "Vine; vi")
        XCTAssertEqual(punctuated("Es genial signo de exclamación", "es-ES"), "Es genial!")
        XCTAssertEqual(punctuated("La lista dos puntos pan y leche", "es-ES"), "La lista dos puntos pan y leche", "two points, maybe")
    }

    func testFrench() {
        XCTAssertEqual(punctuated("Bonjour virgule comment ça va point d'interrogation", "fr-FR"), "Bonjour, comment ça va?")
        XCTAssertEqual(punctuated("Je suis venu, point, j'ai vu", "fr-FR"), "Je suis venu. J'ai vu")
        XCTAssertEqual(punctuated("Je suis venu point-virgule j'ai vu", "fr-FR"), "Je suis venu; j'ai vu")
        XCTAssertEqual(punctuated("C'est génial point d’exclamation", "fr-FR"), "C'est génial!")
        XCTAssertEqual(
            punctuated("Il a dit ouvrez les guillemets bonjour, fermez les guillemets", "fr-FR"),
            "Il a dit «bonjour»"
        )
        XCTAssertEqual(punctuated("Appelle-moi ouvrir la parenthèse après le déjeuner", "fr-CA"), "Appelle-moi (après le déjeuner")

        // French spacing comes after, in the pipeline.
        let pipeline = DictationPipeline(style: .polished, language: "fr-FR", spokenPunctuation: true)
        XCTAssertEqual(
            pipeline.format("bonjour virgule comment ça va point d'interrogation", language: "fr-FR"),
            "Bonjour, comment ça va\u{202F}?"
        )
        XCTAssertEqual(
            pipeline.format("il a dit ouvrez les guillemets bonjour fermez les guillemets", language: "fr-FR"),
            "Il a dit «\u{00A0}bonjour\u{00A0}»."
        )
    }

    func testGerman() {
        XCTAssertEqual(punctuated("Der Plan Doppelpunkt, wir gehen um 12.", "de-DE"), "Der Plan: wir gehen um 12.")
        XCTAssertEqual(punctuated("Er sagte Anführungszeichen Hallo, Abführungszeichen.", "de-DE"), "Er sagte „Hallo“.")
        XCTAssertEqual(
            punctuated("Er sagte Anführungszeichen unten Hallo, Anführungszeichen oben.", "de-DE"),
            "Er sagte „Hallo“."
        )
        XCTAssertEqual(punctuated("Ich kam Semikolon ich sah", "de-DE"), "Ich kam; ich sah")
        XCTAssertEqual(punctuated("Warte Auslassungspunkte", "de-DE"), "Warte…")
        XCTAssertEqual(punctuated("Ich komme morgen Punkt bis bald", "de-DE"), "Ich komme morgen. Bis bald")
        XCTAssertEqual(punctuated("Hallo Komma wie geht es dir Fragezeichen", "de-AT"), "Hallo, wie geht es dir?")
        XCTAssertEqual(punctuated("Danke für das Update Punkt", "de-DE"), "Danke für das Update.")
        XCTAssertEqual(punctuated("Ruf mich an Punkt", "de-DE"), "Ruf mich an.")
        XCTAssertEqual(punctuated("Ruf mich an Klammer auf nach dem Essen Klammer zu", "de-DE"), "Ruf mich an (nach dem Essen)")
    }

    func testItalian() {
        XCTAssertEqual(punctuated("Ciao virgola come stai punto interrogativo", "it-IT"), "Ciao, come stai?")
        XCTAssertEqual(punctuated("Chiamami, apri parentesi dopo pranzo)", "it-IT"), "Chiamami, (dopo pranzo)")
        XCTAssertEqual(punctuated("Ha detto apri virgolette ciao chiudi virgolette", "it-IT"), "Ha detto “ciao”")
        XCTAssertEqual(punctuated("Sono venuto punto e virgola ho visto", "it-IT"), "Sono venuto; ho visto")
        XCTAssertEqual(punctuated("È fantastico punto esclamativo", "it-IT"), "È fantastico!")
        XCTAssertEqual(punctuated("Arrivo domani punto a presto", "it-IT"), "Arrivo domani. A presto")
    }

    func testPortuguese() {
        XCTAssertEqual(punctuated("Olá vírgula tudo bem?", "pt-BR"), "Olá, tudo bem?")
        XCTAssertEqual(punctuated("Chego amanhã ponto final até logo.", "pt-BR"), "Chego amanhã. Até logo.")
        XCTAssertEqual(punctuated("Ele disse abre aspas ou lá fecha aspas.", "pt-BR"), "Ele disse “ou lá”.")
        XCTAssertEqual(
            punctuated("Me liga abre parênteses depois do almoço fecha parênteses.", "pt-PT"),
            "Me liga (depois do almoço)."
        )
        XCTAssertEqual(punctuated("Eu vim ponto e vírgula eu vi.", "pt-BR"), "Eu vim; eu vi.")
        XCTAssertEqual(punctuated("É incrível o ponto de exclamação!", "pt-BR"), "É incrível o ponto de exclamação!", "after an article")
    }

    /// Everyday sentences that use the names as words: none may change.
    func testProseStaysAsSaid() {
        let english = [
            "It was a long period of time.",
            "The comma is optional here.",
            "She put a dash of salt in the soup.",
            "He has a question mark tattoo on his arm.",
            "The colon is part of the digestive system.",
            "Put a period at the end of the sentence.",
            "I'm not sure what the hashtag is.",
            "The trial period ends tomorrow.",
            "There's a big question mark over his future.",
            "My period started this morning.",
            "We had a free period after lunch.",
            "The grace period is thirty days.",
            "Do you use the Oxford comma?",
            "She made a mad dash for the door.",
            "I watched a period drama last night.",
            "He was diagnosed with colon cancer.",
            "My dash cam caught the whole thing.",
            "Add a dash of lemon juice.",
            "The hyphen in that word is wrong.",
            "Use an apostrophe for possession.",
            "That hashtag is trending right now.",
            "What does the at sign mean in an email?",
            "He ended the call with a smiley face emoji.",
            "During that period we lived in Boston.",
            "The question mark key is broken.",
            "An exclamation point at the end feels too loud.",
            "Commas and periods go inside the quotes.",
            "Is that a comma or a period?",
            "I need a quote for the kitchen remodel.",
            "Can you quote me on that?",
            "He used air quotes around the word.",
            "The open quote was missing.",
            "It's a quote unquote expert opinion.",
            "The time period doesn't matter.",
            "He's in colon surgery right now.",
            "Every comma counts in a contract.",
            "That was the last period of the game.",
            "They scored in the third period.",
            "A semicolon joins two clauses.",
            "The ellipsis at the end looks passive aggressive.",
            "Click the dollar sign to see prices.",
            "Type the hashtag before the word.",
            "A smiley can soften a message.",
            "Draw a dash between the numbers.",
            "The comma-separated list is attached.",
            "The waiting period was annoying.",
            "Can you dash off a quick reply?",
            "We need to dash to the store.",
            "I'll dash home after work.",
            "This colon cleanse is a scam.",
            "Her period was late this month.",
            "What a period of growth for the company.",
            "The comma after Hi is optional.",
            "I love the Oxford comma debate.",
            "The quote from the plumber was too high.",
            "The ten-year period ended in June.",
            "That was a really tough period for us.",
            "It happened over a short period.",
            "The colon in the time looks wrong.",
            "Where is the question mark on this keyboard?",
            "Is there an exclamation mark in the title?",
            "My dog is called Dash.",
            "I'll text Dash later.",
            "George Smiley is a spy.",
            "We waited for a period of hours.",
            "The Jurassic period was long ago.",
            "Your period tracker sent a notification.",
            "Use a colon before a list.",
            "The dollar sign is missing.",
            "No comma needed.",
            "I used comma separated values.",
            "Period cramps are the worst.",
            "Comma placement matters.",
            "That smiley was a bit much.",
            "Leave the quote as it is.",
            "Write an exclamation point if you're excited.",
            "She's the period expert on the team.",
            "Hashtags are everywhere.",
            "Quote me if you want.",
            "He gave a quote to the press.",
            "In the past, period films were huge.",
            "Colon health is important.",
            "The first period starts at eight.",
            "Send a smiley to Mom.",
        ]
        let others: [(String, [String])] = [
            ("es-ES", [
                "El punto de vista es claro.",
                "La coma es opcional.",
                "Es un punto de encuentro.",
                "Entró en coma ayer.",
                "Tres coma cinco.",
                "Ganamos por dos puntos.",
                "Ese es el punto.",
                "Está en su punto.",
                "Hay dos puntos de vista.",
                "Escribió el guion de la película.",
                "Lo dijo entre comillas.",
                "Pon una coma aquí.",
                "El paciente sigue en coma.",
                "Llegamos al punto de partida.",
            ]),
            ("fr-FR", [
                "C'est un point important.",
                "La virgule est facultative.",
                "Deux points de vue différents.",
                "Le point de vue est clair.",
                "Il a marqué deux points.",
                "Mettez une virgule ici.",
                "Entre guillemets c'est faux.",
                "Un tiret suffit.",
                "C'est mon point fort.",
                "On fait le point demain.",
                "La cuisson à point.",
            ]),
            ("de-DE", [
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
            ]),
            ("it-IT", [
                "Il punto è questo.",
                "Un punto di vista diverso.",
                "La virgola è facoltativa.",
                "Ho fatto due punti.",
                "È un buon punto.",
                "Siamo al punto di partenza.",
                "Metti una virgola qui.",
                "Lo ha detto tra virgolette.",
                "Il trattino è corto.",
                "Facciamo il punto della situazione.",
            ]),
            ("pt-BR", [
                "O ponto de vista é claro.",
                "Esse é o ponto principal.",
                "A vírgula é opcional.",
                "Ganhamos por dois pontos.",
                "Esse é um bom ponto.",
                "Ele falou entre aspas.",
                "Coloque um hífen aqui.",
                "Estou no ponto de ônibus.",
                "Chegamos ao ponto final da viagem.",
                "Faltou uma vírgula.",
            ]),
        ]
        XCTAssertGreaterThanOrEqual(english.count, 60)
        for sentence in english {
            XCTAssertEqual(punctuated(sentence), sentence)
        }
        for (language, sentences) in others {
            for sentence in sentences {
                XCTAssertEqual(punctuated(sentence, language), sentence, language)
            }
        }
        // Numbers: a decimal or a time stays as said.
        XCTAssertEqual(punctuated("It costs two comma five million"), "It costs two comma five million")
        XCTAssertEqual(punctuated("The meeting is at 3 colon 30"), "The meeting is at 3 colon 30")
        XCTAssertEqual(punctuated("Tres coma cinco", "es-ES"), "Tres coma cinco")
        XCTAssertEqual(punctuated("Zwei Komma fünf Prozent", "de-DE"), "Zwei Komma fünf Prozent")
    }

    /// A closing name needs an open quote or bracket; a bare "quote" needs a closing one.
    func testQuotesAndBracketsPair() {
        XCTAssertEqual(punctuated("Close quote that"), "Close quote that")
        XCTAssertEqual(punctuated("He was fine close paren"), "He was fine close paren")
        XCTAssertEqual(punctuated("Can you quote me on that"), "Can you quote me on that")
        XCTAssertEqual(punctuated("He said \"hi end quote"), "He said \"hi\"", "a straight quote closes straight")
        XCTAssertEqual(punctuated("Lo dijo entre comillas", "es-ES"), "Lo dijo entre comillas")
    }

    func testOtherLanguagesStayAsSaid() {
        XCTAssertEqual(punctuated("Hallo komma", "nl-NL"), "Hallo komma")
        XCTAssertEqual(punctuated("你好逗号", "zh-CN"), "你好逗号")
    }

    /// Polished, Casual and Notes write the marks, Verbatim keeps the words, and the pipeline
    /// writes them only with the switch on (on by default).
    func testStylesAndPipeline() {
        let heard = "Okay comma so here is the plan colon we leave at noon period see you there exclamation point"
        let formatted = DictationStyle.allCases.map {
            TranscriptFormatter.format(heard, style: $0, language: "en-US", punctuation: true)
        }
        XCTAssertEqual(formatted, [
            "Okay, so here is the plan: we leave at noon. See you there!",
            "okay so here is the plan: we leave at noon. see you there!",
            "- So here is the plan: we leave at noon\n- See you there!",
            heard,
        ])
        XCTAssertEqual(
            TranscriptFormatter.format("love you smiley face", style: .polished, language: "en-US", punctuation: true),
            "Love you :-)"
        )

        var pipeline = DictationPipeline(style: .polished, language: "en-US")
        XCTAssertEqual(pipeline.format("Wow exclamation point", language: "en-US"), "Wow exclamation point.", "off")
        pipeline.spokenPunctuation = true
        XCTAssertEqual(pipeline.format("Wow exclamation point", language: "en-US"), "Wow!")
        pipeline.formatLists = true
        XCTAssertEqual(
            pipeline.format("Hi Sarah comma new line thanks for the update period", language: "en-US"),
            "Hi Sarah,\nThanks for the update."
        )
        XCTAssertEqual(
            pipeline.format("Groceries, dash, eggs, dash, milk.", language: "en-US"),
            "Groceries:\n- Eggs.\n- Milk.",
            "a spoken list's dashes stay bullets"
        )
        pipeline.lowercase = true
        XCTAssertEqual(pipeline.format("Wow exclamation point", language: "en-US"), "wow!")

        let defaults = UserDefaults(suiteName: "hex.tests.\(UUID().uuidString)")!
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.dictationSpokenPunctuation, "on by default")
        settings.dictationSpokenPunctuation = false
        XCTAssertFalse(TyprSettings(defaults: defaults).dictationSpokenPunctuation)
    }
}
