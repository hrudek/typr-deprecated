import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardStripViewTests: XCTestCase {
    func testLongGermanWordsFitAtEveryPositionOn393PointIPhone() throws {
        let layout = KeyboardLayout(width: 393)
        let strip = KeyboardStripView(frame: layout.stripFrame)
        strip.textCenterY = layout.metrics.stripTextCenter
        strip.chipHeight = layout.metrics.stripChipHeight

        XCTAssertEqual(strip.bounds.height, 33)
        XCTAssertEqual(strip.chipHeight, 26)
        for word in ["Entschuldigung", "selbstverständlich"] {
            for index in 0..<3 {
                var suggestions = [suggestion("ja"), suggestion("gut"), suggestion("nein")]
                suggestions[index] = suggestion(word, kind: .primary(autoReplace: true))
                try assertSlots(in: strip, fit: suggestions)
            }
        }
    }

    func testLandscapeSlotsUseTheFullSuppliedInsetFrame() throws {
        for width: CGFloat in [801, 951] {
            let inset: CGFloat = 44
            let layout = KeyboardLayout(width: width, orientation: .landscape, horizontalInset: inset)
            let frame = CGRect(x: inset, y: layout.metrics.stripTop, width: width - 2 * inset,
                               height: layout.metrics.stripHeight)
            let keyboard = UIView(frame: CGRect(x: 0, y: 0, width: width, height: layout.totalHeight))
            let strip = KeyboardStripView(frame: frame)
            keyboard.addSubview(strip)
            strip.textCenterY = layout.metrics.stripTextCenter
            strip.chipHeight = layout.metrics.stripChipHeight

            let suggestions = ["Entschuldigung", "gut", "selbstverständlich"].map { suggestion($0) }
            let slots = try assertSlots(in: strip, fit: suggestions)
            XCTAssertEqual(strip.convert(slots[0].frame, to: keyboard).minX, inset, accuracy: 0.001)
            XCTAssertEqual(strip.convert(slots[2].frame, to: keyboard).maxX, width - inset, accuracy: 0.001)
            let compound = suggestion("Kraftfahrzeughaftpflichtversicherung")
            let adaptive = try assertSlots(in: strip, fit: [suggestions[0], compound, suggestions[2]])
            XCTAssertGreaterThan(adaptive[1].frame.width, adaptive[0].frame.width)
            XCTAssertGreaterThan(adaptive[1].frame.width, adaptive[2].frame.width)
        }
    }

    func testHidingWordsPreservesRevertUndoAndClipboardActions() throws {
        let strip = KeyboardStripView(frame: CGRect(x: 0, y: 0, width: 393, height: 33))
        let revert = suggestion("teh", kind: .revert)
        let suggestions = [revert, suggestion("the")]
        var selected: KeyboardSuggestion?
        strip.onSelectSuggestion = { selected = $0 }
        strip.update(suggestions: suggestions, showsUndo: false, statusText: nil, hidesWordSuggestions: true)

        let visibleSlots = slots(in: strip).filter(\.isUserInteractionEnabled)
        XCTAssertEqual(visibleSlots.count, 1)
        let revertSlot = try XCTUnwrap(visibleSlots.first)
        XCTAssertEqual(revertSlot.tag, 0)
        XCTAssertEqual(revertSlot.accessibilityLabel, revert.displayText)
        revertSlot.sendActions(for: .touchUpInside)
        XCTAssertEqual(selected, revert)

        var actions: [String] = []
        strip.onUndoDictation = { actions.append("undo") }
        strip.onPaste = { actions.append("paste") }
        strip.onNextKeyboard = { actions.append("next") }
        strip.update(suggestions: suggestions, showsUndo: true, statusText: nil, clipboard: .dictation,
                     hidesWordSuggestions: true)
        strip.layoutIfNeeded()
        let undo = try XCTUnwrap(chip(String(localized: "Undo dictation"), in: strip))
        XCTAssertEqual(undo.frame.height, 26)
        XCTAssertEqual(undo.frame.midY, strip.bounds.midY)
        undo.sendActions(for: .touchUpInside)
        XCTAssertNil(chip(String(localized: "Paste dictation"), in: strip))

        // A trait-driven repaint must keep the words under the action out of the hit targets.
        strip.palette = FullKeyboardPalette(isDark: true)
        XCTAssertFalse(slots(in: strip).contains(where: \.isUserInteractionEnabled))

        strip.update(suggestions: [suggestion("the")], showsUndo: false, statusText: nil, clipboard: .dictation,
                     hidesWordSuggestions: true)
        let pasteDictation = try XCTUnwrap(chip(String(localized: "Paste dictation"), in: strip))
        pasteDictation.sendActions(for: .touchUpInside)

        strip.update(suggestions: [suggestion("the")], showsUndo: false, statusText: nil,
                     clipboard: .code(canPaste: true), hidesWordSuggestions: true)
        strip.layoutIfNeeded()
        let paste = try XCTUnwrap(chip(String(localized: "Paste"), in: strip))
        let next = try XCTUnwrap(chip(String(localized: "Code from Messages"), in: strip))
        XCTAssertLessThan(paste.frame.maxX, next.frame.minX)
        paste.sendActions(for: .touchUpInside)
        next.sendActions(for: .touchUpInside)
        XCTAssertEqual(actions, ["undo", "paste", "paste", "next"])
    }

    func testFullAccessHintTakesPrecedenceOverNoticeAndStatus() throws {
        let strip = KeyboardStripView(frame: CGRect(x: 0, y: 0, width: 393, height: 33))
        let notice = KeyboardStripNotice(title: "Add to vocabulary", detail: "Wort", button: "Add")
        var actions: [String] = []
        strip.onOpenTyprFromHint = { actions.append("setup") }
        strip.onOpenNotice = { actions.append("notice") }
        strip.update(suggestions: [], showsUndo: true, statusText: "Status", fullAccessHint: true, notice: notice,
                     hidesWordSuggestions: true)
        let setup = try XCTUnwrap(chip(String(localized: "Open Typr"), in: strip))
        XCTAssertNil(chip(notice.button, in: strip))
        XCTAssertNil(chip(String(localized: "Undo dictation"), in: strip))
        setup.sendActions(for: .touchUpInside)

        strip.update(suggestions: [], showsUndo: true, statusText: "Status", notice: notice,
                     hidesWordSuggestions: true)
        let noticeButton = try XCTUnwrap(chip(notice.button, in: strip))
        XCTAssertNil(chip(String(localized: "Open Typr"), in: strip))
        noticeButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(actions, ["setup", "notice"])
    }

    @discardableResult
    private func assertSlots(in strip: KeyboardStripView, fit suggestions: [KeyboardSuggestion]) throws -> [UIControl] {
        strip.update(suggestions: suggestions, showsUndo: false, statusText: nil)
        strip.layoutIfNeeded()
        let slots = slots(in: strip)
        let first = try XCTUnwrap(slots.first)
        let last = try XCTUnwrap(slots.last)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(first.frame.minX, strip.bounds.minX, accuracy: 0.001)
        XCTAssertEqual(last.frame.maxX, strip.bounds.maxX, accuracy: 0.001)
        for (left, right) in zip(slots, slots.dropFirst()) {
            XCTAssertEqual(left.frame.maxX, right.frame.minX, accuracy: 0.001)
        }
        for (slot, suggestion) in zip(slots, suggestions) {
            XCTAssertEqual(slot.accessibilityLabel, suggestion.displayText)
            XCTAssertGreaterThanOrEqual(slot.frame.width, KeyboardStripView.wantedWidth(for: suggestion), suggestion.displayText)
            XCTAssertEqual(strip.hitTest(CGPoint(x: slot.frame.midX, y: slot.frame.midY), with: nil), slot)
        }
        return slots
    }

    private func suggestion(_ text: String, kind: KeyboardSuggestion.Kind = .secondary) -> KeyboardSuggestion {
        KeyboardSuggestion(displayText: text, replacement: text, kind: kind)
    }

    private func slots(in strip: KeyboardStripView) -> [UIControl] {
        strip.subviews.compactMap { $0 as? UIControl }.filter { !($0 is UIButton) }.sorted { $0.tag < $1.tag }
    }

    private func chip(_ title: String, in view: UIView) -> UIButton? {
        guard !view.isHidden else { return nil }
        if let button = view as? UIButton, button.configuration?.title == title { return button }
        for child in view.subviews {
            if let button = chip(title, in: child) { return button }
        }
        return nil
    }
}
