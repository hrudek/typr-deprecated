import UIKit
import XCTest
@testable import Typr

/// Hex's Adaptive touch experiment (Settings › Experiments, off by default): Hex's tests at
/// 0c1c13d7 that need no keyboard engine, reading the key plane from a layout instead. The
/// engine's labelling tests come with Hex's engine.
@MainActor
final class AdaptiveTouchTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "AdaptiveTouchTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var layout: KeyboardLayout { KeyboardLayout(width: 390, language: .english) }

    /// An Adaptive touch reading `layout`'s letters page, as the engine syncs it.
    private func adaptive(_ storage: AdaptiveTouch.Storage = .memory, on layout: KeyboardLayout? = nil) -> AdaptiveTouch {
        let touch = AdaptiveTouch(storage: storage, settings: AdaptiveTouchSettings(defaults: defaults))
        _ = touch.offsets(for: layout ?? self.layout)
        return touch
    }

    /// Admits `taps` labelled taps landing `dx` keycaps right of each key's centre, over
    /// `sessions` keyboard sessions.
    private func teach(_ touch: AdaptiveTouch, dx: CGFloat, taps: Int = 420, sessions: Int = 4) throws {
        let geometry = try XCTUnwrap(touch.geometry)
        for n in 0..<taps {
            if n % max(1, taps / sessions) == 0 { touch.beginSession() }
            let s = n % geometry.letters.count
            let f = geometry.frames[s]
            touch.admit(slot: s, point: CGPoint(x: f.midX + dx * f.width, y: f.midY), quality: AdaptiveTouch.weakQuality)
        }
    }

    func testAdaptiveTouchIsOffByDefaultAndOnlyInMemoryWithoutFullAccess() {
        let settings = AdaptiveTouchSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertNil(AdaptiveTouch.sharedIfEnabled(settings: settings, persistent: true))
        settings.isEnabled = true
        XCTAssertEqual(AdaptiveTouch.sharedIfEnabled(settings: settings, persistent: false)?.storage, .memory)
        settings.isEnabled = false
        XCTAssertNil(AdaptiveTouch.sharedIfEnabled(settings: settings, persistent: false))
        settings.summary = (240, false)
        XCTAssertEqual(AdaptiveTouchStatus.current(settings: settings, fullAccessConfirmed: true), .learning(taps: 240))
        settings.summary = (900, false)
        XCTAssertEqual(AdaptiveTouchStatus.current(settings: settings, fullAccessConfirmed: true), .learning(taps: 400))
    }

    func testAdaptiveTouchFileIsSmallProtectedFromBackupAndReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AdaptiveTouchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(AdaptiveTouch.fileName)
        let settings = AdaptiveTouchSettings(defaults: defaults)
        let touch = adaptive(.file(url))
        try teach(touch, dx: 0.2)
        XCTAssertTrue(touch.isActive)
        XCTAssertFalse(touch.offsets(for: layout).isEmpty, "the decoder reads personal centres")
        touch.save()
        AdaptiveTouch.waitForWrites()
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, AdaptiveTouchModel.byteCount)
        XCTAssertLessThanOrEqual(data.count, 27_712, "averages only, the same size whatever was learned")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(settings.summary?.active, true)
        XCTAssertEqual(AdaptiveTouchStatus.current(settings: settings, fullAccessConfirmed: true), .active)
        XCTAssertEqual(AdaptiveTouchStatus.current(settings: settings, fullAccessConfirmed: false), .sessionOnly)
        XCTAssertEqual(AdaptiveTouch(storage: .file(url), settings: settings).model, touch.model, "the next keyboard process reads it")

        var damaged = data
        damaged[200] ^= 0xFF
        try damaged.write(to: url)
        XCTAssertTrue(AdaptiveTouch(storage: .file(url), settings: settings).model.contexts.allSatisfy { $0.geometry == 0 })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "a damaged file is dropped")

        // Reset touch learning: the running keyboard forgets at once; a file written before
        // can't come back.
        try data.write(to: url)
        settings.requestReset()
        XCTAssertNil(settings.summary)
        XCTAssertEqual(AdaptiveTouchStatus.current(settings: settings, fullAccessConfirmed: true), .learning(taps: 0))
        touch.applyResetIfNeeded()
        XCTAssertFalse(touch.isActive)
        XCTAssertTrue(touch.offsets(for: layout).isEmpty, "the decoder reads the stock centres")
        XCTAssertTrue(touch.model.contexts.allSatisfy { $0.geometry == 0 })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try data.write(to: url)
        XCTAssertTrue(AdaptiveTouch(storage: .file(url), settings: settings).model.contexts.allSatisfy { $0.geometry == 0 })
    }

    func testAdaptiveTouchNeedsEvidenceFromSeveralSessionsBeforeTheDecoderUsesIt() throws {
        let touch = adaptive()
        try teach(touch, dx: 0.2, taps: 399, sessions: 4)
        XCTAssertFalse(touch.isActive, "399 taps")
        let other = adaptive()
        try teach(other, dx: 0.2, taps: 800, sessions: 1)
        XCTAssertFalse(other.isActive, "one session")
        let accurate = adaptive()
        try teach(accurate, dx: 0, taps: 800, sessions: 4)
        XCTAssertFalse(accurate.isActive, "taps on the centres: the stock centres already fit")
    }

    /// Another arrangement of the letters is another key plane: what was learned on QWERTY
    /// never moves QWERTZ's centres, and comes back with QWERTY.
    func testAdaptiveTouchKeepsEachLetterLayoutApart() throws {
        let touch = adaptive()
        try teach(touch, dx: 0.2)
        XCTAssertTrue(touch.isActive)
        let qwerty = try XCTUnwrap(AdaptiveTouchGeometry(layout: layout)).key
        let qwertz = KeyboardLayout(width: 390, language: .english, letters: .qwertz)
        XCTAssertNotEqual(try XCTUnwrap(AdaptiveTouchGeometry(layout: qwertz)).key, qwerty)
        XCTAssertTrue(touch.offsets(for: qwertz).isEmpty, "QWERTZ starts from the stock centres")
        XCTAssertFalse(touch.isActive)
        _ = touch.offsets(for: KeyboardLayout(width: 390, language: .english, letters: .azerty))
        XCTAssertFalse(touch.isActive)
        XCTAssertFalse(touch.offsets(for: layout).isEmpty)
        XCTAssertTrue(touch.isActive, "QWERTY's profile is still there")
    }

    /// Adaptive touch learns the punctuated row apart from Apple's Dvorak, and only where that
    /// row is drawn: a QWERTY keyboard, a non-letter page and a Dvorak URL or email field keep
    /// every centre they learned with the experiment on. (Hex's KeyboardLayoutTests.)
    func testDvorakPunctuationOnlyThePunctuatedRowIsItsOwnAdaptiveTouchPlane() throws {
        func plane(_ layout: KeyboardLayout) throws -> UInt64 {
            try XCTUnwrap(AdaptiveTouchGeometry(layout: layout)).key
        }
        let qwerty = KeyboardLayout(width: 402, language: .english)
        let qwertyOn = KeyboardLayout(width: 402, language: .english, dvorakPunctuation: true)
        XCTAssertEqual(try plane(qwertyOn), try plane(qwerty), "QWERTY doesn't move")
        XCTAssertFalse(qwertyOn.dvorakPunctuation, "the flag means nothing on QWERTY")
        for field in [KeyboardFieldKind.url, .email] {
            let off = KeyboardLayout(width: 402, field: field, language: .english, letters: .dvorak)
            let on = KeyboardLayout(width: 402, field: field, language: .english, letters: .dvorak, dvorakPunctuation: true)
            XCTAssertFalse(on.hasDvorakPunctuationRow, "\(field): no row 1 punctuation")
            XCTAssertEqual(try plane(on), try plane(off), "\(field): its letters are the same plane")
        }
        for layer in [KeyboardLayer.numbers, .symbols] {
            let off = KeyboardLayout(width: 402, layer: layer, language: .english, letters: .dvorak)
            let on = KeyboardLayout(width: 402, layer: layer, language: .english, letters: .dvorak, dvorakPunctuation: true)
            XCTAssertFalse(on.hasDvorakPunctuationRow, "\(layer): no letters page")
            XCTAssertNil(AdaptiveTouchGeometry(layout: on))
            XCTAssertNil(AdaptiveTouchGeometry(layout: off))
        }
        let apple = KeyboardLayout(width: 402, language: .english, letters: .dvorak)
        let punctuated = KeyboardLayout(width: 402, language: .english, letters: .dvorak, dvorakPunctuation: true)
        XCTAssertTrue(punctuated.hasDvorakPunctuationRow)
        XCTAssertNotEqual(try plane(punctuated), try plane(apple), "the narrower row 1 is its own plane")
    }

    /// Learn how I type and Adaptive touch never learn in sensitive fields (Hex's field checks,
    /// read without the engine that applies them).
    func testNeitherLearnsInSensitiveFields() {
        func allows(field: KeyboardFieldKind = .text, _ configure: (TraitField) -> Void = { _ in }) -> (journal: Bool, touch: Bool) {
            let target = TraitField()
            configure(target)
            return (TypingJournal.allows(field: field, target: target), AdaptiveTouch.allows(field: field, target: target))
        }
        XCTAssertTrue(allows() == (true, true), "a plain field")
        for type in [UITextContentType.password, .newPassword, .oneTimeCode, .username, .emailAddress, .URL,
                     .creditCardNumber, .telephoneNumber] {
            XCTAssertTrue(allows { $0.textContentType = type } == (false, false), type.rawValue)
        }
        XCTAssertTrue(allows { $0.autocorrectionType = .no } == (false, false))
        XCTAssertTrue(allows(field: .url) == (false, false))
        XCTAssertTrue(allows(field: .email) == (false, false))
        XCTAssertTrue(allows { $0.isSecureTextEntry = true } == (true, false), "Adaptive touch also skips secure entry")
    }
}

/// A text field with the traits learning must not happen in.
@MainActor
private final class TraitField: KeyboardTextTarget {
    private(set) var text = ""
    var autocapitalizationType: UITextAutocapitalizationType? = UITextAutocapitalizationType.none
    var autocorrectionType: UITextAutocorrectionType? = .default
    var keyboardType: UIKeyboardType? = .default
    var returnKeyType: UIReturnKeyType? = .default
    var keyboardAppearance: UIKeyboardAppearance? { nil }
    var textContentType: UITextContentType?
    var isSecureTextEntry: Bool?
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { nil }
    var smartQuotesType: UITextSmartQuotesType? { nil }
    var smartDashesType: UITextSmartDashesType? { nil }
    var hasText: Bool { !text.isEmpty }
    func insertText(_ inserted: String) { text += inserted }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}
