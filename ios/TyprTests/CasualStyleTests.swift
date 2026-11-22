import XCTest
@testable import Typr

/// Hex's four styles (anomalyco/hex `ios/HEXShared/TranscriptFormatter.swift` at 0c1c13d7).
final class CasualStyleTests: XCTestCase {
    func testStylesAreHexsFourWithHexsNamesAndHints() {
        XCTAssertEqual(DictationStyle.allCases, [.polished, .casual, .notes, .verbatim])
        XCTAssertEqual(DictationStyle.allCases.map(\.label), ["Polished", "Casual", "Notes", "Verbatim"])
        XCTAssertEqual(DictationStyle.allCases.map(\.shortHint), [
            "Full sentences, fillers trimmed",
            "Texting: lowercase start, no final period",
            "Short lines, a list for several items",
            "Exact words from the model",
        ])
        XCTAssertEqual(DictationStyle.verbatim.next, .polished)
    }

    /// Stored values never change: "casual" is Hex's Casual; an earlier Typr-only style
    /// ("casualCapitalized") no longer parses.
    func testStoredStylesDecodeWithHexSemantics() throws {
        XCTAssertEqual(DictationStyle(rawValue: "casual"), .casual)
        XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: Data("\"casual\"".utf8)), .casual)
        XCTAssertNil(DictationStyle(rawValue: "casualCapitalized"))
        for style in DictationStyle.allCases {
            XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: JSONEncoder().encode(style)), style)
            let request = KeyboardLaunchRequest.startRecording(jobID: "style-test", requestedAt: 100, style: style, host: nil)
            XCTAssertEqual(KeyboardLaunchRequest(url: request.url), request)
        }
    }

    @MainActor
    func testCapturedLogStylesCannotCollideWithHistoricalCasualLabel() throws {
        let context = DictationLogContext.capture(
            keyboardJob: false, copyToPasteboard: false, style: .casual,
            engine: "test", language: "de", duration: 1,
            loudestAverage: nil, cleanupPath: .none, vocabularyCount: 0
        )
        XCTAssertEqual(context.style, "Casual (texting)")
        let decoded = try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded.style, "Casual (texting)")
        var historic = DictationLogContext()
        historic.style = "Casual"
        XCTAssertEqual(try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(historic)).style, "Casual")
    }

    /// A saved Typr-only style reads as Polished, with the stored value left as it was.
    @MainActor
    func testSavedTyprStyleFallsBackToPolished() {
        let suite = "typr.tests.casual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.style = .casual
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style, .casual)
        defaults.set("casualCapitalized", forKey: "settings.dictationStyle")
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style, .polished)
        XCTAssertEqual(defaults.string(forKey: "settings.dictationStyle"), "casualCapitalized")
    }
}
