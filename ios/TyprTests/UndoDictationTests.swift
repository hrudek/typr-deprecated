import UIKit
import XCTest
@testable import Typr
@MainActor
final class UndoDictationTests: XCTestCase {
    private let dictation = " Wir sehen uns um zwölf."

    private func keyboard(_ field: FixtureTextTarget) -> FullKeyboardView {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: field,
            autocorrect: AutocorrectEngine(spatialDecoder: nil))
        view.suggestionBarOverride = true
        view.orientationOverride = .portrait
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }
    private func dictate(_ text: String, into field: FixtureTextTarget, at cursor: Int, moveBy offset: Int = 0) -> FullKeyboardView {
        let view = keyboard(field)
        field.adjustTextPosition(byCharacterOffset: cursor - field.cursorIndex)
        let before = field.documentContextBeforeInput ?? "", after = field.documentContextAfterInput ?? ""
        field.insertText(text)
        view.didInsertDictation(text, before: before, after: after)
        if offset != 0 {
            field.adjustTextPosition(byCharacterOffset: offset)
            view.textDidChange()
        }
        view.layoutIfNeeded()
        return view
    }

    private func undoChip(_ view: UIView) -> UIButton? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let button = view as? UIButton, button.configuration?.title == "Undo dictation" { return button }
        return view.subviews.lazy.compactMap(undoChip).first
    }

    func testUndoRemovesTheGermanDictationRightAfterIt() throws {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = dictate(dictation, into: field, at: 11)
        try XCTUnwrap(undoChip(view)).sendActions(for: .touchUpInside)
        XCTAssertEqual(field.text, "Hallo Jörg.")
        XCTAssertEqual(field.cursorIndex, 11)
        XCTAssertNil(undoChip(view))
    }

    func testUndoAfterTheCursorMovedWithinBeforeOrAfterTheDictation() throws {
        let cases: [(String, Int, Int, Int)] = [
            ("Hallo Jörg.", 11, -10, 11),
            ("Hallo Jörg.", 11, -33, 2),
            ("Hallo Jörg. Bis später.", 11, 12, 23),
        ]
        for (text, at, offset, cursor) in cases {
            let field = FixtureTextTarget(text: text)
            let view = dictate(dictation, into: field, at: at, moveBy: offset)
            try XCTUnwrap(undoChip(view), "moved by \(offset)").sendActions(for: .touchUpInside)
            XCTAssertEqual(field.text, text, "moved by \(offset)")
            XCTAssertEqual(field.cursorIndex, cursor, "moved by \(offset)")
            XCTAssertNil(undoChip(view), "moved by \(offset)")
        }
    }

    func testHidesWhenTheDictationWasChanged() {
        let field = FixtureTextTarget(text: "Hallo.")
        let view = dictate(" Danke schön.", into: field, at: 6)
        XCTAssertNotNil(undoChip(view))
        field.deleteBackward()
        field.deleteBackward()
        view.textDidChange()
        view.layoutIfNeeded()
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Hallo. Danke schö")
    }

    func testHidesWhenTheCursorEndsAnEarlierCopyOfTheDictation() {
        let field = FixtureTextTarget(text: " Ja. Ja.")
        let view = dictate(" Ja.", into: field, at: 4, moveBy: -4)
        XCTAssertEqual(field.cursorIndex, 4)
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, " Ja. Ja. Ja.")
    }

    func testHidesWhenTheSameWordsAppearTwice() {
        let field = FixtureTextTarget(text: "Ja. Ja.")
        let view = dictate(" Ja.", into: field, at: 7, moveBy: -5)
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Ja. Ja. Ja.")
    }
    func testKeepsEarlierTextThatEndsLikeTheDictation() {
        let field = FixtureTextTarget(text: "Hallo Ja. Tschüss.")
        let view = dictate(" Ja.", into: field, at: 18, moveBy: -13)
        XCTAssertEqual(field.documentContextBeforeInput, "Hallo Ja.")
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Hallo Ja. Tschüss. Ja.")
    }
    @MainActor private final class SentenceTarget: KeyboardTextTarget {
        let field: FixtureTextTarget
        var selected: String?
        init(_ field: FixtureTextTarget) { self.field = field }
        var selectedText: String? { selected }
        var documentContextBeforeInput: String? {
            let before = field.documentContextBeforeInput ?? ""
            return before.range(of: ". ", options: .backwards).map { String(before[$0.upperBound...]) } ?? before
        }
        var documentContextAfterInput: String? {
            let after = field.documentContextAfterInput ?? ""
            return after.firstIndex(of: ".").map { String(after[...$0]) } ?? after
        }
        var hasText: Bool { field.hasText }
        var autocapitalizationType: UITextAutocapitalizationType? { field.autocapitalizationType }
        var keyboardType: UIKeyboardType? { field.keyboardType }
        var returnKeyType: UIReturnKeyType? { field.returnKeyType }
        var keyboardAppearance: UIKeyboardAppearance? { nil }
        func insertText(_ text: String) { field.insertText(text) }
        func deleteBackward() { field.deleteBackward() }
        func adjustTextPosition(byCharacterOffset offset: Int) { field.adjustTextPosition(byCharacterOffset: offset) }
    }
    private func dictateInSentenceHost(_ text: String, into field: FixtureTextTarget) -> (FullKeyboardView, SentenceTarget) {
        let target = SentenceTarget(field)
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target,
            autocorrect: AutocorrectEngine(spatialDecoder: nil))
        view.suggestionBarOverride = true
        view.orientationOverride = .portrait
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        let before = target.documentContextBeforeInput ?? "", after = target.documentContextAfterInput ?? ""
        target.insertText(text)
        view.didInsertDictation(text, before: before, after: after)
        view.layoutIfNeeded()
        return (view, target)
    }

    func testSentenceOnlyHostUndoesWholeAndHidesWhenTheStartWasRemoved() throws {
        func dictate(into field: FixtureTextTarget) -> FullKeyboardView {
            dictateInSentenceHost(dictation, into: field).0
        }

        let whole = FixtureTextTarget(text: "Hallo Jörg.")
        var view = dictate(into: whole)
        try XCTUnwrap(undoChip(view)).sendActions(for: .touchUpInside)
        XCTAssertEqual(whole.text, "Hallo Jörg.")

        let edited = FixtureTextTarget(text: "Hallo Jörg.")
        view = dictate(into: edited)
        XCTAssertNotNil(undoChip(view))
        edited.adjustTextPosition(byCharacterOffset: -13)
        for _ in 0..<10 { edited.deleteBackward() }
        edited.adjustTextPosition(byCharacterOffset: 13)
        view.textDidChange()
        view.layoutIfNeeded()
        XCTAssertEqual(edited.text, "Hallo Jörg. uns um zwölf.")
        XCTAssertNil(undoChip(view))
    }
    func testNoOfferWhenTheDictationIsAmbiguousRightAfterInsertion() {
        let field = FixtureTextTarget(text: " Ja. Ja.")
        let view = dictate(" Ja.", into: field, at: 4)
        XCTAssertEqual(field.text, " Ja. Ja. Ja.")
        XCTAssertNil(undoChip(view))
    }

    func testNoOfferWhenASentenceOnlyHostShowsPartOfTheDictation() {
        let field = FixtureTextTarget(text: "Hallo.")
        let (view, _) = dictateInSentenceHost(" Satz eins. Satz zwei.", into: field)
        XCTAssertEqual(field.text, "Hallo. Satz eins. Satz zwei.")
        XCTAssertNil(undoChip(view))
    }

    func testSelectingTextHidesTheChip() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let (view, target) = dictateInSentenceHost(dictation, into: field)
        XCTAssertNotNil(undoChip(view))
        target.selected = "zwölf"
        view.selectionDidChange()
        view.layoutIfNeeded()
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Hallo Jörg. Wir sehen uns um zwölf.")
    }

    func testMovingTheCursorKeepsOrHidesTheChipOnSelectionChange() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let (view, _) = dictateInSentenceHost(dictation, into: field)
        field.adjustTextPosition(byCharacterOffset: -10)
        view.selectionDidChange()
        view.layoutIfNeeded()
        XCTAssertNotNil(undoChip(view))
        field.adjustTextPosition(byCharacterOffset: -20)
        view.selectionDidChange()
        view.layoutIfNeeded()
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Hallo Jörg. Wir sehen uns um zwölf.")
    }

    func testSpacebarTrackpadMovingAwayHidesTheChip() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let (view, _) = dictateInSentenceHost(" Ja.", into: field)
        XCTAssertNotNil(undoChip(view))
        var now: TimeInterval = 100
        view.engine.clock = { now }
        let space = view.engine.layout.key(.space)!.frame
        let start = CGPoint(x: space.midX, y: space.midY)
        view.engine.touchBegan(id: 1, at: start)
        now += FullKeyboardEngine.trackpadDelay + 0.1
        let enter = CGPoint(x: start.x - 12, y: start.y)
        view.engine.touchMoved(id: 1, to: enter)
        view.engine.touchMoved(id: 1, to: CGPoint(x: enter.x - 40, y: start.y))
        view.engine.touchEnded(id: 1, at: CGPoint(x: enter.x - 40, y: start.y))
        view.layoutIfNeeded()
        XCTAssertEqual(field.cursorIndex, 10)
        XCTAssertNil(undoChip(view))
        XCTAssertEqual(field.text, "Hallo Jörg. Ja.")
    }

    func testDeleteRemovesOneCharacterAndEndsTheOffer() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = dictate(dictation, into: field, at: 11)
        XCTAssertNotNil(undoChip(view))
        view.engine.deleteBackward()
        view.layoutIfNeeded()
        XCTAssertEqual(field.text, "Hallo Jörg. Wir sehen uns um zwölf")
        XCTAssertNil(undoChip(view))
    }

    func testANewFieldEndsTheOffer() {
        let field = FixtureTextTarget(text: "Hallo Jörg.")
        let view = dictate(dictation, into: field, at: 11)
        view.prepareForField()
        view.layoutIfNeeded()
        XCTAssertNil(undoChip(view))
    }

    func testPlanCountsUTF16AndRefusesSelectionsAndOtherText() {
        let undo = DictationUndo(text: " Grüße 👍🏽", before: "Hallo", after: "")
        XCTAssertEqual(undo.plan(before: "Hal", after: "lo Grüße 👍🏽", selected: nil),
                       DictationUndo.Plan(toEnd: 13, delete: 8, back: -2))
        XCTAssertEqual(undo.plan(before: "Hallo Grüße 👍🏽 und", after: "", selected: nil),
                       DictationUndo.Plan(toEnd: -4, delete: 8, back: 4))
        XCTAssertNil(undo.plan(before: "Hal", after: "lo Grüße 👍🏽", selected: "lo"))
        XCTAssertNil(undo.plan(before: "Tschüss Grüße", after: " 👍🏽", selected: nil))
    }
    func testPlanFindsASentenceShownWithoutItsLeadingSpace() {
        let undo = DictationUndo(text: " Bis später.", before: "Hallo Jörg.", after: "")
        XCTAssertEqual(undo.plan(before: "Bis ", after: "später.", selected: nil),
                       DictationUndo.Plan(toEnd: 7, delete: 12, back: 0))
        XCTAssertNil(undo.plan(before: "Ok. Bis ", after: "später.", selected: nil))
    }
}
