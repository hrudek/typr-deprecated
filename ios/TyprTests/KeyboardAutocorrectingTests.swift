import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardAutocorrectingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "KeyboardAutocorrectingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testHexEngineDefaultsToHexAutocorrect() {
        let engine = FullKeyboardEngine(target: HexFixtureTextTarget())
        XCTAssertTrue(engine.autocorrect is AutocorrectEngine)
    }

    func testHexEngineDrivesTheBackendItIsGiven() {
        let backend: any KeyboardAutocorrecting = AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults))
        let engine = FullKeyboardEngine(target: HexFixtureTextTarget(), autocorrect: backend)
        XCTAssertTrue(engine.autocorrect === backend)

        engine.language = .german
        XCTAssertEqual(backend.language, .german)
        engine.letterLayout = .qwerty
        XCTAssertEqual(backend.layoutLetters, .qwerty)
    }

    func testHexViewPassesTheBackendToItsEngine() {
        let backend: any KeyboardAutocorrecting = AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults))
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(), autocorrect: backend)
        XCTAssertTrue(view.engine.autocorrect === backend)
    }
}
