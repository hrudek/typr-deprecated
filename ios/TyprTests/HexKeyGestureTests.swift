import CoreGraphics
import UIKit
import XCTest
@testable import Typr

final class HexKeyGestureTests: XCTestCase {
    func testTapDictates() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 3, y: 2)), .ignored, "a jitter is still a tap")
        XCTAssertEqual(gesture.touchUp(), .tap)
        XCTAssertEqual(gesture.holdElapsed(), .ignored, "a timer left over from the tap")
        XCTAssertEqual(gesture.state, .idle)
    }

    func testStillHoldFiresOnceAndReleaseFinishes() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.holdElapsed(), .ignored)
        XCTAssertEqual(gesture.touchUp(), .release, "push to talk: lifting finishes")
        XCTAssertEqual(gesture.touchUp(), .ignored)
    }

    func testMoveBeforeHoldOpensMenu() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 20, y: 9)), .openMenu)
        XCTAssertEqual(gesture.holdElapsed(), .ignored, "the menu won, no dictation")
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 0, y: -40)), .dragMenu)
        XCTAssertEqual(gesture.touchUp(), .releaseMenu)
        XCTAssertEqual(gesture.state, .idle)
    }

    func testMoveAfterHoldDoesNothing() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 0, y: -80)), .ignored, "no menu once dictating")
        XCTAssertEqual(gesture.touchUp(), .release)
    }

    func testCancelResets() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.cancel(), .abandon, "a press that was neither tap nor hold: drop its capture")
        XCTAssertEqual(gesture.state, .idle)
        XCTAssertEqual(gesture.holdElapsed(), .ignored)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 50, y: 0)), .ignored)
    }

    func testCancelAfterHoldKeepsDictating() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.cancel(), .ignored, "the hold already dictates; Done finishes it")
        XCTAssertEqual(gesture.cancel(), .ignored)
    }

    /// In-keyboard dictation listens from touch-down: the key reports the press at once, and
    /// abandons it only when the touch is cancelled before it is a tap or a hold.
    @MainActor
    func testHexKeyReportsThePressAndAbandonsOnlyACancelledOne() {
        let key = HexKeyControl(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        var presses = 0, abandoned = 0, dictations = 0
        key.onPress = { _ in presses += 1 }
        key.onPressAbandoned = { abandoned += 1 }
        key.onHold = { dictations += 1 }

        _ = key.beginTracking(UITouch(), with: nil)
        XCTAssertEqual(presses, 1, "touch-down, before the lift")
        XCTAssertEqual(dictations, 0)
        key.endTracking(UITouch(), with: nil)
        XCTAssertEqual(dictations, 1, "a tap keeps the capture")
        XCTAssertEqual(abandoned, 0)

        _ = key.beginTracking(UITouch(), with: nil)
        key.cancelTracking(with: nil)
        XCTAssertEqual(presses, 2)
        XCTAssertEqual(abandoned, 1, "the system took the touch: drop it")
        XCTAssertEqual(dictations, 1)
    }

    @MainActor
    func testEndWithoutATouchAbandonsThePress() {
        let key = HexKeyControl(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        var abandoned = 0
        key.onPressAbandoned = { abandoned += 1 }
        key.onHold = { XCTFail("No touch lifted to dictate") }
        _ = key.beginTracking(UITouch(), with: nil)
        key.endTracking(nil, with: nil)
        XCTAssertEqual(abandoned, 1)
        XCTAssertFalse(key.isHighlighted)
    }
}
