import UIKit
import XCTest
@testable import Typr

@MainActor
final class CodeFromMessagesTests: XCTestCase {
    private func keyboard(
        contentType: UITextContentType?,
        appleKeyboard: Bool,
        fullAccess: Bool = true
    ) -> (FullKeyboardView, FixtureTextTarget) {
        let target = FixtureTextTarget(text: "Dein Code: ")
        target.textContentType = contentType
        let model = KeyboardViewModel()
        model.hasFullAccess = fullAccess
        let view = FullKeyboardView(model: model, target: target, autocorrect: AutocorrectEngine(spatialDecoder: nil))
        view.hasAppleKeyboard = { appleKeyboard }
        view.suggestionBarOverride = true
        view.orientationOverride = .portrait
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.prepareForField()
        view.layoutIfNeeded()
        return (view, target)
    }

    func testChipShowsInACodeFieldWhenApplesKeyboardIsOn() {
        XCTAssertTrue(keyboard(contentType: .oneTimeCode, appleKeyboard: true).0.showsCodeFromMessages)
    }

    func testNoChipWithoutApplesKeyboard() {
        XCTAssertFalse(
            keyboard(contentType: .oneTimeCode, appleKeyboard: false).0.showsCodeFromMessages,
            "Typr and Emoji only: the next keyboard gets no code"
        )
    }

    func testNoChipOutsideACodeField() {
        for type: UITextContentType? in [nil, .password, .emailAddress, .telephoneNumber] {
            let target = FixtureTextTarget()
            target.textContentType = type
            let view = FullKeyboardView(model: KeyboardViewModel(), target: target, autocorrect: AutocorrectEngine(spatialDecoder: nil))
            view.hasAppleKeyboard = {
                XCTFail("asked outside a code field")
                return true
            }
            view.suggestionBarOverride = true
            view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
            view.prepareForField()
            XCTAssertFalse(view.showsCodeFromMessages, "\(String(describing: type))")
        }
    }

    func testStatusMessageWinsOverTheChip() {
        XCTAssertFalse(keyboard(contentType: .oneTimeCode, appleKeyboard: true, fullAccess: false).0.showsCodeFromMessages)
    }

    func testTapSwitchesToTheNextKeyboard() {
        let (view, _) = keyboard(contentType: .oneTimeCode, appleKeyboard: true)
        var switches = 0
        view.model.onNextKeyboard = { switches += 1 }
        view.debugTapCodeFromMessages()
        XCTAssertEqual(switches, 1)
    }

    func testChipFollowsTheField() {
        let (view, target) = keyboard(contentType: nil, appleKeyboard: true)
        XCTAssertFalse(view.showsCodeFromMessages)
        target.textContentType = .oneTimeCode
        view.textDidChange()
        XCTAssertTrue(view.showsCodeFromMessages)
        target.textContentType = nil
        view.textDidChange()
        XCTAssertFalse(view.showsCodeFromMessages)
    }

    func testApplesKeyboardIsNotEmojiDictationOrAnExtension() {
        typealias Mode = KeyboardInputModes.Mode
        let german = Mode(primaryLanguage: "de-DE", className: "UIKeyboardInputMode")
        let typr = Mode(primaryLanguage: "de-DE", className: "UIKeyboardExtensionInputMode")
        let emoji = Mode(primaryLanguage: "emoji", className: "UIKeyboardInputMode")
        let dictation = Mode(primaryLanguage: "dictation", className: "UIKeyboardInputMode")
        XCTAssertTrue(KeyboardInputModes.hasAppleKeyboard([typr, emoji, german]))
        XCTAssertFalse(KeyboardInputModes.hasAppleKeyboard([typr, emoji]))
        XCTAssertFalse(KeyboardInputModes.hasAppleKeyboard([typr, dictation]))
        XCTAssertFalse(KeyboardInputModes.hasAppleKeyboard([typr]))
        XCTAssertFalse(KeyboardInputModes.hasAppleKeyboard([typr, typr, emoji]), "another third-party keyboard gets no code either")
    }
}
