import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardKeyPlaneViewTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "KeyboardKeyPlaneViewTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makePlane(text: String = "") -> (KeyboardKeyPlaneView, HexFixtureTextTarget) {
        let target = HexFixtureTextTarget(text: text)
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(
            learnedWords: LearnedWordsStore(defaults: defaults)
        ))
        engine.width = 393
        engine.clock = { 0 }
        engine.configureForField()
        return (KeyboardKeyPlaneView(engine: engine), target)
    }

    private func sample(_ kind: KeyKind, in plane: KeyboardKeyPlaneView) throws -> TypingLogTouchSample {
        let key = try XCTUnwrap(plane.engine.layout.key(kind))
        return TypingLogTouchSample(point: CGPoint(x: key.frame.midX, y: key.frame.midY), timestamp: 0)
    }

    func testCancelledShiftChordAndLetterDoNotTypeOrLeaveShiftHeld() throws {
        let (plane, target) = makePlane()
        let shift = try sample(.shift, in: plane)
        let a = try sample(.character("a"), in: plane)
        plane.began(id: 1, sample: shift)
        plane.began(id: 2, sample: a)
        XCTAssertTrue(plane.engine.shift.isHeld)

        plane.cancelled(id: 1, sample: shift)
        plane.cancelled(id: 2, sample: a)
        plane.ended(id: 2, sample: a)

        XCTAssertFalse(plane.engine.shift.isHeld)
        XCTAssertTrue(plane.engine.pressedKinds.isEmpty)
        XCTAssertEqual(plane.engine.shift.state, .off)
        XCTAssertEqual(target.text, "")

        plane.began(id: 3, sample: shift)
        plane.ended(id: 3, sample: shift)
        XCTAssertEqual(plane.engine.shift.state, .on)
        plane.began(id: 4, sample: a)
        plane.ended(id: 4, sample: a)
        plane.began(id: 5, sample: a)
        plane.ended(id: 5, sample: a)
        XCTAssertEqual(target.text, "Aa")
    }

    func testCancellingSecondShiftPressPreservesTheFirstTapsDoubleTapWindow() throws {
        let (plane, _) = makePlane()
        let shift = try sample(.shift, in: plane)
        var now: TimeInterval = 10
        plane.engine.clock = { now }
        plane.began(id: 1, sample: shift)
        plane.ended(id: 1, sample: shift)

        now = 10.1
        plane.began(id: 2, sample: shift)
        XCTAssertEqual(plane.engine.shift.state, .locked)
        plane.cancelled(id: 2, sample: shift)
        XCTAssertEqual(plane.engine.shift.state, .on)
        XCTAssertFalse(plane.engine.shift.isHeld)

        now = 10.2
        plane.began(id: 3, sample: shift)
        plane.ended(id: 3, sample: shift)
        XCTAssertEqual(plane.engine.shift.state, .locked)
    }

    func testCancelAllRestoresCapsLockAndKeepsSubsequentTypingUppercase() throws {
        let (plane, target) = makePlane()
        let shift = try sample(.shift, in: plane)
        let a = try sample(.character("a"), in: plane)
        for id in 1...2 {
            plane.began(id: id, sample: shift)
            plane.ended(id: id, sample: shift)
        }
        XCTAssertEqual(plane.engine.shift.state, .locked)

        plane.began(id: 3, sample: shift)
        plane.cancelAllTouches()
        plane.ended(id: 3, sample: shift)
        XCTAssertEqual(plane.engine.shift.state, .locked)
        XCTAssertFalse(plane.engine.shift.isHeld)
        plane.began(id: 4, sample: a)
        plane.ended(id: 4, sample: a)
        XCTAssertEqual(target.text, "A")
    }

    func testCancelAllDropsAnUncommittedShiftAndPreservesACommittedChord() throws {
        let (plane, target) = makePlane()
        let shift = try sample(.shift, in: plane)
        let a = try sample(.character("a"), in: plane)

        plane.began(id: 1, sample: shift)
        plane.cancelAllTouches()
        plane.began(id: 2, sample: a)
        plane.ended(id: 2, sample: a)
        XCTAssertEqual(target.text, "a")

        plane.began(id: 3, sample: shift)
        plane.began(id: 4, sample: a)
        plane.ended(id: 4, sample: a)
        plane.cancelAllTouches()
        XCTAssertEqual(plane.engine.shift.state, .off)
        XCTAssertFalse(plane.engine.shift.isHeld)
        XCTAssertEqual(target.text, "aA")
    }

    func testGeometricSwipeCancelsAndNextSwipeCanBeUndoneAfterHostEcho() throws {
        let (plane, target) = makePlane(text: "hello")
        let engine = plane.engine
        let model = try XCTUnwrap(TypingDecoderModel.bundled(engine.language.rawValue))
        let swipe = SwipeTyping(engine: engine, model: model)
        plane.swipe = swipe
        let path = SwipePath.through("world", keys: engine.swipeKeys).map {
            TypingLogTouchSample(point: $0, timestamp: 0)
        }
        let first = try XCTUnwrap(path.first)
        let last = try XCTUnwrap(path.last)

        func draw(_ id: Int) {
            plane.began(id: id, sample: first)
            for point in path.dropFirst().dropLast() {
                plane.moved(id: id, sample: point)
            }
        }

        draw(1)
        XCTAssertTrue(swipe.owns(1))
        XCTAssertTrue(swipe.trail.isShowing)
        plane.cancelAllTouches()
        plane.ended(id: 1, sample: last)
        XCTAssertFalse(swipe.trail.isShowing)
        XCTAssertFalse(engine.isSwiping)
        XCTAssertEqual(target.text, "hello")

        draw(2)
        plane.ended(id: 2, sample: last)
        XCTAssertEqual(target.text, "hello world")
        engine.textDidChange()
        let delete = try sample(.delete, in: plane)
        plane.began(id: 3, sample: delete)
        plane.ended(id: 3, sample: delete)
        XCTAssertEqual(target.text, "hello")
    }

    func testTwoThumbSelectionAndCancellationRouteThroughPlane() throws {
        let (plane, target) = makePlane(text: "ab👍🏽cd")
        let engine = plane.engine
        engine.trackpadSelectionState.enabled = true
        let space = try sample(.space, in: plane)
        let second = try sample(.character("a"), in: plane)
        var left = second
        left.point.x -= "👍🏽cd".reduce(CGFloat.zero) { $0 + FullKeyboardEngine.trackpadWidth($1) }

        for shouldCancel in [true, false] {
            plane.began(id: 1, sample: space)
            engine.holdSpace(forTouch: 1)
            plane.began(id: 2, sample: second)
            plane.moved(id: 2, sample: left)
            XCTAssertEqual(engine.selectionPresentation?.selected, "👍🏽cd")
            if shouldCancel {
                plane.cancelled(id: 2, sample: left)
                plane.ended(id: 1, sample: space)
                XCTAssertFalse(engine.isSelectionActive)
                XCTAssertFalse(engine.isTrackpadActive)
                XCTAssertEqual(target.text, "ab👍🏽cd")
            } else {
                plane.ended(id: 2, sample: left)
                plane.ended(id: 1, sample: space)
                XCTAssertTrue(engine.selectionActionsShown)
                engine.performTrackpadSelectionAction(.delete) { _ in }
                XCTAssertEqual(target.text, "ab")
            }
        }
    }

    func testSplitSlideDeleteDoesNotRepeatAndRestoresOnlyItsWords() async throws {
        let (plane, target) = makePlane(text: "one two, three")
        plane.engine.width = 680
        plane.engine.posture = .unfoldedWide
        XCTAssertTrue(plane.engine.layout.isSplit)
        plane.repeatsHeldDelete = false
        let delete = try sample(.delete, in: plane)
        plane.began(id: 1, sample: delete)
        defer { plane.cancelAllTouches() }
        XCTAssertEqual(target.text, "one two, thre")

        let (defaultPlane, defaultTarget) = makePlane(text: "three")
        let defaultDelete = try sample(.delete, in: defaultPlane)
        let repeated = expectation(description: "Default hold reaches the first repeat tick")
        defaultPlane.began(id: 2, sample: defaultDelete)
        defaultPlane.onKeyDown = { [weak defaultPlane] _ in
            defaultPlane?.onKeyDown = nil
            repeated.fulfill()
        }
        await fulfillment(of: [repeated], timeout: 3)
        defaultPlane.cancelAllTouches()
        XCTAssertLessThan(defaultTarget.text.count, 4)
        XCTAssertEqual(target.text, "one two, thre")

        var left = delete
        left.point.x -= 2.2 * plane.engine.layout.letterWidth
        plane.moved(id: 1, sample: left)
        XCTAssertEqual(target.text, "one ")
        plane.moved(id: 1, sample: delete)
        XCTAssertEqual(target.text, "one two, thre")
        plane.moved(id: 1, sample: left)
        plane.cancelled(id: 1, sample: left)
        plane.moved(id: 1, sample: delete)
        XCTAssertEqual(target.text, "one ")
        XCTAssertNil(plane.deleteSwipe)
    }
}
