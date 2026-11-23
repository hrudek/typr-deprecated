import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardClipboardTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "typr.clipboard.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testTheChipReadsTextOrALinkOnce() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        XCTAssertNil(KeyboardClipboardTracker.read(pasteboard))
        pasteboard.url = URL(string: "https://typr.example/a")
        XCTAssertEqual(KeyboardClipboardTracker.read(pasteboard), "https://typr.example/a")
        pasteboard.string = "See you at 7"
        XCTAssertEqual(KeyboardClipboardTracker.read(pasteboard), "See you at 7")
    }

    func testCopyExpiresAndUsedCopyStaysHiddenUntilTheNextCopy() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let tracker = KeyboardClipboardTracker(defaults: defaults)
        let copiedAt = Date(timeIntervalSince1970: 1_000)

        func offer(at time: TimeInterval, hasFullAccess: Bool = true) -> KeyboardClipboardOffer? {
            tracker.offer(
                textContentType: nil, keyboardType: .default, autocorrectionType: .default,
                fieldIsEmpty: true, hasFullAccess: hasFullAccess, pasteboard: pasteboard,
                now: copiedAt.addingTimeInterval(time)
            )
        }
        pasteboard.string = "First copy"
        XCTAssertNil(offer(at: -60, hasFullAccess: false))
        XCTAssertEqual(offer(at: 0), .paste)
        XCTAssertEqual(offer(at: KeyboardClipboardTracker.freshness - 1), .paste)
        XCTAssertNil(offer(at: KeyboardClipboardTracker.freshness))
        pasteboard.string = "Second copy"
        XCTAssertEqual(offer(at: 200), .paste)
        tracker.markPasted(pasteboard: pasteboard)
        XCTAssertNil(offer(at: 201))
        pasteboard.string = "Third copy"
        XCTAssertEqual(offer(at: 202), .paste)
    }

    func testAPasteThatAskedPointsToTheSettingAFewTimes() {
        let tracker = KeyboardClipboardTracker(defaults: defaults)
        XCTAssertFalse(tracker.shouldPointToAllowPaste(readDuration: 0.01, refused: false), "Allow: iOS didn't ask")
        for _ in 0..<KeyboardClipboardTracker.allowPasteHintLimit {
            XCTAssertTrue(tracker.shouldPointToAllowPaste(readDuration: 1.2, refused: false))
        }
        XCTAssertFalse(
            KeyboardClipboardTracker(defaults: defaults).shouldPointToAllowPaste(readDuration: 1.2, refused: false),
            "after a few, Ask is left alone: someone may want it"
        )
        XCTAssertTrue(tracker.shouldPointToAllowPaste(readDuration: 0.01, refused: true), "refused: the chip did nothing, always say why")
    }

    func testCodeFromMessagesNeedsApplesKeyboard() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let tracker = KeyboardClipboardTracker(defaults: defaults)
        func offer(appleKeyboard: Bool) -> KeyboardClipboardOffer? {
            tracker.offer(
                textContentType: .oneTimeCode, keyboardType: .numberPad, autocorrectionType: .default, fieldIsEmpty: true,
                hasFullAccess: true, hasAppleKeyboard: { appleKeyboard }, pasteboard: pasteboard
            )
        }
        XCTAssertEqual(offer(appleKeyboard: true), .code(canPaste: false))
        XCTAssertNil(offer(appleKeyboard: false), "Hex and Emoji only: the next keyboard gets no code (TestFlight build 56)")
        pasteboard.string = "482913"
        XCTAssertEqual(offer(appleKeyboard: true), .code(canPaste: true))
        XCTAssertEqual(offer(appleKeyboard: false), .paste, "a copied code still pastes")
        XCTAssertEqual(
            tracker.offer(
                textContentType: nil, keyboardType: .default, autocorrectionType: .default, fieldIsEmpty: true,
                hasFullAccess: true, hasAppleKeyboard: { XCTFail("asked outside a code field"); return true }, pasteboard: pasteboard
            ),
            .paste
        )
    }

    func testNoCodeFromMessagesWhereApplesKeyboardSplits() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let tracker = KeyboardClipboardTracker(defaults: defaults)
        func offer(canSwitch: Bool) -> KeyboardClipboardOffer? {
            tracker.offer(
                textContentType: .oneTimeCode, keyboardType: .numberPad, autocorrectionType: .default, fieldIsEmpty: true,
                hasFullAccess: true, canSwitchKeyboard: canSwitch, hasAppleKeyboard: { true }, pasteboard: pasteboard
            )
        }
        XCTAssertEqual(offer(canSwitch: true), .code(canPaste: false))
        XCTAssertNil(offer(canSwitch: false))
        pasteboard.string = "482913"
        XCTAssertEqual(offer(canSwitch: true), .code(canPaste: true))
        XCTAssertEqual(offer(canSwitch: false), .paste, "a copied code still pastes")
    }

    func testChipsGiveWayToSuggestionsInAChatBox() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let tracker = KeyboardClipboardTracker(defaults: defaults)
        func offer(
            _ keyboardType: UIKeyboardType, _ autocorrection: UITextAutocorrectionType, empty: Bool = true
        ) -> KeyboardClipboardOffer? {
            tracker.offer(
                textContentType: .oneTimeCode, keyboardType: keyboardType, autocorrectionType: autocorrection, fieldIsEmpty: empty,
                hasFullAccess: true, hasAppleKeyboard: { true }, pasteboard: pasteboard
            )
        }
        XCTAssertNil(offer(.default, .default), "a chat box with nothing copied: suggestions")
        XCTAssertEqual(offer(.default, .yes), .code(canPaste: false), "Safari's autocomplete=one-time-code")
        XCTAssertEqual(offer(.default, .no), .code(canPaste: false))
        XCTAssertEqual(offer(.asciiCapableNumberPad, .default), .code(canPaste: false))
        XCTAssertNil(offer(.numberPad, .default, empty: false), "typing a code by hand")
        pasteboard.string = "See you at 7"
        XCTAssertEqual(offer(.default, .default), .paste)
        XCTAssertNil(offer(.default, .default, empty: false), "after a word the strip suggests")
        XCTAssertEqual(offer(.numberPad, .default), .code(canPaste: true))
    }

}
