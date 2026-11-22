import UIKit
import XCTest
@testable import Typr

/// The Apple-style space-bar trackpad (Hex #2219, #2192), laid out with every character 10 pt
/// wide and 20 pt lines.
@MainActor
final class TrackpadCursorTests: XCTestCase {
    private let width: (Character) -> CGFloat = { _ in 10 }

    /// Apple's drags a point through the text at the text's own scale: a line per line height
    /// (the first after half of one, from the middle of the cursor's line), keeping its x across
    /// a short line, stopping at a line's start, where coming back moves the cursor at once, and
    /// past its end, where coming back takes the travel again.
    func testTheTrackpadMovesThroughLinesAtTheTextsOwnScale() {
        var state = TyprTrackpadCursor.State(before: "ein zwei drei\nvier fünf\nsechs elf", after: " acht neun",
                                         wrapWidth: 300, lineHeight: 20, width: width)
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -9), at: 0), 0, "not yet: half a line from the middle")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -2), at: 0), 23 - 33, "up a line, at its end: \"vier fünf\" is shorter")
        XCTAssertEqual(state.move(by: CGVector(dx: -45, dy: 0), at: 0), -5, "along by the text's width: 4.5 characters, the nearer 5")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), -4, "and stops at the line's start")
        XCTAssertEqual(state.move(by: CGVector(dx: 10, dy: 0), at: 0), 1, "coming back moves it at once")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -20), at: 0), 1 - 15, "up a line, at its x")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: 40), at: 0), 25 - 1, "down two lines, at its x")
        XCTAssertEqual(state.move(by: CGVector(dx: 200, dy: -20), at: 0), 23 - 25, "up to \"vier fünf\", stopped at its end")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), 0, "coming back takes that travel again")
        XCTAssertEqual(state.move(by: CGVector(dx: -30, dy: 0), at: 0), -1)
    }

    /// A host shares only the cursor's sentence or line, so past the first or last line the
    /// cursor steps just past what it showed, a move the host makes only if there's text there.
    /// Shown it, the cursor goes on to that line at its x; no answer means that line was the first.
    func testTheTrackpadStepsPastTheTextItKnowsForTheHostToShowMore() {
        var state = TyprTrackpadCursor.State(before: "Zei", after: "le zwei ist länger", wrapWidth: 300, lineHeight: 20, width: width)
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -25), at: 0), -4, "just past the start: the end of the line before")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -2), at: 0.01), 0, "waiting for the host")
        XCTAssertTrue(state.catchUp(before: "Zeile eins", after: "", width: width))
        XCTAssertEqual(state.settle(at: 0.02), 3 - 10, "the line shown, at the x it was at")

        var first = TyprTrackpadCursor.State(before: "Zei", after: "le eins", wrapWidth: 300, lineHeight: 20, width: width)
        XCTAssertEqual(first.move(by: CGVector(dx: 0, dy: -25), at: 0), -4)
        XCTAssertEqual(first.settle(at: 0.5), 0, "unanswered: the host never moved, so neither did the cursor")
        XCTAssertEqual(first.move(by: CGVector(dx: 0, dy: -40), at: 0.6), 0, "the first line keeps it")
        XCTAssertEqual(first.move(by: CGVector(dx: 10, dy: 0), at: 0.7), 1, "and coming back moves it at once")
    }

    /// Apple's took 80 pt of finger 1.05 times as far slowly, 1.4 times at 400 pt/s, twice at
    /// 1,000 and 2.6 times at 2,000 (iOS 27.2), from the finger's speed in whatever direction.
    func testTheTrackpadGoesFurtherTheFasterTheFinger() {
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 0), 1)
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 400), 1.375, accuracy: 0.01)
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 1000), 2, accuracy: 0.01)
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 2000), 2.59, accuracy: 0.01)
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 4000), 3.78, accuracy: 0.01)
        XCTAssertEqual(TyprTrackpadCursor.maxGain, 4)
        XCTAssertEqual(TyprTrackpadCursor.gain(speed: 100_000), TyprTrackpadCursor.maxGain)
        // Moves 7.7 pt apart at a steady 120 Hz, their times arriving 1 to 11 ms apart.
        let times: [TimeInterval] = [0, 0.0001, 0.0089, 0.0149, 0.0254, 0.0322, 0.0381, 0.0488, 0.0554]
        let path = times.enumerated().map { TyprTrackpadCursor.Sample(time: $1, point: CGPoint(x: CGFloat($0) * 7.7, y: 0)) }
        XCTAssertEqual(TyprTrackpadCursor.speed(along: path), 924, accuracy: 120)
        XCTAssertTrue(TyprTrackpadCursor.isVertical([.init(time: 0, point: .zero), .init(time: 0.01, point: CGPoint(x: 3, y: -5))]))
    }

    /// The proxy moves the cursor in UTF-16 units: a 👍🏽 is four of them.
    func testTheTrackpadMovesOverAnEmojiInOneStep() {
        var state = TyprTrackpadCursor.State(before: "ab👍🏽cd", after: "", wrapWidth: 300, lineHeight: 20,
                                         width: { $0 == "👍🏽" ? 20 : 10 })
        XCTAssertEqual(state.move(by: CGVector(dx: -25, dy: 0), at: 0), -2, "back over d and c")
        XCTAssertEqual(state.move(by: CGVector(dx: -10, dy: 0), at: 0), -4, "and the emoji at once")
    }

    /// A line the field wraps: along goes on into the next row, up and down go by rows.
    func testTheTrackpadFollowsRowsTheFieldWraps() {
        let long = String(repeating: "Wort ", count: 12)
        var state = TyprTrackpadCursor.State(before: long, after: "", wrapWidth: 100, lineHeight: 20, width: width)
        XCTAssertEqual(state.layout.rows.count, 6, "two words a row, the space after each hanging past the edge")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -20), at: 0), -10, "up a row")
        XCTAssertEqual(state.move(by: CGVector(dx: -10, dy: 0), at: 0), -1, "along it")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), -10, "and on into the row before")
    }
}
