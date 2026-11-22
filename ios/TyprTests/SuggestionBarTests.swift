import UIKit
import XCTest
@testable import Typr

/// Typr: *Hide suggestion bar* on the full keyboard.
@MainActor
final class SuggestionBarTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "SuggestionBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTyprKeyboardDefaultsOnEmptyDefaultsAndTheBarSettingPersists() {
        let settings = TyprSettings(defaults: defaults)
        XCTAssertFalse(settings.hideSuggestionBar)
        XCTAssertFalse(settings.aiCleanup)
        XCTAssertTrue(settings.personalLearning)
        XCTAssertTrue(settings.autocorrectGerman)
        XCTAssertTrue(settings.autocorrectEnglish)
        XCTAssertFalse(settings.dictationFeedbackStrip)
        settings.hideSuggestionBar = true
        XCTAssertTrue(TyprSettings(defaults: defaults).hideSuggestionBar)
    }

    private func keyboard(showsBar: Bool, text: String = "") -> (TyprFullKeyboardView, FixtureTextTarget) {
        let target = FixtureTextTarget(text: text)
        let view = TyprFullKeyboardView(model: KeyboardViewModel(), target: target,
            autocorrect: TyprAutocorrectEngine(spatialDecoder: nil))
        view.suggestionBarOverride = showsBar
        view.orientationOverride = .portrait
        view.engine.autocorrect.isEnabled = true
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return (view, target)
    }

    /// The three suggestion slots by position. The Code from Messages and Undo dictation chips are
    /// `UIButton`s with the default tag 0, so they are left out.
    private static func slots(of strip: UIView) -> [UIControl] {
        strip.subviews.compactMap { $0 as? UIControl }.filter { !($0 is UIButton) }.sorted { $0.tag < $1.tag }
    }

    private func press(_ kinds: [TyprKeyKind], on view: TyprFullKeyboardView) {
        for (index, kind) in kinds.enumerated() {
            guard let key = view.engine.layout.key(kind) else { return XCTFail("no key \(kind)") }
            let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
            view.engine.touchBegan(id: 500 + index, at: point)
            view.engine.touchEnded(id: 500 + index, at: point)
        }
    }

    func testHiddenBarMakesTheKeyboardShorterAndComputesNoSuggestions() {
        let (view, _) = keyboard(showsBar: false)
        XCTAssertEqual(view.preferredHeight, 224)
        XCTAssertFalse(view.engine.showsStrip)
        press([.character("t"), .character("e"), .character("h")], on: view)
        XCTAssertTrue(view.engine.suggestions.isEmpty)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 6)
    }

    func testBarOnKeepsTheEarlierKeyboard() {
        let (view, _) = keyboard(showsBar: true)
        XCTAssertEqual(view.preferredHeight, 253)
        press([.character("t"), .character("e"), .character("h")], on: view)
        XCTAssertFalse(view.engine.suggestions.isEmpty)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 35)
    }

    func testAutocorrectOnSpaceStillAppliesWithoutTheBar() {
        let (view, target) = keyboard(showsBar: false)
        press([.character("t"), .character("e"), .character("h"), .space], on: view)
        XCTAssertTrue(target.text.hasSuffix("he "), target.text)
        XCTAssertFalse(target.text.lowercased().contains("teh"), target.text)
    }

    func testHeldStripChipAndAccessibilityUseTheirOwnActivationChoice() throws {
        let strip = TyprKeyboardStripView()
        let old = TyprKeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary)
        let new = TyprKeyboardSuggestion(displayText: "world", replacement: "world", kind: .secondary)
        var selected: TyprKeyboardSuggestion?
        var activationCount = 0
        strip.onSelectSuggestion = { selected = $0; activationCount += 1 }
        strip.update(suggestions: [old], statusText: nil)
        let button = try XCTUnwrap(Self.slots(of: strip).first)
        button.sendActions(for: .touchDown)
        strip.update(suggestions: [new], statusText: nil)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(selected, old, "A delayed ranking must not change a held choice")
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(activationCount, 1, "A control event must not also select the newer chip")
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(selected, new, "VoiceOver activates the current choice without touch-down")
        XCTAssertEqual(activationCount, 2)
        selected = nil
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchCancel)
        button.sendActions(for: .touchUpInside)
        XCTAssertNil(selected)
        XCTAssertEqual(activationCount, 2)
    }

    /// Split layouts spread the three suggestions over the whole strip, both halves and the gap, so long
    /// German words are not cut (they were squeezed over the right half before).
    func testSplitKeyboardSpreadsLongSuggestionsOverTheWholeStrip() throws {
        let rows = [["Hauptmann", "Hauptsache", "selbstverständlich"], ["haupt", "Entschuldigung", "Hauptsache"]]
        for width: CGFloat in [801, 951] {
            let (view, _) = keyboard(showsBar: true)
            view.orientationOverride = .splitLandscape
            view.frame = CGRect(x: 0, y: 0, width: width, height: view.preferredHeight)
            view.layoutIfNeeded()
            XCTAssertGreaterThan(view.engine.layout.metrics.splitGap, 0)
            let strip = try XCTUnwrap(view.subviews.first { $0 is TyprKeyboardStripView } as? TyprKeyboardStripView)
            for words in rows {
                let suggestions = words.map { TyprKeyboardSuggestion(displayText: $0, replacement: $0, kind: .secondary) }
                strip.update(suggestions: suggestions, statusText: nil)
                strip.layoutIfNeeded()
                let slots = Self.slots(of: strip)
                XCTAssertEqual(slots.count, 3)
                XCTAssertEqual(slots[0].frame.minX, 0, accuracy: 0.001, "\(width)")
                XCTAssertEqual(slots[2].frame.maxX, strip.bounds.maxX, accuracy: 0.001, "\(width)")
                for (left, right) in zip(slots, slots.dropFirst()) {
                    XCTAssertEqual(left.frame.maxX, right.frame.minX, accuracy: 0.001)
                }
                for (slot, suggestion) in zip(slots, suggestions) {
                    XCTAssertGreaterThanOrEqual(slot.frame.width, TyprKeyboardStripView.wantedWidth(for: suggestion),
                                                "\(suggestion.displayText) is cut at \(width) pt")
                    XCTAssertEqual(strip.hitTest(CGPoint(x: slot.frame.midX, y: slot.frame.midY), with: nil), slot)
                }
            }
        }
    }

    func testSwitchingTheBarRebuildsTheKeys() {
        let (view, _) = keyboard(showsBar: true)
        view.suggestionBarOverride = false
        XCTAssertEqual(view.preferredHeight, 224)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 6)
        view.suggestionBarOverride = true
        XCTAssertEqual(view.preferredHeight, 253)
    }

    func testSlotWidthsGiveALongWordRoomAndAlwaysFillTheStrip() {
        let equal = TyprKeyboardStripView.slotWidths(total: 393, wanted: [0, 0, 0])
        XCTAssertEqual(equal, [131, 131, 131])
        let long = TyprKeyboardStripView.slotWidths(total: 393, wanted: [60, 150, 60])
        XCTAssertEqual(long.reduce(0, +), 393, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(long[1], 150)
        let crowded = TyprKeyboardStripView.slotWidths(total: 393, wanted: [150, 170, 150])
        XCTAssertEqual(crowded.reduce(0, +), 393, accuracy: 0.001)
        XCTAssertEqual(crowded[0], 131, accuracy: 0.001)
    }

    func testLongGermanWordsFitTheirSlotAtFullSizeOn393Points() {
        for word in ["Entschuldigung", "selbstverständlich", "Möglichkeiten"] {
            let suggestion = TyprKeyboardSuggestion(displayText: word, replacement: word, kind: .primary(autoReplace: true))
            for slot in 0..<3 {
                var wanted: [CGFloat] = [70, 70, 70]
                wanted[slot] = TyprKeyboardStripView.wantedWidth(for: suggestion)
                let widths = TyprKeyboardStripView.slotWidths(total: 393, wanted: wanted)
                XCTAssertGreaterThanOrEqual(widths[slot], wanted[slot], "\(word) in slot \(slot) is cut")
            }
        }
    }
}
