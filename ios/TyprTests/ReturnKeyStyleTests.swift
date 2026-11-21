import UIKit
import XCTest
@testable import Typr

@MainActor
final class ReturnKeyStyleTests: XCTestCase {
    private static let expected: [(UIReturnKeyType, symbol: String, isAction: Bool, label: String)] = [
        (.default, "return", false, "Return"),
        (.send, "arrow.up", true, "Send"),
        (.go, "arrow.right", true, "Go"),
        (.join, "arrow.right", true, "Join"),
        (.route, "arrow.right", true, "Route"),
        (.search, "magnifyingglass", true, "Search"),
        (.google, "magnifyingglass", true, "Search"),
        (.yahoo, "magnifyingglass", true, "Search"),
        (.done, "checkmark", true, "Done"),
        (.emergencyCall, "phone", true, "Emergency call"),
        (.next, "chevron.right", false, "Next"),
        (.continue, "chevron.right", false, "Continue"),
    ]

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: "ReturnKeyStyleTests")
    }

    func testEveryReturnKeyTypeMapsToApplesSymbolStyleAndLabel() {
        for (type, symbol, isAction, label) in Self.expected {
            let style = ReturnKeyStyle(type)
            XCTAssertEqual(style.symbol, symbol, "\(type.rawValue)")
            XCTAssertEqual(style.isAction, isAction, "\(type.rawValue)")
            XCTAssertEqual(style.accessibilityLabel, label, "\(type.rawValue)")
            XCTAssertNotNil(UIImage(systemName: symbol), symbol)
        }
        XCTAssertEqual(ReturnKeyStyle(nil), ReturnKeyStyle(.default))
    }

    func testReturnIsOffOnlyForAnEmptyFieldThatAsksForIt() {
        XCTAssertFalse(ReturnKeyStyle.isEnabled(automatically: true, hasText: false))
        XCTAssertTrue(ReturnKeyStyle.isEnabled(automatically: true, hasText: true))
        XCTAssertTrue(ReturnKeyStyle.isEnabled(automatically: false, hasText: false))
        XCTAssertTrue(ReturnKeyStyle.isEnabled(automatically: nil, hasText: false))
    }

    func testFullKeyboardReturnInsertsNewlineForEveryType() {
        for (type, _, _, _) in Self.expected {
            let target = FixtureTextTarget()
            target.autocapitalizationType = UITextAutocapitalizationType.none
            target.returnKeyType = type
            let learning = KeyboardLearningSession(defaults: UserDefaults(suiteName: "ReturnKeyStyleTests")!)
            let engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(learning: learning, spatialDecoder: nil))
            engine.width = 393
            engine.configureForField()
            let key = engine.layout.key(.returnKey)!
            let at = CGPoint(x: key.frame.midX, y: key.frame.midY)
            engine.touchBegan(id: 1, at: at)
            engine.touchEnded(id: 1, at: at)
            XCTAssertEqual(target.text, "\n", "\(type.rawValue)")
        }
    }

    func testFullKeyboardDrawsTheFieldsReturnKeyAndTurnsItOnWithText() {
        let target = FixtureTextTarget()
        target.returnKeyType = .send
        target.enablesReturnKeyAutomatically = true
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.prepareForField()
        XCTAssertEqual(view.shownReturnKey.style, ReturnKeyStyle(.send))
        XCTAssertFalse(view.shownReturnKey.isEnabled)

        target.insertText("Hallo")
        view.textDidChange()
        XCTAssertTrue(view.shownReturnKey.isEnabled)

        target.returnKeyType = .next
        view.prepareForField()
        XCTAssertEqual(view.shownReturnKey.style.symbol, "chevron.right")
        XCTAssertFalse(view.shownReturnKey.style.isAction)
    }
}
