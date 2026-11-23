import XCTest
@testable import Typr

final class HexSpokenHesitationsTests: XCTestCase {
    func testPreservesEverySourceLineSeparatorAndUntouchedSpacing() {
        for separator in ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"] {
            let heard = "  Er kommt morgen." + separator + separator + "\tSie bleibt, äh,  hier. "
            let expected = "  Er kommt morgen." + separator + separator + "\tSie bleibt,  hier. "
            XCTAssertEqual(
                Array(HexSpokenHesitations.remove(from: heard, language: "de-DE").utf8),
                Array(expected.utf8),
                separator.debugDescription
            )
        }
        XCTAssertEqual(HexSpokenHesitations.remove(from: "Danke äh\r\nBis dann.", language: "de"),
                       "Danke\r\nBis dann.")
    }

    func testTransfersSentencePunctuationAndClosingQuotes() {
        let examples = [
            ("Danke, äh. Bis dann.", "Danke. Bis dann."),
            ("Danke äh, ähm. Bis dann.", "Danke. Bis dann."),
            ("Danke äh. ähm. Bis dann.", "Danke. Bis dann."),
            ("Danke... äh. Bis dann.", "Danke... Bis dann."),
            ("Danke äh… Bis dann.", "Danke… Bis dann."),
            ("Danke äh... Bis dann.", "Danke... Bis dann."),
            ("Er sagte: „Danke äh.” Bis dann.", "Er sagte: „Danke.” Bis dann."),
            ("Er sagte: „Danke äh.“ Bis dann.", "Er sagte: „Danke.“ Bis dann."),
            ("Er sagte: „Danke... äh.“ Bis dann.", "Er sagte: „Danke...“ Bis dann."),
            ("Er sagte: (Danke ähm.) Bis dann.", "Er sagte: (Danke.) Bis dann."),
            ("Er sagte: „(Danke ähm.)“ Bis dann.", "Er sagte: „(Danke.)“ Bis dann."),
            ("Er sagte: „Danke äh“ leise.", "Er sagte: „Danke“ leise."),
            ("Er sagte: „Danke äh.“ ähm. Bis dann.", "Er sagte: „Danke.“ Bis dann."),
            ("Er sagte: „Danke äh. ähm“ bis dann.", "Er sagte: „Danke.“ bis dann."),
            ("Erste Option äh; danach weiter.", "Erste Option; danach weiter."),
            ("Die Optionen, äh: Milch und Eier.", "Die Optionen: Milch und Eier."),
            ("Ich kann am Montag äh. Nein, Dienstag passt besser.", "Ich kann am Montag. Nein, Dienstag passt besser."),
        ]
        for (heard, expected) in examples {
            XCTAssertEqual(HexSpokenHesitations.remove(from: heard, language: "de"), expected, heard)
        }
    }

    func testAppliesTheSameBoundaryRuleAcrossHexLocales() {
        for language in ["es", "es-ES", "nb", "nb-NO", "nn", "nn-NO", "no"] {
            XCTAssertEqual(HexSpokenHesitations.remove(from: "Danke, eh, ehm. Weiter.", language: language),
                           "Danke. Weiter.", language)
            XCTAssertEqual(HexSpokenHesitations.remove(from: "«Merci eh…»\r\nEncore.", language: language),
                           "«Merci…»\r\nEncore.", language)
        }
    }

    func testLeavesUnsupportedLanguagesAndNonHesitationsByteIdentical() {
        let heard = "\tÄh, danke eh.\r\n"
        for language in [nil, "en-US", "fr-FR", "sv-SE", "da-DK"] {
            XCTAssertEqual(Array(HexSpokenHesitations.remove(from: heard, language: language).utf8),
                           Array(heard.utf8))
        }
        for text in ["Das ist eh egal.", "Hm? Wirklich!", "„Äh.“ sagte sie.", "Gut, ähm?” Weiter.",
                     "Sie sagte: „Danke\näh.“", "Sie sagte: („Danke äh.“ ähm.)",
                     "Am Montag, nein, am Dienstag.", "\t\r\n "] {
            XCTAssertEqual(HexSpokenHesitations.remove(from: text, language: "de"), text)
        }
    }

    func testKeepsGermanAbbreviationsAndDatesIntact() {
        let heard = "Wir sehen uns am 3. äh Oktober gegen ca. äh zehn. Bring z. B. äh die Unterlagen mit."
        let clean = HexSpokenHesitations.remove(from: heard, language: "de")
        XCTAssertEqual(clean, "Wir sehen uns am 3. Oktober gegen ca. zehn. Bring z. B. die Unterlagen mit.")
        XCTAssertEqual(TranscriptFormatter.format(clean, style: .notes, language: "de"),
                       "- Wir sehen uns am 3. Oktober gegen ca. zehn\n- Bring z. B. die Unterlagen mit")
    }
}
