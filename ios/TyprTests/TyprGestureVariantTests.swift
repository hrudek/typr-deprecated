import UIKit
import XCTest
@testable import Typr

/// Typr cursor sliding and Typr delete sliding on Hex's keyboard, alone and with Slide delete
/// to remove words (S3: on, a held delete never repeats, split included).
@MainActor
final class TyprGestureVariantTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var now: TimeInterval = 100

    override func setUp() async throws {
        suiteName = "TyprGestureVariantTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeEngine(text: String, split: Bool = false) -> (FullKeyboardEngine, HexFixtureTextTarget) {
        let target = HexFixtureTextTarget(text: text)
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(
            learnedWords: LearnedWordsStore(defaults: defaults)
        ))
        engine.width = split ? 680 : 393
        if split { engine.posture = .unfoldedWide }
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
        return (engine, target)
    }

    private func point(_ kind: KeyKind, in engine: FullKeyboardEngine) throws -> CGPoint {
        let key = try XCTUnwrap(engine.layout.key(kind))
        return CGPoint(x: key.frame.midX, y: key.frame.midY)
    }

    private func sample(_ point: CGPoint) -> TypingLogTouchSample {
        TypingLogTouchSample(point: point, timestamp: 0)
    }

    private func makeView(landscape: Bool) -> FullKeyboardView {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: HexFixtureTextTarget(text: "one two"))
        view.hexPlacementOverride = .stripTrailing
        if landscape { view.orientationOverride = .landscape }
        view.frame = CGRect(x: 0, y: 0, width: landscape ? 874 : 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return view
    }

    /// Every combination of the two variants with Slide delete to remove words, in portrait at
    /// Typr's compact height and in landscape.
    func testViewMapsEveryCombinationOntoThePlaneAndEngine() {
        let settings = TyprSettings(defaults: defaults)
        for landscape in [false, true] {
            let view = makeView(landscape: landscape)
            if !landscape { XCTAssertEqual(view.preferredHeight, 253, "Typr's compact height") }
            for cursor in [false, true] {
                for deleteSliding in [false, true] {
                    for slideDelete in [false, true] {
                        settings[experiment: .typrCursorSliding] = cursor
                        settings[experiment: .typrDeleteSliding] = deleteSliding
                        settings[experiment: .deleteSlide] = slideDelete
                        view.syncTyprVariants(settings)
                        let label = "cursor \(cursor) deleteSliding \(deleteSliding) slideDelete \(slideDelete)"
                        XCTAssertEqual(view.engine.slidesCursorByCharacter, cursor, label)
                        XCTAssertEqual(view.plane.repeatsHeldDelete, !slideDelete, "S3: " + label)
                        XCTAssertEqual(view.plane.slidesDeleteByWord, slideDelete || !deleteSliding, label)
                    }
                }
            }
            if !landscape { XCTAssertEqual(view.preferredHeight, 253) }
        }
    }

    func testHexTrackpadStartsOnHoldWhenCursorSlidingIsOff() throws {
        let (engine, target) = makeEngine(text: "hello")
        let space = try point(.space, in: engine)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: space)
        XCTAssertEqual(target.text, "hello", "a held space types nothing")
    }

    func testCursorSlidingMovesOneCharacterPerStepAlongTheLineOnly() throws {
        for split in [false, true] {
            let (engine, target) = makeEngine(text: "one two\nthree four", split: split)
            XCTAssertEqual(engine.layout.isSplit, split)
            engine.slidesCursorByCharacter = true
            var ticks = 0
            engine.onSelectionStep = { ticks += 1 }
            let space = try point(.space, in: engine)
            let step = FullKeyboardEngine.trackpadPointsPerCharacter

            engine.touchBegan(id: 1, at: space)
            engine.touchMoved(id: 1, to: CGPoint(x: space.x - 20, y: space.y))
            XCTAssertFalse(engine.isTrackpadActive, "a slide before the hold is still a tap")
            engine.touchMoved(id: 1, to: space)
            engine.holdSpace(forTouch: 1)
            XCTAssertFalse(engine.isTrackpadActive, "the hold alone starts nothing")
            let start = CGPoint(x: space.x - 10, y: space.y)
            engine.touchMoved(id: 1, to: start)
            XCTAssertTrue(engine.isTrackpadActive)
            XCTAssertEqual(target.cursorIndex, 18)

            engine.touchMoved(id: 1, to: CGPoint(x: start.x - 3 * step - 1, y: start.y))
            XCTAssertEqual(target.cursorIndex, 15, "three steps left")
            engine.touchMoved(id: 1, to: CGPoint(x: start.x - 3 * step - 1, y: start.y - 120))
            XCTAssertEqual(target.cursorIndex, 15, "never up a line")
            engine.touchMoved(id: 1, to: CGPoint(x: start.x - 2 * step, y: start.y))
            XCTAssertEqual(target.cursorIndex, 16, "back one")
            engine.touchEnded(id: 1, at: CGPoint(x: start.x - 2 * step, y: start.y))
            XCTAssertFalse(engine.isTrackpadActive)
            XCTAssertEqual(target.text, "one two\nthree four", "no space typed")
            XCTAssertEqual(target.cursorIndex, 16, "lifting keeps the cursor")
            XCTAssertEqual(ticks, 3, "a tick as it starts and per step: start, 3 left as one step, 1 right")
        }
    }

    func testCursorSlidingHeldStillTypesASpace() throws {
        let (engine, target) = makeEngine(text: "hello")
        engine.slidesCursorByCharacter = true
        let space = try point(.space, in: engine)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        engine.touchMoved(id: 1, to: CGPoint(x: space.x - 4, y: space.y))
        engine.touchEnded(id: 1, at: CGPoint(x: space.x - 4, y: space.y))
        XCTAssertEqual(target.text, "hello ")
    }

    func testHexDeleteSlideTakesOverFromRepeatWhenDeleteSlidingIsOff() throws {
        let (engine, target) = makeEngine(text: "one two, three")
        let plane = KeyboardKeyPlaneView(engine: engine)
        defer { plane.cancelAllTouches() }
        let delete = try point(.delete, in: engine)
        plane.began(id: 1, sample: sample(delete))
        plane.moved(id: 1, sample: sample(CGPoint(x: delete.x - 1.2 * engine.layout.letterWidth, y: delete.y)))
        XCTAssertEqual(target.text, "one two, ")
        XCTAssertEqual(plane.deleteSwipe?.isActive, true)
    }

    func testDeleteSlidingKeepsRepeatingWhenTheFingerDrifts() async throws {
        for split in [false, true] {
            let (engine, target) = makeEngine(text: "one two, three", split: split)
            let plane = KeyboardKeyPlaneView(engine: engine)
            plane.slidesDeleteByWord = false
            let delete = try point(.delete, in: engine)
            plane.began(id: 1, sample: sample(delete))
            plane.moved(id: 1, sample: sample(CGPoint(x: delete.x - 2.2 * engine.layout.letterWidth, y: delete.y)))
            XCTAssertEqual(target.text, "one two, thre", "drifting deletes no word")
            XCTAssertEqual(plane.deleteSwipe?.isActive, false)

            let repeated = expectation(description: "the drifted hold reaches a repeat tick")
            plane.onKeyDown = { [weak plane] _ in
                plane?.onKeyDown = nil
                repeated.fulfill()
            }
            await fulfillment(of: [repeated], timeout: 3)
            plane.cancelAllTouches()
            XCTAssertTrue(target.text.hasPrefix("one two, th"), target.text)
            XCTAssertLessThan(target.text.count, "one two, thre".count, "a letter repeat")
        }
    }

    /// S3 with Typr delete sliding on too: Slide delete to remove words wins, so a hold never
    /// repeats and a slide still deletes and restores words, split included.
    func testSlideDeleteWinsOverDeleteSlidingInEveryLayout() throws {
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .deleteSlide] = true
        settings[experiment: .typrDeleteSliding] = true
        let view = makeView(landscape: false)
        view.syncTyprVariants(settings)

        for split in [false, true] {
            let (engine, target) = makeEngine(text: "one two, three", split: split)
            let plane = KeyboardKeyPlaneView(engine: engine)
            plane.repeatsHeldDelete = view.plane.repeatsHeldDelete
            plane.slidesDeleteByWord = view.plane.slidesDeleteByWord
            defer { plane.cancelAllTouches() }
            let delete = try point(.delete, in: engine)
            plane.began(id: 1, sample: sample(delete))
            XCTAssertEqual(target.text, "one two, thre")
            let left = CGPoint(x: delete.x - 2.2 * engine.layout.letterWidth, y: delete.y)
            plane.moved(id: 1, sample: sample(left))
            XCTAssertEqual(target.text, "one ")
            plane.moved(id: 1, sample: sample(delete))
            XCTAssertEqual(target.text, "one two, thre")
            plane.ended(id: 1, sample: sample(delete))
            XCTAssertNil(plane.deleteSwipe)
        }
    }
}
