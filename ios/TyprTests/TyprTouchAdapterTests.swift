import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprTouchAdapterTests: XCTestCase {
    private enum Keys: CaseIterable {
        case joined, bottomRow, unfoldedJoined, split, splitColumns
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var runningSystemMajorVersion = 0

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "TyprTouchAdapterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeEngine(_ keys: Keys) -> (FullKeyboardEngine, HexFixtureTextTarget, TyprAutocorrectAdapter) {
        let typr = TyprAutocorrectEngine(
            checker: Checker(valid: ["hello", "jello", "a", "out", "about"]),
            learning: KeyboardLearningSession(defaults: defaults),
            spatialDecoder: SpatialWordDecoder(lexicons: [.english: spatialLexicon([("hello", 100), ("jello", 100)])]),
            contextResources: .init(model: nil))
        let adapter = TyprAutocorrectAdapter(engine: typr)
        let target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        switch keys {
        case .joined:
            engine.width = 393
        case .bottomRow:
            engine.width = 393
            engine.typrBottomRow = BottomRow(order: [.typr, .space, .period], periodKey: true)
        case .unfoldedJoined, .split, .splitColumns:
            engine.posture = .unfoldedWide
            engine.windowInset = 75
            engine.width = 801
            engine.joinsUnfoldedKeyboard = keys == .unfoldedJoined
            engine.typrSplitColumns = keys == .splitColumns
        }
        engine.configureForField()
        XCTAssertEqual(engine.layout.split != nil, keys == .split || keys == .splitColumns, "\(keys)")
        return (engine, target, adapter)
    }

    private func centre(_ kind: KeyKind, in engine: FullKeyboardEngine) throws -> CGPoint {
        let key = try XCTUnwrap(engine.layout.key(kind))
        return CGPoint(x: key.frame.midX, y: key.frame.midY)
    }

    private func type(_ word: String, aimedAt aimed: String, on engine: FullKeyboardEngine) throws {
        for (letter, target) in zip(word, aimed) {
            engine.insert(String(letter), source: nil, at: try centre(.character(String(target)), in: engine))
        }
        let space = try centre(.space, in: engine)
        engine.touchBegan(id: 1, at: space)
        engine.touchEnded(id: 1, at: space)
    }

    func testWhereYouTapDecidesTheWordOnEveryLayout() throws {
        for keys in Keys.allCases {
            for (aimed, expected) in [("hello", "hello "), ("jello", "jello "), ("uello", "uello ")] {
                let (engine, target, _) = makeEngine(keys)
                try type("uello", aimedAt: aimed, on: engine)
                XCTAssertEqual(target.text, expected, "\(keys), aimed at \(aimed)")
            }
        }
    }

    func testHexTapsLandOnTheSameTyprKeys() throws {
        for keys in Keys.allCases {
            let (engine, _, adapter) = makeEngine(keys)
            for letter in "hello" {
                engine.insert(String(letter), source: nil, at: try centre(.character(String(letter)), in: engine))
            }
            _ = engine.autocorrect.suggestions(beforeInput: "hello", field: .text, autocorrectionType: .default,
                                               predictionModel: nil, capitalizesNext: false)
            let word = try XCTUnwrap(adapter.engine.touchInput.evidence(beforeInput: "hello"), "\(keys)")
            XCTAssertEqual(word.samples.map(\.text), ["h", "e", "l", "l", "o"], "\(keys)")
            for sample in word.samples {
                XCTAssertTrue(sample.key.frame.insetBy(dx: -1, dy: -1).contains(sample.point), "\(keys) \(sample.text)")
            }
        }
    }

    func testAJoinReadsBothWordsAndTheSpaceAndDecidesTheSpaceOnce() throws {
        for keys in Keys.allCases {
            let (engine, _, adapter) = makeEngine(keys)
            let firstTaps = [try centre(.character("a"), in: engine)].map { CGPoint(x: engine.layout.unsplitX($0.x), y: $0.y) }
            let space = try centre(.space, in: engine)
            adapter.decoderTaps = try "out".map { letter in
                let point = try centre(.character(String(letter)), in: engine)
                return CGPoint(x: engine.layout.unsplitX(point.x), y: point.y)
            }
            XCTAssertTrue(adapter.loadTouches(first: "a", firstTaps: firstTaps,
                                              space: CGPoint(x: engine.layout.unsplitX(space.x), y: space.y),
                                              second: "out", before: "a"), "\(keys)")
            let touch = try XCTUnwrap(adapter.engine.touchInput.boundaryEvidence(beforeInput: "a out"), "\(keys)")
            XCTAssertEqual(touch.previous?.text, "a", "\(keys)")
            XCTAssertEqual(touch.space?.key.kind, .space, "\(keys)")
            XCTAssertEqual(touch.current.text, "out", "\(keys)")

            let boundaries = adapter.engine.learning.diagnostics[.boundaries]
            let merged = adapter.merge(first: "a", firstTaps: firstTaps,
                                       space: CGPoint(x: engine.layout.unsplitX(space.x), y: space.y),
                                       second: "out", before: "a")
            if merged == nil {
                _ = adapter.replacementOnSpace(beforeInput: "a out", field: .text, autocorrectionType: .default)
            }
            XCTAssertEqual(adapter.engine.learning.diagnostics[.boundaries], boundaries + 1, "\(keys): one decision per space")
        }
    }

    func testATyprJoinReachesHexAndItsRevertStopsItForTheSession() throws {
        let sources = try XCTUnwrap(BundledKeyboardData.lexicons)
        let typr = TyprAutocorrectEngine(
            checker: KeyboardBoundaryDecoderTests.Checker(sources[.english], trusted: []),
            learning: KeyboardLearningSession(defaults: defaults),
            spatialDecoder: SpatialWordDecoder(lexicons: sources),
            contextResources: KeyboardContextResources(model: BundledKeyboardData.contextModel))
        let adapter = TyprAutocorrectAdapter(engine: typr)
        let target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        engine.width = 393
        engine.configureForField()

        let grid = TyprKeyboardLayout(width: 393)
        let typrSpace = try XCTUnwrap(grid.key(.space)).frame
        let typrV = try XCTUnwrap(grid.key(.character("v"))).frame
        let hexSpace = try XCTUnwrap(engine.layout.key(.space)).frame
        let straySpace = CGPoint(x: hexSpace.midX + (typrV.midX - typrSpace.midX) / typrSpace.width * hexSpace.width,
                                 y: hexSpace.minY + 1)
        func letters(_ word: String) throws {
            for letter in word {
                engine.insert(String(letter), source: nil, at: try centre(.character(String(letter)), in: engine))
            }
        }
        func space(at point: CGPoint) {
            engine.touchBegan(id: 1, at: point)
            engine.touchEnded(id: 1, at: point)
        }
        let centredSpace = try centre(.space, in: engine)

        try letters("think")
        space(at: centredSpace)
        try letters("ne")
        space(at: straySpace)
        try letters("er")
        space(at: centredSpace)
        XCTAssertTrue(target.text.hasSuffix("never "), target.text)

        space(at: try centre(.delete, in: engine))
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertTrue(target.text.hasSuffix("ne er"), target.text)
        XCTAssertFalse(typr.learning.model.state.rejected.contains { $0.typed == "er" }, "no one-word rejection")

        space(at: centredSpace)
        try letters("think")
        space(at: centredSpace)
        try letters("ne")
        space(at: straySpace)
        try letters("er")
        space(at: centredSpace)
        XCTAssertTrue(target.text.hasSuffix("think ne er "), "an undone join is not made again: \(target.text)")
    }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    init(valid: Set<String>) { self.valid = valid }
    func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
    func guesses(for word: String) -> [String] { [] }
    func completions(for prefix: String) -> [String] { [] }
}
