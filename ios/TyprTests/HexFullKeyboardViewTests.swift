import UIKit
import XCTest
@testable import Typr

/// The staged Hex `FullKeyboardView` composed from the strip, key plane and emoji panel: Typr's
/// compact geometry, the strip across the whole inset width (S1/S2), host lifecycle, memory
/// warnings and the ABC under the emoji key experiment. Production still uses
/// `TyprFullKeyboardView` until the cutover.
@MainActor
final class HexFullKeyboardViewTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var target: HexFixtureTextTarget!

    override func setUp() async throws {
        suiteName = "HexFullKeyboardViewTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        target = HexFixtureTextTarget()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeView(
        width: CGFloat = 393,
        placement: HexKeyPlacement = .stripTrailing,
        model: KeyboardViewModel = KeyboardViewModel()
    ) -> FullKeyboardView {
        let view = FullKeyboardView(model: model, target: target)
        view.hexPlacementOverride = placement
        view.makeEmojiUsage = { [defaults] in EmojiUsageStore(defaults: defaults!) }
        view.frame = CGRect(x: 0, y: 0, width: width, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }

    // MARK: - Geometry

    func testCompactPortraitAndLandscapeGeometryMatchTyprsLayout() throws {
        for width in [375, 393, 402, 440] as [CGFloat] {
            let view = makeView(width: width)
            XCTAssertFalse(view.engine.hasNumberRow, "fixture without the number row")
            XCTAssertEqual(view.preferredHeight, 253, "\(width)")
            XCTAssertEqual(view.plane.frame, view.bounds, "\(width)")
            let expected = KeyboardLayout(width: width, phoneSize: view.engine.phoneSize)
            for letter in ["q", "a", "z", "p"] {
                let key = try XCTUnwrap(view.engine.layout.key(.character(letter)))
                XCTAssertEqual(key.frame, expected.key(.character(letter))?.frame, "\(letter) at \(width)")
            }
            XCTAssertEqual(view.engine.layout.key(.space)?.frame.height, 45, "\(width)")
            let hex = try XCTUnwrap(view.engine.layout.key(.hex))
            XCTAssertEqual(view.hexKey.frame, hex.hitFrame, "\(width)")
            XCTAssertEqual(hex.frame.height, TyprKeyboardMetrics.stripPillHeight, "\(width)")
        }

        let turned = FullKeyboardView(model: KeyboardViewModel(), target: target)
        turned.orientationOverride = .landscape
        turned.hexPlacementOverride = .stripTrailing
        turned.frame = CGRect(x: 0, y: 0, width: 874, height: turned.preferredHeight)
        turned.layoutIfNeeded()
        XCTAssertEqual(turned.preferredHeight, 176)
        XCTAssertEqual(turned.engine.layout.key(.character("q"))?.frame.height, 27.5)
        XCTAssertEqual(turned.engine.layout.key(.character("q"))?.frame.minY ?? 0, 39, accuracy: 0.001)
    }

    /// S1: in portrait the strip runs from the inset to the Hex key, and the three slots fit
    /// long German words.
    func testPortraitStripFitsLongGermanWords() throws {
        let view = makeView(width: 393)
        let layout = view.engine.layout
        let hex = try XCTUnwrap(layout.key(.hex))
        XCTAssertEqual(view.stripView.frame.minX, layout.horizontalInset, accuracy: 0.5)
        XCTAssertEqual(view.stripView.frame.maxX, hex.frame.minX - layout.metrics.gap, accuracy: 0.5)
        XCTAssertEqual(view.stripView.frame.height, 33)

        for word in ["Entschuldigung", "selbstverständlich"] {
            for index in 0..<3 {
                var words = ["ja", "gut", "nein"]
                words[index] = word
                XCTAssertLessThanOrEqual(wantedWidth(words), view.stripView.bounds.width, "\(word) in slot \(index)")
            }
        }
    }

    private func wantedWidth(_ words: [String]) -> CGFloat {
        words.map { KeyboardStripView.wantedWidth(for: KeyboardSuggestion(displayText: $0, replacement: $0, kind: .secondary)) }
            .reduce(0, +)
    }

    /// S2: where Hex's split keyboard keeps its strip over one half, Typr's spans the whole
    /// inset width, with the Hex key at its outer end on either side.
    func testSplitStripSpansTheWholeInsetWidth() throws {
        for placement in [HexKeyPlacement.stripTrailing, .stripLeading] {
            let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
            view.hexPlacementOverride = placement
            view.engine.posture = .unfoldedWide
            view.engine.windowInset = 75
            view.frame = CGRect(x: 0, y: 0, width: 801, height: view.preferredHeight)
            view.layoutIfNeeded()

            let layout = view.engine.layout
            let split = try XCTUnwrap(layout.split, "\(placement) is split")
            let hex = try XCTUnwrap(layout.key(.hex))
            let strip = view.stripView.frame
            let gap = layout.metrics.gap
            XCTAssertLessThan(strip.minX, split.leftEdge, "\(placement) reaches the left half")
            XCTAssertGreaterThan(strip.maxX, split.rightEdge, "\(placement) reaches the right half")
            XCTAssertGreaterThan(strip.width, layout.stripFrame.width, "\(placement) wider than Hex's half strip")
            if placement == .stripTrailing {
                XCTAssertEqual(strip.minX, layout.horizontalInset, accuracy: 0.5)
                XCTAssertEqual(strip.maxX, hex.frame.minX - gap, accuracy: 0.5)
            } else {
                XCTAssertEqual(strip.minX, hex.frame.maxX + gap, accuracy: 0.5)
                XCTAssertEqual(strip.maxX, view.bounds.width - layout.horizontalInset, accuracy: 0.5)
            }
            XCTAssertFalse(strip.intersects(hex.frame), "\(placement) leaves the Hex key its room")
            XCTAssertEqual(view.selectionStrip.frame, strip)
            XCTAssertLessThanOrEqual(wantedWidth(["Entschuldigung", "gut", "selbstverständlich"]), strip.width, "\(placement)")
        }
    }

    // MARK: - Host lifecycle

    func testNewFieldCancelsTouchesAndClosesTheEmojiPanel() throws {
        let view = makeView()
        view.emojiOverride = true
        let q = try XCTUnwrap(view.engine.layout.key(.character("q")))
        view.engine.touchBegan(id: 1, at: CGPoint(x: q.frame.midX, y: q.frame.midY))
        XCTAssertFalse(view.engine.touches.isEmpty)
        view.prepareForField()
        XCTAssertTrue(view.engine.touches.isEmpty, "a new field drops the touch")
        XCTAssertEqual(target.text, "", "and types nothing")

        view.debugOpenEmoji()
        XCTAssertNotNil(view.emojiPanel)
        view.prepareForField()
        XCTAssertNil(view.emojiPanel, "a new field closes the panel")
        XCTAssertFalse(view.plane.isHidden)
        XCTAssertFalse(view.stripView.isHidden)
    }

    func testFieldKindChangeCancelsTouches() throws {
        let view = makeView()
        let q = try XCTUnwrap(view.engine.layout.key(.character("q")))
        view.engine.touchBegan(id: 1, at: CGPoint(x: q.frame.midX, y: q.frame.midY))
        target.keyboardType = .emailAddress
        view.textDidChange()
        XCTAssertTrue(view.engine.touches.isEmpty)
        XCTAssertEqual(target.text, "")
    }

    func testRecordingPanelAllocatesLazilyAndTearsDownOnIdle() {
        let model = KeyboardViewModel()
        let view = makeView(model: model)
        XCTAssertFalse(view.hasAllocatedRecordingPanel, "no recording panel while typing")

        let t: TimeInterval = 1_000
        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .recording, heartbeat: t, expiresAt: t + 60, recordingStartedAt: t - 1, jobID: "j1"),
            isModelInstalled: true,
            style: .polished,
            now: t,
            clearPending: false,
            animated: false
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(view.hasAllocatedRecordingPanel)
        XCTAssertTrue(view.showsRecording)

        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .ready, heartbeat: t + 1, expiresAt: t + 60),
            isModelInstalled: true,
            style: .polished,
            now: t + 1,
            clearPending: true,
            animated: false
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(view.hasAllocatedRecordingPanel, "torn down once recording ends")
    }

    // MARK: - Memory

    func testMemoryWarningPurgesGlyphsAndReleasesTheClosedPanelsLibrary() throws {
        let view = makeView()
        view.emojiOverride = true
        view.debugOpenEmoji()
        let panel = try XCTUnwrap(view.emojiPanel)
        _ = panel.glyphs.glyph(for: "🍕", size: 32, scale: 3)
        XCTAssertGreaterThan(panel.glyphs.cachedCount, 0)

        view.handleMemoryWarning()
        XCTAssertEqual(panel.glyphs.cachedCount, 0, "glyph bitmaps go")
        XCTAssertNotNil(view.emojiLibrary, "the open panel keeps its library")

        view.closeEmojiPanel()
        XCTAssertNil(view.emojiPanel, "closing drops the panel")
        XCTAssertNotNil(view.emojiLibrary)
        view.handleMemoryWarning()
        XCTAssertNil(view.emojiLibrary, "a closed panel's library goes on a warning")
    }

    // MARK: - Emoji

    /// Settings › Experiments › ABC under the emoji key, from Hex's `EmojiPanelLettersKeyTests`:
    /// on, the panel's ABC takes the emoji key's x and width; off, it keeps the bar's leading end.
    func testLettersKeySitsUnderTheEmojiKeyOnlyWithTheExperiment() throws {
        for width in [375, 402, 440] as [CGFloat] {
            for needsGlobe in [false, true] {
                for experiment in [true, false] {
                    let model = KeyboardViewModel()
                    model.needsGlobeKey = needsGlobe
                    let view = FullKeyboardView(model: model, target: HexFixtureTextTarget())
                    view.emojiOverride = true
                    view.emojiLettersUnderEmojiKeyOverride = experiment
                    view.makeEmojiUsage = { [defaults] in EmojiUsageStore(defaults: defaults!) }
                    view.frame = CGRect(x: 0, y: 0, width: width, height: view.preferredHeight)
                    view.layoutIfNeeded()
                    view.debugOpenEmoji()
                    view.layoutIfNeeded()

                    let panel = try XCTUnwrap(view.emojiPanel)
                    panel.layoutIfNeeded()
                    let letters = try XCTUnwrap(panel.subviews.first { $0.accessibilityLabel == "Letters" })
                    let key = try XCTUnwrap(view.engine.layout.key(.emoji), "an emoji key on a \(width) pt keyboard")
                    let frame = letters.convert(letters.bounds, to: view)
                    let context = "\(width) pt, globe \(needsGlobe), experiment \(experiment)"
                    if experiment {
                        XCTAssertEqual(frame.midX, key.frame.midX, accuracy: 0.5, context)
                        XCTAssertEqual(frame.width, key.frame.width, accuracy: 0.5, context)
                    } else {
                        let keyWidth = min(44, KeyboardLayout.letterWidth(
                            innerWidth: width - 2 * panel.horizontalInset,
                            metrics: panel.metrics
                        ) * KeyboardLayout.bottomSwitchWidthRatio)
                        XCTAssertEqual(frame.minX, panel.horizontalInset + panel.metrics.side, accuracy: 0.5, context)
                        XCTAssertEqual(frame.width, keyWidth, accuracy: 0.5, context)
                    }
                }
            }
        }
    }

    func testEmojiSearchKeepsTheFieldsSecureEntry() {
        let secure = SecureFixtureTarget()
        let routed = EmojiRoutedTarget(document: secure)
        XCTAssertEqual(routed.isSecureTextEntry, true)
        routed.query = ""
        XCTAssertEqual(routed.isSecureTextEntry, true, "searching keeps the field's secure entry")
    }

    // MARK: - Keyboard languages

    func testKeyboardLanguagesReadHexsStoredSettings() {
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.keyboardLanguages, [])
        XCTAssertNil(settings.currentKeyboardLanguage)
        defaults.set(["de", "en", "de", "zz"], forKey: "settings.keyboardLanguages")
        XCTAssertEqual(settings.keyboardLanguages, [.german, .english], "unknown and repeated languages drop")
        settings.currentKeyboardLanguage = .english
        XCTAssertEqual(settings.currentKeyboardLanguage, .english)
        XCTAssertEqual(settings.letterLayout(for: .german), KeyboardLanguage.german.offered(nil))
    }
}

@MainActor
private final class SecureFixtureTarget: KeyboardTextTarget {
    var documentContextBeforeInput: String? { "" }
    var documentContextAfterInput: String? { "" }
    var hasText: Bool { false }
    var autocapitalizationType: UITextAutocapitalizationType? { UITextAutocapitalizationType.none }
    var keyboardType: UIKeyboardType? { .default }
    var returnKeyType: UIReturnKeyType? { .default }
    var keyboardAppearance: UIKeyboardAppearance? { nil }
    var isSecureTextEntry: Bool? { true }
    var smartQuotesType: UITextSmartQuotesType? { nil }
    var smartDashesType: UITextSmartDashesType? { nil }
    func insertText(_ text: String) {}
    func deleteBackward() {}
}
