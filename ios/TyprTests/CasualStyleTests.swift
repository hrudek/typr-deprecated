import XCTest
@testable import Typr

final class CasualStyleTests: XCTestCase {
    func testChatStylesDifferOnlyInCapitalization() {
        let cases: [(String, String, String)] = [
            ("ähm ich treffe Anna im Büro. danach komme ich.",
             "Ich treffe Anna im Büro. Danach komme ich", "ich treffe anna im büro. danach komme ich"),
            ("Sounds good. See you tomorrow.", "Sounds good. See you tomorrow", "sounds good. see you tomorrow"),
            ("kommst du? ich warte.", "Kommst du? Ich warte", "kommst du? ich warte"),
            ("hallo! alles gut?", "Hallo! Alles gut?", "hallo! alles gut?"),
            ("ich nutze iPhone und GitHub.", "Ich nutze iPhone und GitHub", "ich nutze iphone und github"),
            ("ich komme um 13 Uhr bzw. etwas später.", "Ich komme um 13 Uhr bzw. etwas später", "ich komme um 13 uhr bzw. etwas später"),
            ("  klingt gut . dann bis morgen . \n", "Klingt gut. Dann bis morgen", "klingt gut. dann bis morgen"),
            ("", "", ""),
        ]
        for (raw, casual, veryCasual) in cases {
            XCTAssertEqual(TyprTranscriptFormatter.format(raw, style: .typrCasual), casual, raw)
            XCTAssertEqual(TyprTranscriptFormatter.format(raw, style: .casual), veryCasual, raw)
        }
    }

    /// Stored values never change: "casual" (Typr's old Very casual) is Hex's Casual, and
    /// Typr's Casual ("casualCapitalized") is a style only with Typr dictation styles on.
    func testStoredStylesDecodeWithHexSemantics() throws {
        XCTAssertEqual(DictationStyle(rawValue: "casual"), .casual)
        XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: Data("\"casual\"".utf8)), .casual)
        XCTAssertEqual(DictationStyle(rawValue: "casualCapitalized"), .typrCasual)
        XCTAssertEqual(DictationStyle.choices(typrStyles: false), [.polished, .casual, .notes, .verbatim])
        XCTAssertEqual(DictationStyle.choices(typrStyles: true), [.polished, .typrCasual, .casual, .notes, .verbatim])
        XCTAssertEqual(DictationStyle.casual.label(typrStyles: false), "Casual")
        XCTAssertEqual(DictationStyle.casual.label(typrStyles: true), "Very casual")
        XCTAssertEqual(DictationStyle.typrCasual.label(typrStyles: true), "Casual")
        for style in DictationStyle.choices(typrStyles: true) {
            XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: JSONEncoder().encode(style)), style)
            XCTAssertEqual(DictationStyle(rawValue: style.rawValue), style)
            let request = KeyboardLaunchRequest.startRecording(jobID: "style-test", requestedAt: 100, style: style, host: nil)
            XCTAssertEqual(KeyboardLaunchRequest(url: request.url), request)
        }
    }

    @MainActor
    func testCapturedLogStylesCannotCollideWithHistoricalCasualLabel() throws {
        let typrStyles = DictationStyle.typrStylesEnabled
        for (style, expected) in [(DictationStyle.typrCasual, "Casual (natural case)"),
                                  (.casual, typrStyles ? "Very casual" : "Casual (texting)")] {
            let context = DictationLogContext.capture(
                keyboardJob: false, copyToPasteboard: false, style: style,
                engine: "test", language: "de", duration: 1,
                loudestAverage: nil, cleanupPath: .none, vocabularyCount: 0
            )
            XCTAssertEqual(context.style, expected)
            XCTAssertNotEqual(context.style, "Casual")
            let decoded = try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(context))
            XCTAssertEqual(decoded.style, expected)
        }
        var historic = DictationLogContext()
        historic.style = "Casual"
        let decoded = try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(historic))
        XCTAssertEqual(decoded.style, "Casual")
    }

    /// A saved Typr Casual reads as Polished while Typr dictation styles is off, with the stored
    /// value kept for when it is on again.
    @MainActor
    func testSavedStyleSelectionFallsBackWhileTyprStylesAreOff() {
        let suite = "typr.tests.casual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.style = .casual
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style, .casual)
        bridge.style = .typrCasual
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style,
                       DictationStyle.typrStylesEnabled ? .typrCasual : .polished)
        XCTAssertEqual(defaults.string(forKey: "settings.dictationStyle"), "casualCapitalized")
    }

    func testPipelineFallsBackToPolishedForUnavailableStyle() {
        let suite = "typr.tests.casual.pipeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        let vocabulary = DictationVocabulary(userTerms: [])
        XCTAssertEqual(DictationPipeline(style: .typrCasual, language: .german, vocabulary: vocabulary,
                                         settings: settings).style, .polished)
        settings[experiment: .typrDictationStyles] = true
        XCTAssertEqual(DictationPipeline(style: .typrCasual, language: .german, vocabulary: vocabulary,
                                         settings: settings).style, .typrCasual)
    }
}
