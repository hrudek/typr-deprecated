import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprTypingVariantTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "TyprTypingVariantTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func typrEngine() -> TyprAutocorrectEngine {
        TyprAutocorrectEngine(
            checker: Checker(valid: ["the", "its", "it's", "a", "nice", "day"], guesses: ["teh": ["the"]]),
            learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil,
            contextResources: .init(model: BundledKeyboardData.contextModel))
    }

    private func makeView(_ settings: TyprSettings) -> (FullKeyboardView, HexFixtureTextTarget) {
        let target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let backend = FullKeyboardView.typrTypingBackend(settings) { typrEngine() }
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target, autocorrect: backend, defaults: defaults)
        view.hexPlacementOverride = .stripTrailing
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return (view, target)
    }

    private func type(_ text: String, on engine: FullKeyboardEngine) throws {
        for character in text {
            let key = try XCTUnwrap(engine.layout.key(character == " " ? .space : .character(String(character))))
            let at = CGPoint(x: key.frame.midX, y: key.frame.midY)
            engine.touchBegan(id: 1, at: at)
            engine.touchEnded(id: 1, at: at)
        }
    }

    func testTyprTypingIsAnOffByDefaultTyprVariant() {
        let typing = ExperimentalSwitch.typrTyping
        XCTAssertEqual(typing.key, "typr.experimental.variant.typrTyping")
        XCTAssertEqual(typing.title, "Typr typing and autocorrect")
        XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(typing))
        XCTAssertTrue(ExperimentalSwitch.typrOverrides.contains(typing))
        let settings = TyprSettings(defaults: defaults)
        XCTAssertFalse(settings[experiment: typing])
        XCTAssertNil(FullKeyboardView.typrTypingBackend(settings) {
            XCTFail("off: no Typr engine is built")
            return typrEngine()
        })
    }

    func testTheSwitchPicksTheHexKeyboardsAutocorrect() throws {
        let settings = TyprSettings(defaults: defaults)
        let (hex, _) = makeView(settings)
        XCTAssertTrue(hex.engine.autocorrect is AutocorrectEngine, "off: Hex's autocorrect")

        settings[experiment: .typrTyping] = true
        let (typr, target) = makeView(settings)
        XCTAssertTrue(typr.engine.autocorrect is TyprAutocorrectAdapter)
        try type("teh ", on: typr.engine)
        XCTAssertEqual(target.text, "the ")
    }

    func testWordsFromContextActsOnTyprTyping() throws {
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .typrTyping] = true
        let (view, target) = makeView(settings)
        let typr = try XCTUnwrap(view.engine.autocorrect as? TyprAutocorrectAdapter)
        view.syncTyprVariants(settings)
        XCTAssertFalse(typr.engine.choosesWordsFromContext)
        settings[experiment: .wordsFromContext] = true
        view.syncTyprVariants(settings)
        XCTAssertTrue(typr.engine.choosesWordsFromContext)
        try type("its a nice day ", on: view.engine)
        XCTAssertEqual(target.text, "it's a nice day ")
    }

    func testEveryCombinationWithTheOtherTyprKeyboardVariants() throws {
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .typrTyping] = true
        settings.hideSuggestionBar = true
        let flags = [false, true]
        let combinations = KeyboardDesign.allCases.flatMap { design in
            [KeyboardTheme.automatic, .navy].flatMap { theme in
                flags.flatMap { cursor in flags.flatMap { deleteSliding in
                    flags.flatMap { bottomRow in flags.map { (design, theme, cursor, deleteSliding, bottomRow, $0) } }
                } }
            }
        }
        for (design, theme, cursor, deleteSliding, bottomRow, compact) in combinations {
            let label = "\(design.rawValue) \(theme.rawValue) cursor \(cursor) delete \(deleteSliding) bottom \(bottomRow) compact \(compact)"
            settings[experiment: .typrCursorSliding] = cursor
            settings[experiment: .typrDeleteSliding] = deleteSliding
            settings[experiment: .typrBottomRow] = bottomRow
            settings[experiment: .typrCompactStrip] = compact
            TyprFullKeyboardSettings(defaults: defaults).design = design
            let hex = FullKeyboardSettings(defaults: defaults)
            hex.keyboardThemesEnabled = true
            hex.keyboardTheme = theme
            let (view, target) = makeView(settings)
            view.syncTyprVariants(settings)
            view.layoutIfNeeded()
            XCTAssertEqual(view.preferredHeight, compact ? 224 : 253, label)
            XCTAssertEqual(view.engine.showsStrip, !compact, label)
            XCTAssertEqual(view.engine.typrBottomRow != nil, bottomRow, label)
            XCTAssertEqual(view.palette.mechanical, design == .mechanical, label)
            XCTAssertEqual(view.palette.theme, design == .mechanical ? .automatic : theme, label)
            XCTAssertEqual(view.engine.slidesCursorByCharacter, cursor, label)
            XCTAssertEqual(view.plane.slidesDeleteByWord, !deleteSliding, label)
            XCTAssertTrue(view.engine.autocorrect is TyprAutocorrectAdapter, label)
            try type("teh ", on: view.engine)
            XCTAssertEqual(target.text, "the ", label)
        }
    }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    let table: [String: [String]]
    init(valid: Set<String>, guesses: [String: [String]]) { self.valid = valid; table = guesses }
    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { table[word.lowercased()] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
}
