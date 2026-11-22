import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprFullKeyboardEngineTests: XCTestCase {
    private var target: FixtureTextTarget!
    private var engine: TyprFullKeyboardEngine!
    private var now: TimeInterval = 100
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "TyprFullKeyboardEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let ac = TyprAutocorrectEngine(learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        engine = TyprFullKeyboardEngine(target: target, autocorrect: ac)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func point(_ kind: TyprKeyKind) -> CGPoint {
        let key = engine.layout.key(kind)!
        return CGPoint(x: key.frame.midX, y: key.frame.midY)
    }

    private func down(_ id: Int, _ kind: TyprKeyKind) { engine.touchBegan(id: id, at: point(kind)) }
    private func up(_ id: Int, _ kind: TyprKeyKind) { engine.touchEnded(id: id, at: point(kind)) }

    private func tap(_ kind: TyprKeyKind) {
        let at = point(kind)
        engine.touchBegan(id: 1, at: at)
        engine.touchEnded(id: 1, at: at)
    }

    private func type(_ text: String) {
        for ch in text {
            tap(ch == " " ? .space : .character(String(ch)))
            now += 0.5
        }
    }

    func testOnlyTheTouchedCopyOfARepeatedSplitKeyIsPressed() {
        engine.width = 951
        engine.orientation = .splitLandscape
        let copies = engine.layout.keys.filter { $0.kind == .character("g") }
        XCTAssertEqual(copies.count, 2)
        for (index, copy) in copies.enumerated() {
            let at = CGPoint(x: copy.frame.midX, y: copy.frame.midY)
            engine.touchBegan(id: 1, at: at)
            XCTAssertEqual(copies.map(engine.isPressed), copies.indices.map { $0 == index }, "copy \(index)")
            engine.touchEnded(id: 1, at: at)
        }
        XCTAssertEqual(target.text, "gg")
    }

    func testRolloverKeepsOrder() {
        down(1, .character("t"))
        down(2, .character("h"))
        up(1, .character("t"))
        up(2, .character("h"))
        XCTAssertEqual(target.text, "th")
    }

    func testRolloverWhenTheSecondKeyLiftsFirst() {
        down(1, .character("t"))
        down(2, .character("h"))
        up(2, .character("h"))
        up(1, .character("t"))
        XCTAssertEqual(target.text, "th")
    }

    func testRolloverWithTheSpaceBarKeepsOrder() {
        down(1, .character("a"))
        down(2, .space)
        up(1, .character("a"))
        down(3, .character("b"))
        up(3, .character("b"))
        up(2, .space)
        XCTAssertEqual(target.text, "a b")

        let start = point(.space)
        down(4, .space)
        down(5, .character("c"))
        now += TyprFullKeyboardEngine.trackpadDelay + 0.1
        engine.touchMoved(id: 4, to: CGPoint(x: start.x - 30, y: start.y))
        XCTAssertFalse(engine.isTrackpadActive, "a space already typed doesn't become the trackpad")
        engine.touchEnded(id: 4, at: CGPoint(x: start.x - 30, y: start.y))
        up(5, .character("c"))
        XCTAssertEqual(target.text, "a b c")
    }

    func testSlidingToAnotherKeyTypesWhereTheFingerLifts() {
        down(1, .character("f"))
        engine.touchMoved(id: 1, to: point(.character("g")))
        XCTAssertEqual(engine.previewKey?.kind, .character("g"))
        up(1, .character("g"))
        XCTAssertEqual(target.text, "g")
    }

    func testShiftChordAndOneShot() {
        down(1, .shift)
        down(2, .character("a"))
        up(2, .character("a"))
        down(3, .character("b"))
        up(3, .character("b"))
        up(1, .shift)
        tap(.character("c"))
        XCTAssertEqual(target.text, "ABc")

        tap(.shift)
        tap(.character("d"))
        tap(.character("e"))
        XCTAssertEqual(target.text, "ABcDe")
    }

    func testDoubleTapShiftLocks() {
        tap(.shift)
        now += 0.1
        tap(.shift)
        type("hi")
        XCTAssertEqual(target.text, "HI")
        XCTAssertEqual(engine.shift.state, .locked)
    }

    func testHoldNumbersSlideToADigitAndLetGo() {
        down(1, .layerSwitch(.numbers))
        XCTAssertEqual(engine.layout.layer, .numbers)
        engine.touchMoved(id: 1, to: point(.character("7")))
        engine.touchEnded(id: 1, at: point(.character("7")))
        XCTAssertEqual(target.text, "7")
        XCTAssertEqual(engine.layout.layer, .letters)
    }

    func testHoldingNumbersSwitchesKeyboardsOnlyWhenTheGlobeDoesNot() {
        engine.showsGlobe = true
        for globeKey in GlobeKey.allCases {
            engine.globeKey = globeKey
            let layerKey = point(.layerSwitch(.numbers))
            engine.touchBegan(id: 1, at: layerKey)
            XCTAssertEqual(engine.takeNextKeyboardHold(forTouch: 1), globeKey != .switches, "\(globeKey)")
            engine.touchEnded(id: 1, at: layerKey)
            if globeKey == .switches { tap(.layerSwitch(.letters)) }
            XCTAssertEqual(engine.layout.layer, .letters, "\(globeKey)")
            XCTAssertTrue(engine.touches.isEmpty)
        }
        XCTAssertEqual(target.text, "")
    }

    func testHoldingNumbersThenSlidingAwayStillTypesThePunctuation() {
        engine.showsGlobe = true
        engine.globeKey = .hidden
        down(1, .layerSwitch(.numbers))
        engine.touchMoved(id: 1, to: point(.character(".")))
        XCTAssertFalse(engine.takeNextKeyboardHold(forTouch: 1))
        engine.touchEnded(id: 1, at: point(.character(".")))
        XCTAssertEqual(target.text, ".")
    }

    func testThePeriodKeyTypesAPeriodAndItsHoldOffersMorePunctuation() throws {
        engine.bottomRow = BottomRow(order: BottomKey.standard, periodKey: true)
        tap(.character("."))
        XCTAssertEqual(target.text, ".")

        down(1, .character("."))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        let menu = try XCTUnwrap(engine.activeAccentMenu)
        XCTAssertEqual(Set(menu.options), Set(TyprAccentCatalog.periodKey))
        let cell = menu.cellFrames[try XCTUnwrap(menu.options.firstIndex(of: ","))]
        engine.touchMoved(id: 1, to: CGPoint(x: cell.midX, y: cell.midY))
        engine.touchEnded(id: 1, at: CGPoint(x: cell.midX, y: cell.midY))
        XCTAssertEqual(target.text, ".,")

        tap(.layerSwitch(.numbers))
        down(1, .character("."))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        XCTAssertEqual(Set(try XCTUnwrap(engine.activeAccentMenu).options), Set(TyprAccentCatalog.options(for: ".", uppercase: false) ?? []))
        engine.cancelAllTouches()
    }

    func testNumberRowTypesDigitsOnTheLettersPage() {
        engine.numberRow = true
        type("1a0")
        XCTAssertEqual(target.text, "1a0")
        XCTAssertEqual(engine.layout.layer, .letters)
        XCTAssertNotNil(engine.layout.key(.character("1")))
    }

    func testHoldingNumbersBelowTheNumberRowSwitchesKeyboards() {
        engine.showsGlobe = true
        engine.globeKey = .hidden
        engine.numberRow = true
        let layerKey = point(.layerSwitch(.numbers))
        engine.touchBegan(id: 1, at: layerKey)
        XCTAssertTrue(engine.takeNextKeyboardHold(forTouch: 1))
        XCTAssertEqual(engine.layout.layer, .letters)
        XCTAssertTrue(engine.touches.isEmpty)
    }

    func testGlobeSpacerDoesNothingWhenTapped() {
        engine.showsGlobe = true
        engine.globeKey = .spacer
        tap(.globeSpacer)
        XCTAssertEqual(target.text, "")
        XCTAssertEqual(engine.layout.layer, .letters)
    }

    func testNumbersStayUntilSpace() {
        tap(.layerSwitch(.numbers))
        XCTAssertEqual(engine.layout.layer, .numbers)
        tap(.character("4"))
        tap(.character("2"))
        XCTAssertEqual(engine.layout.layer, .numbers)
        tap(.space)
        XCTAssertEqual(engine.layout.layer, .letters)
        XCTAssertEqual(target.text, "42 ")
    }

    private func resetText(_ text: String = "", keyboardType: UIKeyboardType = .default) {
        target = FixtureTextTarget(text: text)
        target.autocapitalizationType = UITextAutocapitalizationType.none
        target.keyboardType = keyboardType
        let ac = TyprAutocorrectEngine(learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil)
        engine = TyprFullKeyboardEngine(target: target, autocorrect: ac)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    private func punctuation(_ mark: String, sliding: Bool = false) {
        if sliding {
            down(1, .layerSwitch(.numbers))
            let at = point(.character(mark))
            engine.touchMoved(id: 1, to: at)
            engine.touchEnded(id: 1, at: at)
        } else {
            tap(.layerSwitch(.numbers))
            tap(.character(mark))
        }
    }

    func testPunctuationCorrectsTheCurrentWordOnTapAndNumberSlide() {
        for sliding in [false, true] {
            for mark in ["?", "!", ".", ","] {
                resetText()
                type("teh")
                punctuation(mark, sliding: sliding)
                XCTAssertEqual(target.text, "the" + mark)
                XCTAssertNil(engine.autocorrect.pendingFeedback, "punctuation must not teach automatic output")
                XCTAssertNil(engine.autocorrect.touchInput.evidence(beforeInput: target.documentContextBeforeInput))
            }
        }
    }

    func testPunctuationReplacesSpaceAfterAutomaticAndExplicitCorrection() {
        for explicit in [false, true] {
            for mark in ["?", "!", ".", ","] {
                resetText()
                type("teh")
                if explicit {
                    engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
                } else {
                    tap(.space)
                }
                XCTAssertEqual(target.text, "the ")
                punctuation(mark)
                XCTAssertEqual(target.text, "the" + mark)
            }
        }
    }

    func testLongPressPlainPunctuationUsesTheSameBoundaryHandling() throws {
        for trailingSpace in [false, true] {
            for mark in ["?", "!", "."] {
                resetText()
                type("teh")
                if trailingSpace { tap(.space) }
                tap(.layerSwitch(.numbers))
                down(1, .character(mark))
                XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
                let menu = try XCTUnwrap(engine.activeAccentMenu)
                let index = try XCTUnwrap(menu.options.firstIndex(of: mark))
                let cell = menu.cellFrames[index]
                engine.touchEnded(id: 1, at: CGPoint(x: cell.midX, y: cell.midY))
                XCTAssertEqual(target.text, "the" + mark)
            }
        }
    }

    func testPunctuationSpacingStillWorksWithAutocorrectDisabled() {
        for disabledSetting in [false, true] {
            resetText("word ")
            if disabledSetting { engine.autocorrect.isEnabled = false } else { target.autocorrectionType = .no }
            punctuation("?")
            XCTAssertEqual(target.text, "word?", "spacing cleanup is independent of word replacement")
        }
    }

    func testPunctuationDoesNotReconsiderExplicitKeep() {
        type("teh")
        engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "teh", replacement: "teh", kind: .keepLiteral))
        punctuation("?")
        XCTAssertEqual(target.text, "teh?")
    }

    func testDoubleSpaceAfterAutomaticAndExplicitCorrection() {
        for explicit in [false, true] {
            for typrKey in [false, true] {
                resetText()
                type("teh")
                if explicit {
                    engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
                } else {
                    tap(.space)
                }
                now += 0.2
                if typrKey { engine.typeSpaceFromTyprKey() } else { tap(.space) }
                XCTAssertEqual(target.text, "the. ")
                now += 0.1
                tap(.space)
                XCTAssertEqual(target.text, "the.  ")
            }
        }
    }

    func testDelayedSpaceThenQuickSpaceAfterSeparatorTypesPeriodRightAfterWord() {
        for explicit in [false, true] {
            resetText()
            type("teh")
            if explicit {
                engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
            } else {
                tap(.space)
            }
            now += 2
            tap(.space)
            XCTAssertEqual(target.text, "the  ")
            now += 0.2
            tap(.space)
            XCTAssertEqual(target.text, "the. ")
        }
    }

    func testSlowSecondTapAfterDelayedSpaceDoesNotInsertPeriod() {
        type("ok")
        tap(.space)
        now += 2
        tap(.space)
        now += 0.5
        tap(.space)
        XCTAssertEqual(target.text, "ok   ")
    }

    func testSpacesAfterNonWordDoNotInsertPeriod() {
        resetText("ok. ")
        tap(.space)
        now += 0.2
        tap(.space)
        XCTAssertEqual(target.text, "ok.   ")
    }

    func testSlowSpaceAfterSuggestionDoesNotInsertPeriod() {
        type("teh")
        engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
        now += 0.5
        tap(.space)
        XCTAssertEqual(target.text, "the  ")
    }

    func testPunctuationPreservesWhitespaceAndNonProseFields() {
        for text in ["word  ", "word\n", "word\t", " "] {
            resetText(text)
            punctuation("?")
            XCTAssertEqual(target.text, text + "?")
        }
        for field in [UIKeyboardType.emailAddress, .URL] {
            resetText("teh ", keyboardType: field)
            punctuation(".")
            XCTAssertEqual(target.text, "teh .")
            resetText("teh", keyboardType: field)
            punctuation(".")
            XCTAssertEqual(target.text, "teh.")
        }
    }

    func testPunctuationRespectsDisabledAutocorrect() {
        for disabledSetting in [false, true] {
            resetText()
            if disabledSetting { engine.autocorrect.isEnabled = false } else { target.autocorrectionType = .no }
            type("teh")
            punctuation("!")
            XCTAssertEqual(target.text, "teh!")
        }
    }

    func testDeleteUndoesPunctuationCorrectionWithoutLearningPunctuationAsAWord() {
        type("teh")
        punctuation("?")
        engine.deleteAndRevert()
        XCTAssertEqual(target.text, "teh")
        XCTAssertTrue(engine.autocorrect.learning.model.lexicon.isRejected(typed: "teh", replacement: "the"))
        XCTAssertFalse(engine.autocorrect.learning.model.lexicon.isRejected(typed: "teh", replacement: "the?"))
        XCTAssertNil(engine.autocorrect.pendingFeedback)
    }

    func testExternalCursorChangeInvalidatesSuggestionDoubleSpace() {
        type("teh")
        engine.acceptOwnedFixtureSuggestion(TyprKeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
        engine.textDidChange()
        now += 0.1
        tap(.space)
        XCTAssertEqual(target.text, "the  ")
    }

    func testDoubleSpaceTypesAPeriod() {
        type("ok")
        tap(.space)
        now += 0.2
        tap(.space)
        XCTAssertEqual(target.text, "ok. ")
        now += 0.2
        tap(.space)
        XCTAssertEqual(target.text, "ok.  ", "a third space is just a space")
    }

    // Typr: a tap on the Typr key types a space like the space bar.
    func testTyprKeySpaceActsLikeTheSpaceBar() {
        type("ok")
        engine.typeSpaceFromTyprKey()
        XCTAssertEqual(target.text, "ok ")
        now += 0.2
        engine.typeSpaceFromTyprKey()
        XCTAssertEqual(target.text, "ok. ", "double space still types a period")
        tap(.layerSwitch(.numbers))
        tap(.character("4"))
        engine.typeSpaceFromTyprKey()
        XCTAssertEqual(engine.layout.layer, .letters, "back to letters after a space")
        XCTAssertEqual(target.text, "ok. 4 ")
    }

    func testSentenceAutoCapitalization() {
        target.autocapitalizationType = .sentences
        engine.configureForField()
        XCTAssertEqual(engine.shift.state, .on)
        type("hi")
        tap(.space)
        now += 0.2
        tap(.space)
        type("there")
        XCTAssertEqual(target.text, "Hi. There")
    }

    func testAcceleratingDeleteRampAndWordDelete() {
        type("hello world")
        down(1, .delete)
        XCTAssertEqual(target.text, "hello worl")
        // Initial repeat deletes 1 char.
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.repeatDelay)
        XCTAssertEqual(target.text, "hello wor")
        // Accelerated repeat deletes 2 chars per tick.
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.fastRepeatAfter)
        XCTAssertEqual(target.text, "hello w")
        // After 1.4 s, removes whole words backward.
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.wordDeleteAfter)
        XCTAssertEqual(target.text, "hello ")
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.wordDeleteAfter)
        XCTAssertEqual(target.text, "")
        up(1, .delete)
    }

    func testLongPressAccentPickerSelectsAndUppercaseWorks() {
        tap(.shift)
        down(1, .character("e"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        let menu = try! XCTUnwrap(engine.activeAccentMenu)
        XCTAssertNil(engine.previewKey, "single-key balloon hides while accent picker is open")
        XCTAssertEqual(menu.options.first, "E")
        // Slide to index 2 ("É").
        let cell = menu.cellFrames[2]
        engine.touchMoved(id: 1, to: CGPoint(x: cell.midX, y: cell.midY))
        engine.touchEnded(id: 1, at: CGPoint(x: cell.midX, y: cell.midY))
        XCTAssertNil(engine.activeAccentMenu)
        XCTAssertEqual(target.text, "É")
        XCTAssertEqual(engine.shift.state, .off)
    }

    func testSpacebarTrackpadMovesCaretWithoutInsertingSpace() {
        type("helo")
        let spaceStart = point(.space)
        engine.touchBegan(id: 1, at: spaceStart)
        now += TyprFullKeyboardEngine.trackpadDelay + 0.1
        // Enter trackpad mode (-12 pt) then drag left by 16 pt (-2 chars: before "lo").
        let enterPoint = CGPoint(x: spaceStart.x - 12, y: spaceStart.y)
        engine.touchMoved(id: 1, to: enterPoint)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchMoved(id: 1, to: CGPoint(x: enterPoint.x - 16, y: spaceStart.y))
        engine.touchEnded(id: 1, at: CGPoint(x: enterPoint.x - 16, y: spaceStart.y))
        XCTAssertFalse(engine.isTrackpadActive)
        XCTAssertEqual(target.cursorIndex, 2)
        tap(.character("l"))
        XCTAssertEqual(target.text, "hello")
    }

    /// A quick space tap that drifts still types a space, as on Apple's: taps of 60 to 150 ms
    /// sliding 12 to 40 pt used to start the trackpad and type nothing (Hex #2233).
    func testAQuickSpaceTapThatDriftsTypesASpace() {
        let start = point(.space)
        for (id, ms, dx) in [(1, 60.0, CGFloat(12)), (2, 100, 16), (3, 150, 24), (4, 100, -16), (5, 150, 40)] {
            type("a")
            engine.touchBegan(id: id, at: start)
            now += ms / 2000
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx / 2, y: start.y))
            now += ms / 2000
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx, y: start.y))
            XCTAssertFalse(engine.isTrackpadActive, "\(ms) ms, \(dx) pt")
            engine.touchEnded(id: id, at: CGPoint(x: start.x + dx, y: start.y))
            now += 0.5
        }
        XCTAssertEqual(target.text, "a a a a a ")
    }

    func testASlowSpaceDragStillMovesTheCursor() {
        type("hallo")
        let start = point(.space)
        engine.touchBegan(id: 1, at: start)
        for step in 1...10 {
            now += 0.06
            engine.touchMoved(id: 1, to: CGPoint(x: start.x - 4 * CGFloat(step), y: start.y))
        }
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: CGPoint(x: start.x - 40, y: start.y))
        XCTAssertEqual(target.text, "hallo")
        XCTAssertEqual(target.cursorIndex, 3)
    }

    private func useAppleTrackpad(text: String) {
        engine.followsTextOnTrackpad = true
        engine.trackpadLineHeight = 20
        engine.trackpadCharacterWidth = { $0.isNewline ? 0 : 10 }
        target.insertText(text)
        engine.textDidChange()
    }

    private func slideSpace(id: Int, from start: CGPoint, by dx: CGFloat, steps: Int, interval: TimeInterval) -> CGPoint {
        var at = start
        for step in 1...steps {
            now += interval
            at = CGPoint(x: start.x + dx * CGFloat(step) / CGFloat(steps), y: start.y)
            engine.touchMoved(id: id, to: at)
        }
        return at
    }

    func testTheAppleTrackpadMovesTheCursorUpAndDownThroughLines() {
        useAppleTrackpad(text: "Hallo Welt\nwie geht es dir")
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        engine.touchMoved(id: 1, to: CGPoint(x: space.x, y: space.y - 20))
        XCTAssertEqual(target.cursorIndex, 10, "up a line, at the end of the shorter \"Hallo Welt\"")
        engine.touchMoved(id: 1, to: CGPoint(x: space.x, y: space.y))
        XCTAssertEqual(target.cursorIndex, 26, "down again, at its x")
        engine.touchMoved(id: 1, to: CGPoint(x: space.x - 50, y: space.y))
        engine.touchEnded(id: 1, at: CGPoint(x: space.x - 50, y: space.y))
        XCTAssertEqual(target.cursorIndex, 21)
        XCTAssertEqual(target.text, "Hallo Welt\nwie geht es dir")
    }

    func testTheAppleTrackpadMovesFurtherOnAFastDragThanOnASlowOne() {
        useAppleTrackpad(text: "Das ist ein ziemlich langer Satz")
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        engine.touchEnded(id: 1, at: slideSpace(id: 1, from: space, by: -80, steps: 8, interval: 0.1))
        let slow = 32 - target.cursorIndex
        XCTAssertEqual(slow, 9, "80 pt at 100 pt/s goes 1.06 times as far: 8.5 characters")

        target.adjustTextPosition(byCharacterOffset: slow)
        engine.textDidChange()
        now += 1
        engine.touchBegan(id: 2, at: space)
        engine.holdSpace(forTouch: 2)
        engine.touchEnded(id: 2, at: slideSpace(id: 2, from: space, by: -80, steps: 8, interval: 0.005))
        let fast = 32 - target.cursorIndex
        XCTAssertGreaterThan(fast, 2 * slow, "80 pt at 2,000 pt/s goes about 2.6 times as far")
        XCTAssertEqual(target.text, "Das ist ein ziemlich langer Satz")
    }

    /// Holding the space bar still starts the trackpad, as Apple's does, so letting go types
    /// nothing; sliding after the hold moves the cursor and never ticks (Apple's asks for no
    /// feedback after the space bar's own).
    func testHoldingSpaceStillStartsTheAppleTrackpadAndTypesNoSpace() {
        useAppleTrackpad(text: "hallo ")
        var ticks = 0
        engine.onSelectionStep = { ticks += 1 }
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: space)
        XCTAssertEqual(target.text, "hallo ")

        engine.touchBegan(id: 2, at: space)
        engine.holdSpace(forTouch: 2)
        let left = CGPoint(x: space.x - 21, y: space.y)
        engine.touchMoved(id: 2, to: left)
        engine.touchEnded(id: 2, at: left)
        XCTAssertEqual(target.text, "hallo ")
        XCTAssertEqual(target.cursorIndex, 4)
        XCTAssertEqual(ticks, 0)
    }

    func testWithTheAppleTrackpadAQuickSpaceTapThatDriftsStillTypesASpace() {
        useAppleTrackpad(text: "")
        let start = point(.space)
        for (id, ms, dx) in [(1, 60.0, CGFloat(12)), (2, 150, 24), (3, 150, -40)] {
            type("a")
            engine.touchBegan(id: id, at: start)
            now += ms / 2000
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx / 2, y: start.y))
            now += ms / 2000
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx, y: start.y))
            XCTAssertFalse(engine.isTrackpadActive, "\(ms) ms, \(dx) pt")
            engine.touchEnded(id: id, at: CGPoint(x: start.x + dx, y: start.y))
            now += 0.5
        }
        XCTAssertEqual(target.text, "a a a ")
    }

    func testTheAppleTrackpadAlsoStartsBySlidingOnceHeld() {
        useAppleTrackpad(text: "hallo")
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        let end = slideSpace(id: 1, from: space, by: -40, steps: 10, interval: 0.06)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: end)
        XCTAssertEqual(target.text, "hallo")
        XCTAssertEqual(target.cursorIndex, 3, "started 24 pt in, the last 16 pt move it")
    }

    func testWithoutTheExperimentHoldingSpaceStillTypesASpace() {
        type("hallo")
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        now += TyprFullKeyboardEngine.trackpadDelay + 0.1
        engine.holdSpace(forTouch: 1)
        XCTAssertFalse(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: space)
        XCTAssertEqual(target.text, "hallo ")
    }

    private func slideDelete(_ id: Int, keyWidths: CGFloat) {
        let start = point(.delete)
        engine.touchMoved(id: id, to: CGPoint(x: start.x - keyWidths * engine.layout.letterWidth, y: start.y))
    }

    func testSlidingLeftFromDeleteRemovesAWordPerKeyWidthAndSlidingBackTypesThemBack() {
        resetText("Wir sehen uns, Grüße. Straße")
        engine.slidesDeleteByWord = true
        var ticks = 0
        engine.onSelectionStep = { ticks += 1 }

        down(1, .delete)
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße. Straß", "going down deletes a letter, as a tap does")
        slideDelete(1, keyWidths: 0.6)
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße. Straß")
        XCTAssertFalse(engine.isDeleteSliding)

        slideDelete(1, keyWidths: 1.2)
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße. ")
        XCTAssertTrue(engine.isDeleteSliding)
        slideDelete(1, keyWidths: 2.2)
        XCTAssertEqual(target.text, "Wir sehen uns, ", "spaces and punctuation go with the word before them")
        slideDelete(1, keyWidths: 3.2)
        XCTAssertEqual(target.text, "Wir sehen ")
        XCTAssertEqual(ticks, 3)

        slideDelete(1, keyWidths: 1.5)
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße. ")
        XCTAssertEqual(ticks, 5)

        engine.touchEnded(id: 1, at: CGPoint(x: point(.delete).x - 1.5 * engine.layout.letterWidth, y: point(.delete).y))
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße. ", "lifting keeps what is deleted")
        XCTAssertFalse(engine.isDeleteSliding)

        tap(.delete)
        XCTAssertEqual(target.text, "Wir sehen uns, Grüße.", "a tap after it deletes one character")
    }

    func testSlidingDeleteBackToWhereItWentDownRestoresEveryWord() {
        resetText("Schöne Grüße")
        engine.slidesDeleteByWord = true
        down(1, .delete)
        slideDelete(1, keyWidths: 6.5)
        XCTAssertEqual(target.text, "", "the slide stops at the start of the text")
        slideDelete(1, keyWidths: 0)
        XCTAssertEqual(target.text, "Schöne Grüß", "the letter the press deleted stays deleted")
        up(1, .delete)
        XCTAssertEqual(target.text, "Schöne Grüß")
    }

    func testTheDeleteSlideWorksFromItsStartingTextWhenTheHostReportsContextLate() {
        let host = LateContextTarget(text: "Hallo schöne Welt")
        engine = TyprFullKeyboardEngine(target: host, autocorrect: TyprAutocorrectEngine(
            learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil))
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
        engine.slidesDeleteByWord = true

        down(1, .delete)
        host.freezesContext = true
        slideDelete(1, keyWidths: 2.2)
        XCTAssertEqual(host.text, "Hallo ")
        slideDelete(1, keyWidths: 0)
        XCTAssertEqual(host.text, "Hallo schöne Wel")
        up(1, .delete)
        XCTAssertEqual(host.text, "Hallo schöne Wel")
    }

    func testAnotherKeyDuringADeleteSlideKeepsWhatWasDeletedAndEndsTheSlide() {
        for (key, typed) in [(TyprKeyKind.character("x"), "Hallo schöne x"), (.space, "Hallo schöne  "),
                             (.returnKey, "Hallo schöne \n")] {
            resetText("Hallo schöne Welt")
            engine.slidesDeleteByWord = true
            down(1, .delete)
            slideDelete(1, keyWidths: 1.2)
            XCTAssertEqual(target.text, "Hallo schöne ", "\(key)")
            down(2, key)
            up(2, key)
            XCTAssertEqual(target.text, typed, "\(key)")
            slideDelete(1, keyWidths: 2.2)
            slideDelete(1, keyWidths: 0)
            up(1, .delete)
            XCTAssertEqual(target.text, typed, "\(key): the slide ended at the other key")
        }
    }

    func testASwipeOrSuggestionDuringADeleteSlideEndsTheSlide() {
        resetText("Hallo schöne Welt")
        engine.slidesDeleteByWord = true
        down(1, .delete)
        slideDelete(1, keyWidths: 1.2)
        let letter = point(.character("a"))
        engine.touchBegan(id: 2, at: letter)
        engine.touchMoved(id: 2, to: CGPoint(x: letter.x + 3 * engine.layout.letterWidth, y: letter.y))
        engine.touchCancelled(id: 2)
        slideDelete(1, keyWidths: 2.2)
        XCTAssertEqual(target.text, "Hallo schöne ", "a second finger starting a swipe ends the slide")
        up(1, .delete)

        down(3, .delete)
        slideDelete(3, keyWidths: 1.2)
        XCTAssertEqual(target.text, "Hallo ")
        engine.insertEmoji("👋")
        slideDelete(3, keyWidths: 0)
        up(3, .delete)
        XCTAssertEqual(target.text, "Hallo 👋")
    }

    func testWithTheDeleteSlideATapAndAStillHoldDeleteAsBefore() {
        resetText("Hallo Welt")
        engine.slidesDeleteByWord = true
        tap(.delete)
        XCTAssertEqual(target.text, "Hallo Wel")

        down(1, .delete)
        slideDelete(1, keyWidths: 0.4)
        XCTAssertFalse(engine.isDeleteSliding, "a drifting hold keeps repeating")
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.repeatDelay)
        XCTAssertEqual(target.text, "Hallo W")
        engine.repeatDelete(heldFor: TyprFullKeyboardEngine.wordDeleteAfter)
        XCTAssertEqual(target.text, "Hallo ")
        up(1, .delete)
        XCTAssertEqual(target.text, "Hallo ")
    }

    func testWithoutTheExperimentSlidingLeftFromDeleteRemovesNoWords() {
        resetText("Hallo Welt")
        down(1, .delete)
        slideDelete(1, keyWidths: 3.2)
        XCTAssertFalse(engine.isDeleteSliding)
        up(1, .delete)
        XCTAssertEqual(target.text, "Hallo Wel")
    }

    func testDeleteSlideWordsMatchOptionDelete() {
        XCTAssertNil(DeleteWordSlide.wordLength(before: ""))
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "Hallo, Welt. "), 6)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "Schöne Grüße"), 5)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "die Straße?!"), 8)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "so geht's"), 6)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "eine E-Mail"), 4)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "?!"), 2)
        XCTAssertEqual(DeleteWordSlide.wordLength(before: "Zeile\n"), 6)
    }

    func testEnablesReturnKeyAutomaticallyBlocksEmptyField() {
        target.enablesReturnKeyAutomatically = true
        tap(.returnKey)
        XCTAssertEqual(target.text, "")
        type("ok")
        tap(.returnKey)
        XCTAssertEqual(target.text, "ok\n")
    }

    func testRecordingPanelAllocatesLazilyAndTearsDownOnIdle() {
        let model = KeyboardViewModel()
        let view = TyprFullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.layoutIfNeeded()
        XCTAssertFalse(view.hasAllocatedRecordingPanel, "no Metal scope allocated while typing")

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
        XCTAssertFalse(view.hasAllocatedRecordingPanel, "Metal scope torn down once recording ends")
    }

    func testRecordingPanelSitsInTheStripAndTheKeysStay() throws {
        let model = KeyboardViewModel()
        let view = TyprFullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.layoutIfNeeded()
        let strip = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyboardStripView }.first)
        let plane = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyboardKeyPlaneView }.first)
        let key = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyControl }.first)
        let keysFrame = plane.frame
        let stripFrame = strip.frame

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
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { view.hasAllocatedRecordingPanel }
        }, object: nil)
        wait(for: [recording], timeout: 2)
        view.layoutIfNeeded()

        let panel = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyRecordingPanel }.first)
        XCTAssertEqual(panel.frame, CGRect(x: 0, y: stripFrame.minY, width: view.bounds.width, height: stripFrame.height))
        XCTAssertEqual(panel.alpha, 1)
        XCTAssertTrue(strip.isHidden, "the panel replaces the suggestion strip")
        XCTAssertFalse(plane.isHidden)
        XCTAssertEqual(plane.alpha, 1, "the keys stay visible")
        XCTAssertEqual(plane.frame, keysFrame, "and where they were")
        XCTAssertFalse(key.isHidden)
        XCTAssertEqual(key.alpha, 1)

        var events: [String] = []
        model.onDictateTap = { events.append("start") }
        model.onColdStart = { events.append("cold") }
        key.onHold?()
        XCTAssertEqual(events, [], "holding the visible Typr key does not start a second dictation")
    }

    func testTyprKeyTouchDownArmsOnlyWhileWarmAndATapStillTypesASpace() throws {
        let model = KeyboardViewModel()
        var events: [String] = []
        model.onArmDictation = { events.append("arm") }
        model.onDisarmDictation = { events.append("disarm") }
        let view = TyprFullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.layoutIfNeeded()
        let key = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyControl }.first)

        _ = key.beginTracking(UITouch(), with: nil)
        key.endTracking(UITouch(), with: nil)
        XCTAssertEqual(events, ["disarm"])
        XCTAssertEqual(target.text, " ")

        let t = Date().timeIntervalSince1970
        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .ready, heartbeat: t, expiresAt: t + 60),
            isModelInstalled: true,
            style: .polished,
            now: t,
            clearPending: false,
            animated: false
        )
        let warm = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { key.isWarm }
        }, object: nil)
        wait(for: [warm], timeout: 2)

        events = []
        _ = key.beginTracking(UITouch(), with: nil)
        XCTAssertEqual(events, ["arm"], "warm: the touch-down arms")
        key.endTracking(UITouch(), with: nil)
        XCTAssertEqual(events, ["arm", "disarm"], "the tap drops the arming")
        XCTAssertEqual(target.text.count, 2, "and types its space")
        XCTAssertTrue(target.text.hasSuffix(" "))

        events = []
        _ = key.beginTracking(UITouch(), with: nil)
        key.cancelTracking(with: nil)
        XCTAssertEqual(events, ["arm", "disarm"], "a cancelled touch drops the arming")
        XCTAssertEqual(target.text.count, 2, "a cancelled touch types nothing")
    }

    func testColdTyprKeyArmsOnlyForInKeyboardDictation() throws {
        let model = KeyboardViewModel()
        var events: [String] = []
        model.onArmDictation = { events.append("arm") }
        model.onDisarmDictation = { events.append("disarm") }
        let view = TyprFullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.layoutIfNeeded()
        let key = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyControl }.first)
        XCTAssertFalse(key.isWarm)

        model.armsWhenCold = true
        _ = key.beginTracking(UITouch(), with: nil)
        XCTAssertEqual(events, ["arm"], "in-keyboard dictation arms a cold key on touch-down")
        key.endTracking(UITouch(), with: nil)
        XCTAssertEqual(events, ["arm", "disarm"], "the tap drops it")
        XCTAssertEqual(target.text, " ", "and types its space")
    }

    func testHoldingTheEmptyStripDictatesUntilReleasedAndATapDoesNothing() throws {
        let model = KeyboardViewModel()
        var events: [String] = []
        model.onArmDictation = { events.append("arm") }
        model.onDisarmDictation = { events.append("disarm") }
        model.onDictateTap = { events.append("start") }
        model.onStopTap = { events.append("stop") }
        model.onColdStart = { events.append("cold") }
        let view = TyprFullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 254)
        view.layoutIfNeeded()
        let strip = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyboardStripView }.first)
        let key = try XCTUnwrap(view.subviews.compactMap { $0 as? TyprKeyControl }.first)
        XCTAssertFalse(strip.isHidden)
        let empty = CGPoint(x: strip.frame.minX + 20, y: strip.frame.midY)
        XCTAssertTrue(view.hitTest(empty, with: nil) === view, "the keyboard view, never hidden, owns the hold")

        func waitFor(_ event: String) {
            let seen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { events.contains(event) }
            }, object: nil)
            wait(for: [seen], timeout: 2)
        }
        func expectNoHold(_ body: () -> Void) {
            let fired = expectation(description: "no hold")
            fired.isInverted = true
            model.onDictateTap = { fired.fulfill() }
            body()
            wait(for: [fired], timeout: TyprKeyGesture.holdDuration + 0.3)
            model.onDictateTap = { events.append("start") }
        }

        XCTAssertTrue(view.beginStripPress(at: empty))
        waitFor("cold")
        view.endStripPress()
        XCTAssertEqual(events, ["cold", "disarm"], "cold: the hold opens Typr as the Typr key does, the end stops nothing")

        let t = Date().timeIntervalSince1970
        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .ready, heartbeat: t, expiresAt: t + 60),
            isModelInstalled: true,
            style: .polished,
            now: t,
            clearPending: false,
            animated: false
        )
        let warm = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { key.isWarm }
        }, object: nil)
        wait(for: [warm], timeout: 2)

        events = []
        XCTAssertTrue(view.beginStripPress(at: empty))
        XCTAssertEqual(events, ["arm"], "warm: the touch-down arms")
        waitFor("start")
        XCTAssertEqual(events, ["arm", "start"], "a still hold starts dictating")
        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .recording, heartbeat: t, expiresAt: t + 60, recordingStartedAt: t, jobID: "j1"),
            isModelInstalled: true,
            style: .polished,
            now: t,
            clearPending: false,
            animated: false
        )
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { view.hasAllocatedRecordingPanel && strip.isHidden }
        }, object: nil)
        wait(for: [recording], timeout: 2)
        view.endStripPress()
        XCTAssertEqual(events, ["arm", "start", "disarm", "stop"], "the release after the panel hid the strip stops it")

        model.applyBridgeState(
            hasFullAccess: true,
            snapshot: KeyboardSnapshot(state: .ready, heartbeat: t, expiresAt: t + 60),
            isModelInstalled: true,
            style: .polished,
            now: t,
            clearPending: true,
            animated: false
        )
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !strip.isHidden }
        }, object: nil)
        wait(for: [idle], timeout: 2)

        events = []
        expectNoHold {
            view.beginStripPress(at: empty)
            view.endStripPress()
        }
        XCTAssertEqual(events, ["arm", "disarm"], "a short tap only drops the arming")

        events = []
        expectNoHold {
            view.beginStripPress(at: empty)
            view.moveStripPress(to: CGPoint(x: empty.x + 20, y: empty.y))
        }
        XCTAssertEqual(events, ["arm", "disarm"], "a slide before the hold is no hold")
        XCTAssertEqual(target.text, "", "no strip touch types anything")
    }

    func testStripWordsAndChipsKeepTheirTouchesBesideTheEmptyHoldArea() {
        let strip = TyprKeyboardStripView(frame: CGRect(x: 0, y: 0, width: 393, height: 44))
        let suggestion = TyprKeyboardSuggestion(displayText: "Hallo", replacement: "Hallo", kind: .primary(autoReplace: false))
        let emoji = TyprKeyboardSuggestion(displayText: "😀", replacement: "😀", kind: .secondary)
        var picked: [String] = []
        strip.onSelectSuggestion = { picked.append($0.replacement) }

        strip.update(suggestions: [suggestion, emoji], statusText: nil)
        strip.layoutIfNeeded()
        XCTAssertFalse(strip.hitTest(CGPoint(x: 65, y: 22), with: nil) === strip, "a word's slot takes its touch")
        XCTAssertFalse(strip.hitTest(CGPoint(x: 196, y: 22), with: nil) === strip, "an emoji's slot takes its touch")
        XCTAssertNil(strip.hitTest(CGPoint(x: 330, y: 22), with: nil), "the empty third slot passes through to the hold")
        let slot = strip.hitTest(CGPoint(x: 65, y: 22), with: nil) as? UIControl
        slot?.sendActions(for: .touchDown)
        slot?.sendActions(for: .touchUpInside)
        XCTAssertEqual(picked, ["Hallo"], "tapping a word still picks it")

        strip.update(suggestions: [], statusText: nil, showsUndo: true)
        strip.layoutIfNeeded()
        XCTAssertTrue(strip.hitTest(CGPoint(x: 196, y: 22), with: nil) is UIButton, "Undo dictation takes its touch")
        XCTAssertNil(strip.hitTest(CGPoint(x: 20, y: 22), with: nil), "beside Undo passes through to the hold")

        strip.update(suggestions: [], statusText: nil, showsCodeChip: true)
        strip.layoutIfNeeded()
        XCTAssertTrue(strip.hitTest(CGPoint(x: 196, y: 22), with: nil) is UIButton, "Code from Messages takes its touch")
        XCTAssertNil(strip.hitTest(CGPoint(x: 20, y: 22), with: nil), "beside the code chip passes through to the hold")
    }

    func testEmailFieldShowsAtAndDot() {
        target.keyboardType = .emailAddress
        engine.configureForField()
        tap(.character("@"))
        tap(.character("."))
        XCTAssertEqual(target.text, "@.")
    }

    func testNumberPadOpensOnNumbers() {
        target.keyboardType = .numberPad
        engine.configureForField()
        XCTAssertEqual(engine.layout.layer, .numbers)
    }
}

/// A host whose `documentContextBeforeInput` stops following edits, as some apps report it late.
@MainActor
private final class LateContextTarget: TyprKeyboardTextTarget {
    private let field: FixtureTextTarget
    private var frozenBefore: String?
    var freezesContext = false {
        didSet { frozenBefore = freezesContext ? field.documentContextBeforeInput : nil }
    }

    init(text: String) {
        field = FixtureTextTarget(text: text)
        field.autocapitalizationType = UITextAutocapitalizationType.none
    }

    var text: String { field.text }
    var documentContextBeforeInput: String? { frozenBefore ?? field.documentContextBeforeInput }
    var documentContextAfterInput: String? { field.documentContextAfterInput }
    var hasText: Bool { field.hasText }
    var autocapitalizationType: UITextAutocapitalizationType? { field.autocapitalizationType }
    var keyboardType: UIKeyboardType? { field.keyboardType }
    var returnKeyType: UIReturnKeyType? { field.returnKeyType }
    var keyboardAppearance: UIKeyboardAppearance? { field.keyboardAppearance }
    func insertText(_ text: String) { field.insertText(text) }
    func deleteBackward() { field.deleteBackward() }
}
