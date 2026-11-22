import UIKit
import XCTest
@testable import Typr

@MainActor
final class FullKeyboardEngineTests: XCTestCase {
    private var target: HexFixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 100
    private var suiteName: String!
    private var defaults: UserDefaults!
    /// The layouts are Apple's iOS 27 keyboard; CI's newest simulator runtime is iOS 26.5, so the
    /// version these tests describe is pinned (the before-27 Ukrainian test sets 26 itself).
    private var runningSystemMajorVersion = 0

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "FullKeyboardEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let ac = AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults))
        engine = FullKeyboardEngine(target: target, autocorrect: ac)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func point(_ kind: KeyKind) -> CGPoint {
        let key = engine.layout.key(kind)!
        return CGPoint(x: key.frame.midX, y: key.frame.midY)
    }

    private func down(_ id: Int, _ kind: KeyKind) { engine.touchBegan(id: id, at: point(kind)) }
    private func up(_ id: Int, _ kind: KeyKind) { engine.touchEnded(id: id, at: point(kind)) }

    private func tap(_ kind: KeyKind) {
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

    /// Space in a rollover keeps its place: a letter held as space goes down goes in first, and
    /// space goes in when the next letter goes down, even if that letter lifts first. It used
    /// to wait for its own lift, so "a b" typed fast came out "ab ".
    func testRolloverWithTheSpaceBarKeepsOrder() {
        down(1, .character("a"))
        down(2, .space)
        up(1, .character("a"))
        down(3, .character("b"))
        up(3, .character("b"))
        up(2, .space)
        XCTAssertEqual(target.text, "a b")

        down(4, .space)
        down(5, .character("c"))
        engine.holdSpace(forTouch: 4)
        XCTAssertFalse(engine.isTrackpadActive, "a space already typed doesn't become the trackpad")
        up(4, .space)
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

    /// Settings › Experiments › Dvorak punctuation keys: on English's Dvorak letters the three
    /// keys type `<`, `>` and `:` while shift is on, their keycaps and pop-ups read so, one-shot
    /// shift turns off after one as it does for a letter, and caps lock keeps them shifted.
    func testDvorakPunctuationTypesShiftedSymbols() throws {
        engine.width = 402
        engine.letterLayout = .dvorak
        XCTAssertNil(engine.layout.key(.character(",")), "off: Apple's seven-letter row 1")
        engine.dvorakPunctuation = true
        XCTAssertEqual(engine.layout.letters, .dvorak)
        let comma = try XCTUnwrap(engine.layout.key(.character(",")))
        let period = try XCTUnwrap(engine.layout.key(.character(".")))
        let semicolon = try XCTUnwrap(engine.layout.key(.character(";")))
        XCTAssertEqual(comma.shifted, "<")
        XCTAssertEqual(period.shifted, ">")
        XCTAssertEqual(semicolon.shifted, ":")
        XCTAssertEqual(comma.row, 0)
        XCTAssertEqual(period.row, 0)
        XCTAssertEqual(semicolon.row, 3)
        XCTAssertEqual(engine.keycapLabel(for: comma), ",")
        XCTAssertEqual(engine.displayLabel(for: comma), ",")
        XCTAssertEqual(engine.keycapLabel(for: semicolon), ";")
        tap(.shift)
        XCTAssertEqual(engine.keycapLabel(for: comma), "<")
        XCTAssertEqual(engine.displayLabel(for: comma), "<")
        XCTAssertEqual(engine.keycapLabel(for: period), ">")
        XCTAssertEqual(engine.displayLabel(for: period), ">")
        XCTAssertEqual(engine.keycapLabel(for: semicolon), ":")
        XCTAssertEqual(engine.displayLabel(for: semicolon), ":")
        tap(.character(","))
        XCTAssertEqual(target.text, "<")
        XCTAssertEqual(engine.shift.state, .off, "one-shot, as after a letter")
        XCTAssertEqual(engine.keycapLabel(for: comma), ",")
        tap(.character("."))
        tap(.character(";"))
        XCTAssertEqual(target.text, "<.;")
        tap(.shift)
        now += 0.1
        tap(.shift)
        XCTAssertEqual(engine.shift.state, .locked)
        tap(.character(","))
        tap(.character("."))
        tap(.character(";"))
        XCTAssertEqual(target.text, "<.;<>:")
        XCTAssertEqual(engine.shift.state, .locked, "caps lock stays on")
        XCTAssertEqual(engine.keycapLabel(for: semicolon), ":")
        // The narrower row 1 is its own key plane for Adaptive touch: what it learns stays there.
        let punctuation = try XCTUnwrap(AdaptiveTouchGeometry(layout: engine.layout)).key
        engine.dvorakPunctuation = false
        XCTAssertNotEqual(try XCTUnwrap(AdaptiveTouchGeometry(layout: engine.layout)).key, punctuation)
    }

    /// Settings › Experiments › Dvorak punctuation keys: a URL or email field already has its own
    /// `.` key on the bottom row, so its Dvorak row 1 stays Apple's rather than have two keys
    /// that type the same character, while the semicolon still joins the space bar.
    func testDvorakPunctuationKeepsFieldsOwnPeriodKey() throws {
        engine.width = 402
        engine.letterLayout = .dvorak
        engine.dvorakPunctuation = true
        for keyboardType in [UIKeyboardType.URL, .emailAddress] {
            target.keyboardType = keyboardType
            engine.configureForField()
            XCTAssertNotEqual(engine.layout.field, .text, "\(keyboardType.rawValue)")
            XCTAssertEqual(engine.layout.keys.filter { $0.kind == .character(".") }.count, 1, "the field's own . only")
            XCTAssertNil(engine.layout.key(.character(",")), "row 1 stays Apple's")
            XCTAssertEqual(engine.layout.key(.character("."))?.row, 3)
            XCTAssertEqual(engine.layout.key(.character(";"))?.shifted, ":")
            XCTAssertEqual(engine.layout.key(.character(";"))?.row, 3)
        }
    }

    /// Settings › Experiments › Dvorak punctuation keys: auto-capitalization's shift types no
    /// symbols — a comma at a sentence's start stays a comma, and its keycap reads so — while a
    /// shift you press, or caps lock, types `<`, and the semicolon `:`.
    func testDvorakPunctuationFollowsAUserShiftNotAutoCapitalization() throws {
        engine.width = 402
        engine.letterLayout = .dvorak
        engine.dvorakPunctuation = true
        target.autocapitalizationType = .sentences
        engine.configureForField()
        let comma = try XCTUnwrap(engine.layout.key(.character(",")))
        XCTAssertEqual(engine.shift.state, .on, "the field's first sentence")
        XCTAssertFalse(engine.shift.isUserShift)
        XCTAssertEqual(engine.keycapLabel(for: comma), ",")
        XCTAssertEqual(engine.displayLabel(for: comma), ",")
        tap(.character(","))
        XCTAssertEqual(target.text, ",")
        XCTAssertEqual(engine.shift.state, .off)

        type("ok. ")
        XCTAssertEqual(target.text, ",ok. ")
        XCTAssertEqual(engine.shift.state, .on, "after a sentence")
        XCTAssertFalse(engine.shift.isUserShift)
        tap(.character(","))
        XCTAssertEqual(target.text, ",ok. ,")

        tap(.shift)
        XCTAssertTrue(engine.shift.isUserShift)
        XCTAssertEqual(engine.keycapLabel(for: comma), "<")
        tap(.character(","))
        XCTAssertEqual(target.text, ",ok. ,<")
        XCTAssertEqual(engine.shift.state, .off, "one-shot")

        tap(.shift)
        now += 0.1
        tap(.shift)
        XCTAssertEqual(engine.shift.state, .locked)
        XCTAssertTrue(engine.shift.isUserShift)
        XCTAssertEqual(engine.keycapLabel(for: comma), "<")
        tap(.character(";"))
        XCTAssertEqual(target.text, ",ok. ,<:")
    }

    func testHoldNumbersSlideToADigitAndLetGo() {
        down(1, .layerSwitch(.numbers))
        XCTAssertEqual(engine.layout.layer, .numbers)
        engine.touchMoved(id: 1, to: point(.character("7")))
        engine.touchEnded(id: 1, at: point(.character("7")))
        XCTAssertEqual(target.text, "7")
        XCTAssertEqual(engine.layout.layer, .letters)
    }

    /// As on Apple's keyboard, the key under the finger shows its pop-up the whole slide.
    func testHoldNumbersPreviewsTheKeyUnderTheFinger() {
        down(1, .layerSwitch(.numbers))
        XCTAssertNil(engine.previewKey, "123 itself has no pop-up")
        engine.touchMoved(id: 1, to: point(.character("5")))
        XCTAssertEqual(engine.previewKey?.kind, .character("5"))
        XCTAssertTrue(engine.pressedKinds.contains(.character("5")), "with Key pop-ups off it darkens")
        engine.touchMoved(id: 1, to: point(.character("6")))
        XCTAssertEqual(engine.previewKey?.kind, .character("6"))
        engine.touchMoved(id: 1, to: point(.space))
        XCTAssertNil(engine.previewKey, "no pop-up over a key that isn't a character")
        engine.touchMoved(id: 1, to: CGPoint(x: point(.character("6")).x, y: engine.layout.touchAreaFrame.minY - 40))
        XCTAssertNil(engine.previewKey, "none off the keys")
        engine.touchMoved(id: 1, to: point(.character("(")))
        XCTAssertEqual(engine.previewKey?.kind, .character("("))
        engine.touchEnded(id: 1, at: point(.character("(")))
        XCTAssertNil(engine.previewKey)
        XCTAssertEqual(target.text, "(")
        XCTAssertEqual(engine.layout.layer, .letters)
    }

    func testLiftingBackOnTheNumbersKeyOrOffTheKeysTypesNothing() {
        down(1, .layerSwitch(.numbers))
        engine.touchMoved(id: 1, to: point(.character("5")))
        let abc = point(.layerSwitch(.letters))
        engine.touchMoved(id: 1, to: abc)
        XCTAssertNil(engine.previewKey)
        engine.touchEnded(id: 1, at: abc)
        XCTAssertEqual(target.text, "")
        XCTAssertEqual(engine.layout.layer, .letters, "a slide taken back goes back to the letters")

        down(2, .layerSwitch(.numbers))
        engine.touchMoved(id: 2, to: point(.character("5")))
        let above = CGPoint(x: point(.character("5")).x, y: engine.layout.touchAreaFrame.minY - 40)
        engine.touchMoved(id: 2, to: above)
        engine.touchEnded(id: 2, at: above)
        XCTAssertEqual(target.text, "")
        XCTAssertEqual(engine.layout.layer, .numbers, "off the keys the numbers stay, as on Apple's keyboard")

        tap(.layerSwitch(.letters))
        tap(.layerSwitch(.numbers))
        XCTAssertEqual(engine.layout.layer, .numbers, "a tap of 123 still stays on the numbers")
        XCTAssertEqual(target.text, "")
    }

    func testHoldSymbolsSlideToASymbolAndLetGo() {
        tap(.layerSwitch(.numbers))
        down(1, .layerSwitch(.symbols))
        XCTAssertEqual(engine.layout.layer, .symbols)
        engine.touchMoved(id: 1, to: point(.character("%")))
        XCTAssertEqual(engine.previewKey?.kind, .character("%"))
        engine.touchEnded(id: 1, at: point(.character("%")))
        XCTAssertEqual(target.text, "%")
        XCTAssertEqual(engine.layout.layer, .numbers, "back to the page it came from")
    }

    func testHoldShiftSlideToALetterTypesACapital() {
        down(1, .shift)
        engine.touchMoved(id: 1, to: point(.character("h")))
        XCTAssertEqual(engine.previewKey?.kind, .character("h"))
        XCTAssertEqual(engine.previewKey.map(engine.displayLabel(for:)), "H")
        engine.touchEnded(id: 1, at: point(.character("h")))
        XCTAssertEqual(target.text, "H")
        XCTAssertEqual(engine.shift.state, .off)
        tap(.character("i"))
        XCTAssertEqual(target.text, "Hi")

        // Slid off and back onto shift: a tap of shift, nothing typed.
        down(2, .shift)
        engine.touchMoved(id: 2, to: point(.character("z")))
        engine.touchMoved(id: 2, to: point(.shift))
        XCTAssertNil(engine.previewKey)
        engine.touchEnded(id: 2, at: point(.shift))
        XCTAssertEqual(target.text, "Hi")
        XCTAssertEqual(engine.shift.state, .on)
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

    func testSlowDoubleSpaceStaysTwoSpaces() {
        type("ok")
        tap(.space)
        now += 0.5
        tap(.space)
        XCTAssertEqual(target.text, "ok  ")
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

    /// Settings › Keyboard › Auto-capitalization off, as Apple's switch: shift never turns
    /// itself on, whatever the field asks, not even after the double-space period; shift and
    /// caps lock still work.
    func testAutoCapitalizationOffNeverTurnsShiftOn() {
        engine.autoCapitalizes = false
        for type in [UITextAutocapitalizationType.sentences, .words, .allCharacters] {
            target.autocapitalizationType = type
            engine.configureForField()
            XCTAssertEqual(engine.shift.state, .off, "autocapitalizationType \(type.rawValue)")
        }
        target.autocapitalizationType = .sentences
        engine.configureForField()
        type("hi")
        tap(.space)
        now += 0.2
        tap(.space)
        XCTAssertEqual(engine.shift.state, .off, "after the double-space period")
        type("there ok")
        tap(.shift)
        type("x")
        tap(.shift)
        tap(.shift)
        type("yz")
        XCTAssertEqual(target.text, "hi. there okXYZ", "shift, then caps lock")

        tap(.shift)
        tap(.space)
        now += 0.2
        tap(.space)
        XCTAssertEqual(target.text, "hi. there okXYZ. ")
        XCTAssertEqual(engine.shift.state, .off)
        engine.autoCapitalizes = true
        XCTAssertEqual(engine.shift.state, .on, "switched back on, the next sentence starts with a capital")
    }

    func testLongPressAccentPickerSelectsAndUppercaseWorks() {
        tap(.shift)
        down(1, .character("e"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        let menu = try! XCTUnwrap(engine.activeAccentMenu)
        XCTAssertNil(engine.previewKey, "single-key balloon hides while accent picker is open")
        // Apple's order, capitals while shift is on, opening on the key's own letter.
        XCTAssertEqual(menu.options, ["Ë", "É", "E", "È", "Ê", "Ě", "Ẽ", "Ē", "Ė", "Ę"])
        XCTAssertEqual(menu.selectedOption, "E")
        let cell = menu.cellFrames[menu.options.firstIndex(of: "É")!]
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
        let enterPoint = CGPoint(x: spaceStart.x - 12, y: spaceStart.y)
        engine.touchMoved(id: 1, to: enterPoint)
        XCTAssertFalse(engine.isTrackpadActive, "a slide alone doesn't start it")
        // Held, then dragged left by 16 pt (-2 chars: before "lo").
        engine.holdSpace(forTouch: 1)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchMoved(id: 1, to: CGPoint(x: enterPoint.x - 16, y: spaceStart.y))
        engine.touchEnded(id: 1, at: CGPoint(x: enterPoint.x - 16, y: spaceStart.y))
        XCTAssertFalse(engine.isTrackpadActive)
        XCTAssertEqual(target.cursorIndex, 2)
        tap(.character("l"))
        XCTAssertEqual(target.text, "hello")
    }

    /// X (Brandon): "holding down on the space bar only allows scrubbing horizontally, whereas
    /// Apple's keyboard treats it like a cursor on both x/y axes". Apple's (black box, iOS 27.2)
    /// drags a point through the text at the text's own scale: a line per line height (the
    /// first after half of one, from the middle of the cursor's line), keeping its x across a
    /// short line, and stopping at a line's start, where coming back moves the cursor at once,
    /// and past its end, where coming back takes the travel again. Laid out here with every
    /// character 10 pt wide and 20 pt lines.
    func testTheTrackpadMovesThroughLinesAtTheTextsOwnScale() {
        var state = TrackpadCursor.State(before: "one two three\nfour five\nsix seven", after: " eight nine", wrapWidth: 300, lineHeight: 20, width: { _ in 10 })
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -9), at: 0), 0, "not yet: half a line from the middle")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -2), at: 0), 23 - 33, "up a line, at its end: \"four five\" is shorter")
        XCTAssertEqual(state.move(by: CGVector(dx: -45, dy: 0), at: 0), -5, "along by the text's width: 4.5 characters, the nearer 5")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), -4, "and stops at the line's start")
        XCTAssertEqual(state.move(by: CGVector(dx: 10, dy: 0), at: 0), 1, "coming back moves it at once")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -20), at: 0), 1 - 15, "up a line, at its x")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: 40), at: 0), 25 - 1, "down two lines, at its x")
        XCTAssertEqual(state.move(by: CGVector(dx: 200, dy: -20), at: 0), 23 - 25, "up to \"four five\", stopped at its end")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), 0, "coming back takes that travel again")
        XCTAssertEqual(state.move(by: CGVector(dx: -30, dy: 0), at: 0), -1)
    }

    /// Past the first or last line the host may have more: a host shares only the cursor's
    /// sentence or line, so the cursor steps just past what it showed, in one move the host makes
    /// only if there's text there. Shown it, the cursor goes on to the line there at its x; no
    /// answer means the host never moved, and that line was the text's first.
    func testTheTrackpadStepsPastTheTextItKnowsForTheHostToShowMore() {
        var state = TrackpadCursor.State(before: "Lin", after: "e two is longer", wrapWidth: 300, lineHeight: 20, width: { _ in 10 })
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -25), at: 0), -4, "just past the start: the end of the line before")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -2), at: 0.01), 0, "waiting for the host")
        XCTAssertTrue(state.catchUp(before: "Line one", after: "", width: { _ in 10 }))
        XCTAssertEqual(state.settle(at: 0.02), 3 - 8, "the line shown, at the x it was at")

        var first = TrackpadCursor.State(before: "Lin", after: "e one", wrapWidth: 300, lineHeight: 20, width: { _ in 10 })
        XCTAssertEqual(first.move(by: CGVector(dx: 0, dy: -25), at: 0), -4)
        XCTAssertEqual(first.settle(at: 0.5), 0, "unanswered: the host never moved, so neither did the cursor")
        XCTAssertEqual(first.move(by: CGVector(dx: 0, dy: -40), at: 0.6), 0, "the first line keeps it")
        XCTAssertEqual(first.move(by: CGVector(dx: 10, dy: 0), at: 0.7), 1, "and coming back moves it at once")
    }

    /// Apple's took 80 pt of finger 1.05 times as far slowly, 1.4 times at 400 pt/s, twice at
    /// 1,000 and 2.6 times at 2,000 (iOS 27.2), from the finger's speed in whatever direction.
    func testTheTrackpadGoesFurtherTheFasterTheFinger() {
        XCTAssertEqual(TrackpadCursor.gain(speed: 0), 1)
        XCTAssertEqual(TrackpadCursor.gain(speed: 400), 1.375, accuracy: 0.01)
        XCTAssertEqual(TrackpadCursor.gain(speed: 1000), 2, accuracy: 0.01)
        XCTAssertEqual(TrackpadCursor.gain(speed: 2000), 2.59, accuracy: 0.01)
        XCTAssertEqual(TrackpadCursor.gain(speed: 100_000), TrackpadCursor.maxGain)
        // Moves 7.7 pt apart at a steady 120 Hz, their times arriving 1 to 11 ms apart.
        let times: [TimeInterval] = [0, 0.0001, 0.0089, 0.0149, 0.0254, 0.0322, 0.0381, 0.0488, 0.0554]
        let path = times.enumerated().map { TrackpadCursor.Sample(time: $1, point: CGPoint(x: CGFloat($0) * 7.7, y: 0)) }
        XCTAssertEqual(TrackpadCursor.speed(along: path), 924, accuracy: 120)
        XCTAssertTrue(TrackpadCursor.isVertical([.init(time: 0, point: .zero), .init(time: 0.01, point: CGPoint(x: 3, y: -5))]))
    }

    /// The proxy moves the cursor in UTF-16 units: a 👍🏽 is four of them, so moving by
    /// characters stalled three steps inside one. Each character's own width counts too.
    func testTheTrackpadMovesOverAnEmojiInOneStep() {
        var state = TrackpadCursor.State(before: "ab👍🏽cd", after: "", wrapWidth: 300, lineHeight: 20, width: { $0 == "👍🏽" ? 20 : 10 })
        XCTAssertEqual(state.move(by: CGVector(dx: -25, dy: 0), at: 0), -2, "back over d and c")
        XCTAssertEqual(state.move(by: CGVector(dx: -10, dy: 0), at: 0), -4, "and the emoji at once")
    }

    /// A line the field wraps: along goes on into the next row (the rows are estimates, and a
    /// single-line field never wraps), and up and down go by rows.
    func testTheTrackpadFollowsRowsTheFieldWraps() {
        let long = String(repeating: "word ", count: 12)
        var state = TrackpadCursor.State(before: long, after: "", wrapWidth: 100, lineHeight: 20, width: { _ in 10 })
        XCTAssertEqual(state.layout.rows.count, 6, "two words a row, the space after each hanging past the edge")
        XCTAssertEqual(state.move(by: CGVector(dx: 0, dy: -20), at: 0), -10, "up a row")
        XCTAssertEqual(state.move(by: CGVector(dx: -10, dy: 0), at: 0), -1, "along it")
        XCTAssertEqual(state.move(by: CGVector(dx: -100, dy: 0), at: 0), -10, "and on into the row before")
    }

    /// Apple's second finger starts a selection while the space bar is the trackpad, which a
    /// keyboard can't make; Hex's typed the blank key under it. Nor does the trackpad tick: Apple's
    /// keyboard asks for no feedback after the space bar's own (iOS 27.2's log).
    func testASecondFingerOnTheTrackpadTypesNothingAndItNeverTicks() {
        type("hello world")
        var ticks = 0
        engine.onSelectionStep = { ticks += 1 }
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        engine.touchMoved(id: 1, to: CGPoint(x: space.x - 30, y: space.y))
        down(2, .character("k"))
        up(2, .character("k"))
        engine.touchMoved(id: 1, to: CGPoint(x: space.x - 60, y: space.y))
        engine.touchEnded(id: 1, at: CGPoint(x: space.x - 60, y: space.y))
        XCTAssertEqual(target.text, "hello world")
        XCTAssertLessThan(target.cursorIndex, 11)
        XCTAssertEqual(ticks, 0)
    }

    /// With two or more languages a quick swipe along the space bar switches language (to the
    /// left the next, to the right the one before) and types nothing; a slip shorter than a
    /// swipe is still a space; a hold, then a slide, moves the cursor. With one language a
    /// quick slide is a space too, as on Apple's (TestFlight build 56: "missing the space
    /// key", where a tap that drifted 10 pt started the trackpad and typed nothing).
    func testASpaceBarSwipeSwitchesLanguageAndAHoldThenSlideMovesTheCursor() {
        var steps: [Int] = []
        engine.onLanguageSwipe = { steps.append($0) }
        engine.switchesLanguage = true
        type("hi")
        let start = point(.space)
        func slide(_ id: Int, by dx: CGFloat) {
            engine.touchBegan(id: id, at: start)
            now += 0.05
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx / 2, y: start.y))
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx, y: start.y))
            engine.touchEnded(id: id, at: CGPoint(x: start.x + dx, y: start.y))
            now += 0.5
        }

        slide(1, by: -40)
        XCTAssertEqual(steps, [1])
        slide(2, by: 32)
        XCTAssertEqual(steps, [1, -1])
        XCTAssertEqual(target.text, "hi", "a swipe types nothing")

        slide(3, by: 20)
        XCTAssertEqual(target.text, "hi ", "a short slip is a space")
        XCTAssertEqual(steps, [1, -1])

        // Held (the plane view's `trackpadHoldDelay` timer), then slid: the cursor moves.
        engine.touchBegan(id: 4, at: start)
        engine.holdSpace(forTouch: 4)
        XCTAssertTrue(engine.isTrackpadActive, "held first: the cursor slides")
        // Back over " i" and a little more, at the text's own scale.
        let back = FullKeyboardEngine.trackpadWidth(" ") + FullKeyboardEngine.trackpadWidth("i") + 1
        engine.touchMoved(id: 4, to: CGPoint(x: start.x - back, y: start.y))
        engine.touchEnded(id: 4, at: CGPoint(x: start.x - back, y: start.y))
        XCTAssertEqual(steps, [1, -1])
        XCTAssertEqual(target.cursorIndex, 1)

        // A slow swipe still switches: the hold timer firing mid-swipe leaves it a swipe.
        engine.touchBegan(id: 6, at: start)
        engine.touchMoved(id: 6, to: CGPoint(x: start.x - 15, y: start.y))
        engine.holdSpace(forTouch: 6)
        XCTAssertFalse(engine.isTrackpadActive)
        engine.touchEnded(id: 6, at: CGPoint(x: start.x - 40, y: start.y))
        XCTAssertEqual(steps, [1, -1, 1])

        engine.switchesLanguage = false
        let spaces = target.text.filter { $0 == " " }.count
        for (id, dx) in [(5, CGFloat(12)), (7, -24), (8, 40)] {
            engine.touchBegan(id: id, at: start)
            now += 0.05
            engine.touchMoved(id: id, to: CGPoint(x: start.x + dx, y: start.y))
            XCTAssertFalse(engine.isTrackpadActive, "one language: a quick slide is still a tap")
            engine.touchEnded(id: id, at: CGPoint(x: start.x + dx, y: start.y))
            now += 1
        }
        XCTAssertEqual(target.text.filter { $0 == " " }.count, spaces + 3, "each typed a space")
        XCTAssertEqual(steps, [1, -1, 1])
    }

    /// The TestFlight request (build 56): English on QWERTZ. The keys, Spatial autocorrect's
    /// centres, a held key's accents and the touch decoder all read the QWERTZ keys.
    func testEnglishOnQWERTZTypesOnItsOwnKeys() throws {
        engine.width = 402
        engine.letterLayout = .qwertz
        let z = try XCTUnwrap(engine.layout.key(.character("z")))
        let y = try XCTUnwrap(engine.layout.key(.character("y")))
        XCTAssertEqual(z.row, 0)
        XCTAssertEqual(y.row, 2)
        type("zany yak ")
        XCTAssertEqual(target.text, "zany yak ")
        let keys = try XCTUnwrap(engine.autocorrect.decoderKeys)
        XCTAssertEqual(keys.centres["z"], CGPoint(x: z.frame.midX, y: z.frame.midY))
        XCTAssertEqual(keys.centres["y"], CGPoint(x: y.frame.midX, y: y.frame.midY))
        XCTAssertEqual(engine.swipeKeys, keys, "swipes read the same keys")
        XCTAssertEqual(engine.autocorrect.layoutLetters, .qwertz)

        engine.touchBegan(id: 7, at: CGPoint(x: y.frame.midX, y: y.frame.midY))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 7))
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, "y", "the key's own, where Apple's callout puts it")
        XCTAssertEqual(Set(engine.activeAccentMenu?.options ?? []), ["y", "ý", "ŷ", "ÿ"], "English's holds")
        engine.touchCancelled(id: 7)

        engine.letterLayout = nil
        XCTAssertEqual(engine.layout.letters, .qwerty, "nil: English's own")
        XCTAssertEqual(engine.layout.key(.character("z"))?.row, 2)
    }

    /// Spatial autocorrect's language model was trained on QWERTY text, but its touch part
    /// scores taps against the keys as drawn: a sloppy word on QWERTZ is read as QWERTZ.
    func testSpatialAutocorrectReadsTapsOnTheQWERTZKeys() throws {
        engine.width = 402
        let model = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        engine.letterOdds = model
        engine.autocorrect.decoder = TypingDecoder(model: model)
        engine.letterLayout = .qwertz
        // "yes" and "zoo" with each tap a third of a key off-centre, towards the next key right.
        for word in ["yes", "zoo"] {
            for letter in word {
                let key = try XCTUnwrap(engine.layout.key(.character(String(letter))))
                tapAt(CGPoint(x: key.frame.midX + key.frame.width / 3, y: key.frame.midY))
            }
            tapAt(point(.space))
        }
        XCTAssertEqual(target.text, "yes zoo ")
    }

    func testEnablesReturnKeyAutomaticallyBlocksEmptyField() {
        target.enablesReturnKeyAutomatically = true
        tap(.returnKey)
        XCTAssertEqual(target.text, "")
        type("ok")
        tap(.returnKey)
        XCTAssertEqual(target.text, "ok\n")
    }

    func testTypesOnTheNorwegianLayout() {
        engine.language = .norwegian
        XCTAssertNotNil(engine.layout.key(.character("å")))
        XCTAssertEqual(engine.autocorrect.language, .norwegian)
        tap(.shift)
        tap(.character("ø"))
        tap(.character("l"))
        XCTAssertEqual(target.text, "Øl")

        let o = engine.layout.key(.character("ø"))!
        engine.touchBegan(id: 7, at: CGPoint(x: o.frame.midX, y: o.frame.midY))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 7))
        XCTAssertEqual(Set(engine.activeAccentMenu?.options ?? []), ["ø", "ö"])
        engine.touchCancelled(id: 7)

        engine.language = .german
        XCTAssertNil(engine.layout.key(.character("å")))
        XCTAssertNotNil(engine.layout.key(.character("ü")))
    }

    /// The likelier next letter claims a few points of its neighbour's target, as Apple's
    /// keyboard does: on the e/d border, "th" types e and "an" types d. Past the reach, with
    /// autocorrect off, or on a page without letters, every target stays where it is drawn.
    func testTheLikelyNextLetterClaimsAFewPointsOfItsNeighbour() throws {
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        let e = engine.layout.key(.character("e"))!
        let d = engine.layout.key(.character("d"))!
        let border = e.hitFrame.maxY
        XCTAssertEqual(border, d.hitFrame.minY)
        let x = max(e.frame.minX, d.frame.minX) + 4
        let inD = CGPoint(x: x, y: border + 2)
        let inE = CGPoint(x: x, y: border - 2)
        let pastReach = CGPoint(x: x, y: border + engine.letterReach + 1)

        type("th")
        XCTAssertEqual(engine.key(at: inD)?.kind, .character("e"), "the")
        XCTAssertEqual(engine.key(at: pastReach)?.kind, .character("d"))
        // A finger that rolls a point or two keeps the letter it claimed.
        engine.touchBegan(id: 1, at: inD)
        engine.touchMoved(id: 1, to: CGPoint(x: x, y: border + 3))
        engine.touchEnded(id: 1, at: CGPoint(x: x, y: border + 3))
        XCTAssertEqual(target.text, "the")

        type(" an")
        XCTAssertEqual(engine.key(at: inE)?.kind, .character("d"), "and")
        XCTAssertEqual(engine.key(at: inD)?.kind, .character("d"))

        engine.autocorrect.isEnabled = false
        XCTAssertEqual(engine.key(at: inE)?.kind, .character("e"), "autocorrect off: fixed targets")
        engine.autocorrect.isEnabled = true
        target.autocorrectionType = .no
        XCTAssertEqual(engine.key(at: inE)?.kind, .character("e"), "a field without autocorrect")
    }

    /// A TestFlight tester's sentence (build 25) as tapped on a 402 pt iPhone, from "but": each
    /// letter near the key they hit, drawn from where taps meant for the key they wanted land.
    /// They typed "but i miss here we mire than on the buokt in aoplw kwybaird whichnalso
    /// sixks". Spatial autocorrect with the next-letter odds reads every slip but "we" (way),
    /// a real word two edits away.
    func testTheTestersSentenceComesOutRightWithSpatialAutocorrect() throws {
        engine.width = 402
        let model = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        engine.letterOdds = model
        engine.autocorrect.decoder = TypingDecoder(model: model)
        let taps: [(CGFloat, CGFloat)] = [
            (237.1, 172.9), (267.7, 58.8), (185.2, 75.3), (172.8, 222.0), (301.5, 68.6), (256.1, 230.7),
            (328.1, 175.7), (306.7, 53.4), (84.3, 128.5), (82.1, 119.9), (227.3, 237.6), (243.6, 117.7),
            (97.4, 56.5), (148.7, 51.1), (103.2, 63.1), (150.6, 231.6), (68.5, 77.5), (103.2, 70.6),
            (179.1, 236.2), (323.2, 171.2), (315.6, 60.9), (143.2, 63.5), (94.7, 58.1), (129.1, 227.6),
            (181.7, 61.9), (240.9, 121.0), (41.6, 123.1), (284.4, 173.9), (199.4, 219.6), (334.4, 67.5),
            (271.3, 180.1), (214.8, 237.9), (175.0, 68.1), (251.5, 121.3), (109.3, 68.8), (107.9, 227.9),
            (250.2, 174.8), (254.9, 57.3), (322.1, 67.6), (331.9, 127.7), (175.5, 66.3), (180.5, 240.5),
            (301.3, 62.8), (274.2, 177.8), (191.9, 228.6), (39.5, 120.4), (358.9, 66.9), (372.9, 52.3),
            (360.7, 123.2), (77.0, 59.8), (156.0, 242.4), (319.3, 115.8), (82.3, 60.3), (219.7, 62.6),
            (241.8, 169.2), (45.0, 114.3), (318.2, 73.8), (142.4, 70.3), (122.1, 119.5), (169.6, 233.9),
            (65.8, 58.9), (247.5, 122.4), (294.0, 70.1), (165.6, 185.1), (231.3, 123.3), (297.4, 205.9),
            (44.8, 121.6), (364.4, 124.5), (77.0, 123.4), (332.3, 73.2), (158.3, 236.4), (82.4, 125.4),
            (282.4, 79.9), (137.6, 175.1), (309.7, 126.6), (72.5, 126.2), (108.8, 239.2),
        ]
        // The taps were placed on that build's rows (45 pt keys on a 56 pt pitch from 35 pt
        // down); put each at the same spot on today's row.
        func onTodaysRow(_ y: CGFloat) -> CGFloat {
            let row = min(3, max(0, Int(((y - 35 + 5.5) / 56).rounded(.down))))
            let key = engine.layout.keys.first { $0.row == row }!.frame
            return key.minY + (y - (35 + CGFloat(row) * 56)) / 45 * key.height
        }
        for (i, (x, y)) in taps.enumerated() {
            let point = CGPoint(x: x, y: onTodaysRow(y))
            engine.touchBegan(id: i, at: point)
            engine.touchEnded(id: i, at: point)
            now += 0.2
        }
        XCTAssertEqual(target.text, "but I miss here we more than on the built in apple keyboard which also sucks ")
    }

    /// Settings › Experiments › Join the keyboard when unfolded: on, the Duo unfolded upright
    /// rebuilds as one keyboard rather than the split one, and off splits it again.
    func testJoiningTheUnfoldedKeyboardRebuildsOneLayout() {
        engine.posture = .unfoldedWide
        engine.windowInset = 75
        engine.width = 801
        XCTAssertTrue(engine.layout.isSplit)
        engine.joinsUnfoldedKeyboard = true
        XCTAssertFalse(engine.layout.isSplit)
        XCTAssertEqual(engine.layout.keys.filter { $0.label == "q" }.count, 1)
        XCTAssertEqual(engine.layout.key(.character("q"))?.frame.minX ?? 0, 19, accuracy: 0.001)
        engine.joinsUnfoldedKeyboard = false
        XCTAssertTrue(engine.layout.isSplit)
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

    // MARK: - One space per space press

    private func suggestion(_ text: String, _ kind: KeyboardSuggestion.Kind = .secondary) -> KeyboardSuggestion {
        KeyboardSuggestion(displayText: kind == .keepLiteral ? "“\(text)”" : text, replacement: text, kind: kind)
    }

    func testNextWordSuggestionsAppendOnlyOnAPickInTheSameWordGap() throws {
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        type("thank ")
        let you = try XCTUnwrap(engine.suggestions.first { $0.replacement == "you" })
        XCTAssertEqual(you.kind, .nextWord)
        XCTAssertFalse(you.willAutoReplace)
        XCTAssertEqual(target.text, "thank ")
        engine.acceptSuggestion(you)
        XCTAssertEqual(target.text, "thank you ")
        type("f")
        engine.acceptSuggestion(you)
        XCTAssertEqual(target.text, "thank you f")
    }

    func testNextWordPredictionsUseTheActiveLanguageAndRespectBoundaries() throws {
        engine.language = .spanish
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("es"))
        type("por ")
        XCTAssertFalse(engine.suggestions.isEmpty)
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.kind == .nextWord })
        for context in ["@por ", "todo/por ", "por  "] {
            XCTAssertTrue(engine.autocorrect.suggestions(beforeInput: context, field: .text,
                autocorrectionType: .default, predictionModel: engine.letterOdds).isEmpty, context)
        }
        for context in ["por. ", "hola\n"] {
            XCTAssertEqual(engine.autocorrect.suggestions(beforeInput: context, field: .text,
                autocorrectionType: .default, predictionModel: engine.letterOdds).map(\.replacement), ["yo", "el", "la"], context)
        }
        target.autocorrectionType = .no
        engine.refreshSuggestions()
        XCTAssertTrue(engine.suggestions.isEmpty)
    }

    /// An empty field and a new sentence offer three first words, capitalized as shift would
    /// be (not with Auto-capitalization off); after a word the three slots are always filled.
    func testSentenceStartersAndNextWordsFillAllThreeSlots() throws {
        target.autocapitalizationType = .sentences
        engine.configureForField()
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        engine.refreshSuggestions()
        XCTAssertEqual(engine.suggestions.map(\.replacement), ["I", "The", "I'm"])
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.kind == .nextWord && !$0.willAutoReplace })
        engine.acceptSuggestion(engine.suggestions[1])
        XCTAssertEqual(target.text, "The ")
        type("hi ")
        XCTAssertEqual(engine.suggestions.count, 3, "\(engine.suggestions.map(\.replacement))")
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.kind == .nextWord })
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.replacement.first?.isLowercase == true || $0.replacement == "I" })

        let model = engine.letterOdds
        func words(_ before: String, capitalized: Bool) -> [String] {
            engine.autocorrect.suggestions(beforeInput: before, field: .text, autocorrectionType: .default,
                                           predictionModel: model, capitalizesNext: capitalized).map(\.replacement)
        }
        for context in ["Done. ", "Really? ", "Wow! ", "Hi\n", ""] {
            XCTAssertEqual(words(context, capitalized: true), ["I", "The", "I'm"], context)
        }
        XCTAssertEqual(words("zzqx ", capitalized: false), ["the", "to", "and"], "an unknown word: the commonest words")
        XCTAssertEqual(words("Running late, ", capitalized: false), ["I", "but", "and"], "after a comma, words that start a clause")
        XCTAssertEqual(words("at 7 ", capitalized: false), [], "not after a number")
        XCTAssertEqual(words("Done.", capitalized: true), [], "no space after the period yet")
        engine.autoCapitalizes = false
        XCTAssertEqual(words("Done. ", capitalized: true), ["I", "the", "I'm"], "Auto-capitalization off adds no capitals")
    }

    /// A suggestion types its word and a space, so a space pressed right after it (a pick,
    /// then space out of habit) is swallowed, as on Apple's keyboard. Record typing logs
    /// showed every double space came from this: a word, what was typed, or an emoji picked,
    /// then space.
    func testASpaceRightAfterASuggestionIsSwallowed() {
        type("prett")
        engine.acceptSuggestion(suggestion("pretty"))
        XCTAssertEqual(target.text, "pretty ")
        now += 0.15
        tap(.space)
        XCTAssertEqual(target.text, "pretty ", "one space, not two")
        type("good")
        XCTAssertEqual(target.text, "pretty good")

        type(" is th")
        engine.acceptSuggestion(suggestion("th", .keepLiteral))
        now += 0.15
        tap(.space)
        XCTAssertEqual(target.text, "pretty good is th ", "what you typed, kept from the left slot")

        engine.acceptSuggestion(suggestion("😡", .emoji))
        now += 0.7
        tap(.space)
        XCTAssertEqual(target.text, "pretty good is th 😡 ", "an emoji for the word before")
        now += 0.7
        tap(.space)
        XCTAssertEqual(target.text, "pretty good is th 😡  ", "a second press is a space you asked for")
    }

    func testTheSwallowedSpaceStillCountsTowardsAPeriod() {
        type("prett")
        engine.acceptSuggestion(suggestion("pretty"))
        now += 0.1
        tap(.space)
        now += 0.2
        tap(.space)
        XCTAssertEqual(target.text, "pretty. ")
    }

    func testASpaceAfterTheCursorMovedIsTyped() {
        type("prett")
        engine.acceptSuggestion(suggestion("pretty"))
        target.adjustTextPosition(byCharacterOffset: -7)
        engine.textDidChange()
        tap(.space)
        XCTAssertEqual(target.text, " pretty ")

        let field = HexFixtureTextTarget()
        field.autocapitalizationType = UITextAutocapitalizationType.none
        let keys = FullKeyboardEngine(target: field, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
        keys.width = 393
        keys.configureForField()
        let p = keys.layout.key(.character("p"))!.frame
        keys.touchBegan(id: 1, at: CGPoint(x: p.midX, y: p.midY))
        keys.touchEnded(id: 1, at: CGPoint(x: p.midX, y: p.midY))
        keys.acceptSuggestion(suggestion("pretty"))
        keys.textDidChange()
        let space = keys.layout.key(.space)!.frame
        keys.touchBegan(id: 2, at: CGPoint(x: space.midX, y: space.midY))
        keys.touchEnded(id: 2, at: CGPoint(x: space.midX, y: space.midY))
        XCTAssertEqual(field.text, "pretty ", "a host that reports the keys' own edit leaves it swallowed")
    }

    /// "brown" in "the quick brown fox" selected and typed over: the cursor sits between the
    /// space before it and the space after it.
    private func typeOverBrown() {
        type("the quick  fox")
        target.adjustTextPosition(byCharacterOffset: -4)
        engine.textDidChange()
    }

    /// TestFlight: "Tapping on a word to select it, and then quickly typing in a correction
    /// doesn't account for the trailing space and you end up with 2 spaces inserted."
    func testASpaceBeforeASpaceMidSentenceIsHeldForTheNextWord() {
        typeOverBrown()
        type("black ")
        XCTAssertEqual(target.text, "the quick black fox", "one space, not two")
        tap(.space)
        XCTAssertEqual(target.text, "the quick black fox", "nor after a second press")
        type("cat")
        XCTAssertEqual(target.text, "the quick black cat fox", "the next word gets the space")
        tap(.space)
        punctuate(",")
        XCTAssertEqual(target.text, "the quick black cat, fox", "a mark goes against the word")

        target.adjustTextPosition(byCharacterOffset: 4)
        engine.textDidChange()
        type(" jumps")
        target.adjustTextPosition(byCharacterOffset: -5)
        engine.textDidChange()
        tap(.space)
        XCTAssertEqual(target.text, "the quick black cat, fox  jumps", "after a space, a space you asked for")
    }

    /// A held space reads as a typed one for the strip and the keys' page: the strip offers the
    /// next word (never the finished word's completions), a pick goes in after the held space
    /// rather than in the finished word's place, and 123 goes back to ABC.
    func testAHeldSpaceOffersTheNextWordAndGoesBackToLetters() throws {
        typeOverBrown()
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        type("thank ")
        XCTAssertEqual(target.text, "the quick thank fox")
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.kind == .nextWord }, "\(engine.suggestions.map(\.replacement))")
        let you = try XCTUnwrap(engine.suggestions.first { $0.replacement == "you" })
        engine.acceptSuggestion(you)
        XCTAssertEqual(target.text, "the quick thank you fox")
        XCTAssertTrue(engine.suggestions.allSatisfy { $0.kind == .nextWord }, "\(engine.suggestions.map(\.replacement))")

        tap(.layerSwitch(.numbers))
        tap(.character("7"))
        tap(.space)
        XCTAssertEqual(target.text, "the quick thank you 7 fox")
        XCTAssertEqual(engine.layout.layer, .letters, "a held space goes back to ABC as a typed one does")
    }

    func testAnAutocorrectionMidSentenceHoldsItsSpaceAndDeleteStillOffersTheRevert() {
        type("see  ok")
        target.adjustTextPosition(byCharacterOffset: -3)
        engine.textDidChange()
        type("teh ")
        XCTAssertEqual(target.text, "see the ok")
        XCTAssertNotEqual(engine.suggestions.first?.kind, .revert, "not before delete, as after a typed space")
        tap(.delete)
        XCTAssertEqual(target.text, "see the ok", "delete takes the held space")
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "see teh ok", "the strip puts back what was typed")
        tap(.space)
        XCTAssertEqual(target.text, "see teh ok", "space keeps it, with no second space")
    }

    func testAPickedSuggestionMidSentenceTypesNoSecondSpace() {
        typeOverBrown()
        type("blac")
        engine.acceptSuggestion(suggestion("black"))
        XCTAssertEqual(target.text, "the quick black fox")
        now += 0.15
        tap(.space)
        XCTAssertEqual(target.text, "the quick black fox", "the space after the cursor is the one")
        type("cat")
        XCTAssertEqual(target.text, "the quick black cat fox")

        target.adjustTextPosition(byCharacterOffset: 4)
        engine.textDidChange()
        type(" jumps")
        punctuate(".")
        target.adjustTextPosition(byCharacterOffset: -1)
        engine.textDidChange()
        engine.acceptSuggestion(suggestion("jumped"))
        XCTAssertEqual(target.text, "the quick black cat fox jumped.", "no space before a closing mark")
        for mark in [",", "!", "?", ";", ":", ")", "\"", "'", "’", "”"] {
            let field = HexFixtureTextTarget(text: "word" + mark)
            field.adjustTextPosition(byCharacterOffset: -1)
            let keys = FullKeyboardEngine(target: field, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
            XCTAssertTrue(keys.textAfterSeparates, mark)
        }
    }

    func testFrenchKeepsTheSpaceBeforeItsSpacedMarks() {
        engine.language = .french
        type("vrai")
        punctuate("?")
        target.adjustTextPosition(byCharacterOffset: -1)
        engine.textDidChange()
        XCTAssertFalse(engine.textAfterSeparates, "French puts a space before ?")
        engine.acceptSuggestion(suggestion("vraie"))
        XCTAssertEqual(target.text, "vraie ?")
    }

    func testADictationMidSentenceAddsNoSecondSpace() {
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "black", beforeContext: "the quick ", afterContext: " fox"), "black")
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "black", beforeContext: "the quick", afterContext: " fox"), " black")
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "black", beforeContext: "the quick ", afterContext: ". Then"), "black")
    }

    /// "th", then the e aimed a few points high 80 ms later, on the strip's lower half under
    /// its left slot. Record typing logs showed that tap picked "th" and a space, so "the"
    /// came out "th" and the space after it doubled. While you type, the keys take it.
    func testATapOnTheStripsLowerHalfWhileTypingTypesTheKeyBelow() {
        type("on t")
        tap(.character("h"))
        let e = engine.layout.key(.character("e"))!
        let strip = engine.layout.stripFrame
        let aimedHigh = CGPoint(x: e.frame.midX, y: strip.maxY - 6)
        XCTAssertLessThan(aimedHigh.y, engine.layout.touchAreaFrame.minY, "on the strip, above the keys' touch area")
        now += 0.08
        XCTAssertTrue(engine.takesStripTouch(at: aimedHigh))
        XCTAssertFalse(engine.takesStripTouch(at: CGPoint(x: aimedHigh.x, y: strip.minY + 6)), "the upper half stays the strip's")
        XCTAssertEqual(engine.key(at: aimedHigh)?.kind, .character("e"))
        engine.touchBegan(id: 9, at: aimedHigh)
        engine.touchEnded(id: 9, at: aimedHigh)
        XCTAssertEqual(target.text, "on the")
        now += 0.1
        tap(.space)
        XCTAssertEqual(target.text, "on the ")

        now += 0.3
        XCTAssertFalse(engine.takesStripTouch(at: aimedHigh), "after a pause a pick is a pick")
        down(1, .character("a"))
        XCTAssertTrue(engine.takesStripTouch(at: aimedHigh), "while a key is down")
        up(1, .character("a"))
    }

    /// With the Hex key on the left the strip runs to the right side, so the keys take its
    /// lower half over p too, and the Hex key, not the keys, keeps the spot over q.
    func testTheStripsLowerHalfRuleFollowsTheHexKeyToTheLeft() {
        engine.hexPlacement = .stripLeading
        type("on t")
        tap(.character("h"))
        let strip = engine.layout.stripFrame
        let p = engine.layout.key(.character("p"))!
        let q = engine.layout.key(.character("q"))!
        let hex = engine.layout.key(.hex)!
        let overP = CGPoint(x: p.frame.midX, y: strip.maxY - 6)
        let overQ = CGPoint(x: q.frame.midX, y: strip.maxY - 6)
        now += 0.08
        XCTAssertTrue(engine.takesStripTouch(at: overP))
        XCTAssertEqual(engine.key(at: overP)?.kind, .character("p"))
        XCTAssertFalse(engine.takesStripTouch(at: overQ), "the Hex key's, not the strip's")
        XCTAssertTrue(hex.hitFrame.contains(overQ))
        now += 0.3
        XCTAssertFalse(engine.takesStripTouch(at: overP), "after a pause a pick is a pick")
    }

    /// Holding the space bar still starts the trackpad, as Apple's does, so letting go types
    /// nothing: a hold meant to move the cursor typed a space beside the one already there.
    func testHoldingSpaceStillStartsTheTrackpadAndTypesNoSpace() {
        type("hello ")
        let space = point(.space)
        engine.touchBegan(id: 1, at: space)
        engine.holdSpace(forTouch: 1)
        XCTAssertTrue(engine.isTrackpadActive)
        engine.touchEnded(id: 1, at: space)
        XCTAssertEqual(target.text, "hello ")

        engine.touchBegan(id: 2, at: space)
        engine.holdSpace(forTouch: 2)
        let left = CGPoint(x: space.x - FullKeyboardEngine.trackpadWidth(" ") - FullKeyboardEngine.trackpadWidth("o") - 1, y: space.y)
        engine.touchMoved(id: 2, to: left)
        engine.touchEnded(id: 2, at: left)
        XCTAssertEqual(target.text, "hello ")
        XCTAssertEqual(target.cursorIndex, 4, "sliding after the hold moves the cursor")
    }

    func testTwoThumbSelectionDeletesExactlyTheRangeIncludingAnEmoji() {
        target.insertText("ab👍🏽cd")
        engine.textDidChange()
        engine.trackpadSelectionState.enabled = true

        down(1, .space)
        engine.holdSpace(forTouch: 1)
        down(2, .character("a"))

        let start = point(.character("a"))
        let width = "👍🏽cd".reduce(CGFloat.zero) { $0 + FullKeyboardEngine.trackpadWidth($1) }
        let end = CGPoint(x: start.x - width, y: start.y)
        engine.touchMoved(id: 2, to: end)
        XCTAssertEqual(engine.selectionPresentation?.phase, .selecting)
        XCTAssertEqual(engine.selectionPresentation?.selected, "👍🏽cd")

        engine.touchEnded(id: 2, at: end)
        up(1, .space)
        XCTAssertEqual(engine.selectionPresentation?.phase, .actions)
        XCTAssertEqual(target.text, "ab👍🏽cd")
        XCTAssertEqual(target.cursorIndex, 5)

        engine.performTrackpadSelectionAction(.delete) { _ in }
        XCTAssertEqual(target.text, "ab")
        XCTAssertEqual(target.cursorIndex, 2)
        XCTAssertFalse(engine.isSelectionActive)
    }

    /// Types a mark from the 123 page; the next space goes back to the letters.
    private func punctuate(_ mark: String) {
        if engine.layout.layer == .letters { tap(.layerSwitch(.numbers)) }
        tap(.character(mark))
        now += 0.5
    }

    /// Types `text` key by key: letters on the letters page, digits and marks from the 123 page.
    private func keys(_ text: String) {
        for ch in text {
            if ch == " " {
                tap(.space)
            } else if ch.isLetter {
                if engine.layout.layer != .letters { tap(.layerSwitch(.letters)) }
                tap(.character(String(ch)))
            } else {
                if engine.layout.layer == .letters { tap(.layerSwitch(.numbers)) }
                tap(.character(String(ch)))
            }
            now += 0.5
        }
    }

    private func smartField(quotes: UITextSmartQuotesType? = .default, dashes: UITextSmartDashesType? = .default, language: KeyboardLanguage = .english) {
        target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        target.smartQuotesType = quotes
        target.smartDashesType = dashes
        engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.language = language
        engine.configureForField()
    }

    /// X (Brandon): "no smart quotes/etc." Apple's keyboard (black box, iOS 27.2, a UITextView
    /// and a text field) curls ' and " by what comes before them, makes a second hyphen an em
    /// dash, and writes autocorrect's apostrophes as ’; a field whose smartQuotesType or
    /// smartDashesType is .no gets straight ones, as there.
    func testSmartQuotesAndDashesFollowTheFieldAsOnApplesKeyboard() {
        smartField()
        keys("'hi' it's \"yes\" (\"ok\") 5'9\" ('a') so '\"ok\"' well--known this -- that one---two yes - no")
        XCTAssertEqual(target.text, "‘hi’ it’s “yes” (“ok”) 5’9” (‘a’) so ‘“ok”’ well—known this — that one—-two yes - no")
        smartField()
        keys("a--")
        tap(.delete)
        XCTAssertEqual(target.text, "a", "delete takes the dash whole")

        smartField()
        type("dont ")
        XCTAssertEqual(target.text, "don’t ", "autocorrect's apostrophe")
        type("im")
        XCTAssertTrue(engine.suggestions.contains { $0.displayText == "I’m" && $0.replacement == "I'm" }, "the strip shows it too")
        type(" ")
        XCTAssertEqual(target.text, "don’t I’m ")
        type("ill")
        tap(.delete)
        keys("'l")
        XCTAssertEqual(target.text, "don’t I’m il’l")
        XCTAssertEqual(AutocorrectEngine.currentToken(in: engine.textBefore), "il'l", "the keys read ’ as an apostrophe")

        smartField(quotes: .no, dashes: .no)
        keys("'hi' it's \"yes\" well--known ")
        type("dont ")
        XCTAssertEqual(target.text, "'hi' it's \"yes\" well--known don't ")

        smartField(quotes: .yes, dashes: .no)
        keys("\"well--known\"")
        XCTAssertEqual(target.text, "“well--known”")
    }

    /// Apple's "AZERTY – French" apostrophe key (iOS 27.2 simulator, black box): right after a
    /// letter it shows ’ and types the apostrophe, curled as the field curls quotes; after
    /// anything else it shows and types ´. Held, it offers ' ’ ‘ ` after a letter and ´ ˋ ˆ ¨
    /// elsewhere, each typed as it is.
    func testFrenchApostropheKeyTypesAsApplesDoes() {
        smartField(language: .french)
        engine.autocorrect.isEnabled = false
        let apostrophe = KeyKind.character(FrenchTyping.key)
        let key = engine.layout.key(apostrophe)!
        XCTAssertEqual(engine.keycapLabel(for: key), "´", "nothing before it")
        tap(apostrophe)
        type("l")
        XCTAssertEqual(engine.keycapLabel(for: key), "’")
        XCTAssertEqual(engine.displayLabel(for: key), "’")
        tap(apostrophe)
        XCTAssertEqual(engine.keycapLabel(for: key), "´", "after an apostrophe")
        tap(apostrophe)
        type("ami e ")
        tap(apostrophe)
        type("e")
        XCTAssertEqual(target.text, "´l’´ami e ´e", "never a dead key")

        smartField(quotes: .no, language: .french)
        engine.autocorrect.isEnabled = false
        type("l")
        tap(apostrophe)
        type("homme")
        XCTAssertEqual(target.text, "l'homme")

        smartField(language: .french)
        engine.autocorrect.isEnabled = false
        var id = 700
        func hold(pick: String) {
            let key = engine.layout.key(apostrophe)!
            id += 1
            engine.touchBegan(id: id, at: CGPoint(x: key.frame.midX, y: key.frame.midY))
            XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: id), pick)
            guard let menu = engine.activeAccentMenu, let index = menu.options.firstIndex(of: pick) else {
                return XCTFail("no \(pick) in \(engine.activeAccentMenu?.options ?? [])")
            }
            let cell = menu.cellFrames[index]
            engine.touchMoved(id: id, to: CGPoint(x: cell.midX, y: cell.midY))
            engine.touchEnded(id: id, at: CGPoint(x: cell.midX, y: cell.midY))
        }
        hold(pick: "¨")
        type("d")
        hold(pick: "'")
        type("a")
        hold(pick: "‘")
        XCTAssertEqual(target.text, "¨d'a‘", "a held choice goes in as it is")
        type(" ")
        hold(pick: "ˆ")
        XCTAssertEqual(target.text, "¨d'a‘ ˆ")

        // Canada's and Switzerland's own layouts end row 2 in the same key, with the same rules.
        for language in [KeyboardLanguage.frenchCanadian, .frenchSwiss] {
            smartField(language: language)
            engine.autocorrect.isEnabled = false
            let key = engine.layout.key(apostrophe)!
            XCTAssertEqual(key.row, 1, "\(language)")
            XCTAssertEqual(engine.keycapLabel(for: key), "´", "\(language)")
            tap(apostrophe)
            type("qu")
            XCTAssertEqual(engine.keycapLabel(for: key), "’", "\(language)")
            tap(apostrophe)
            type("il")
            XCTAssertEqual(target.text, "´qu’il", "\(language)")
            id += 1
            engine.touchBegan(id: id, at: CGPoint(x: key.frame.midX, y: key.frame.midY))
            XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: id))
            XCTAssertEqual(Set(engine.activeAccentMenu?.options ?? []), ["'", "’", "‘", "`"], "\(language)")
            engine.touchCancelled(id: id)
        }
    }

    /// Each of Apple's keyboards types its language's quotes (black box, iOS 27.2): „Hallo“ ‚tag‘
    /// in German, where the apostrophe key types ‘ in a word too; « Bonjour » with no-break
    /// spaces inside and ‘salut’ in French; „tak” ‚nie’ in Polish; «да» in Russian.
    func testSmartQuotesFollowTheKeysLanguage() {
        smartField(language: .german)
        keys("\"hallo\" 'tag' geht's")
        XCTAssertEqual(target.text, "„hallo“ ‚tag‘ geht‘s")
        smartField(language: .french)
        keys("\"bonjour\" 'salut' l'ami")
        XCTAssertEqual(target.text, "«\u{00A0}bonjour\u{00A0}» ‘salut’ l’ami")
        smartField(language: .frenchCanadian)
        keys("\"oui\"")
        XCTAssertEqual(target.text, "«\u{00A0}oui\u{00A0}»")
        smartField(language: .polish)
        keys("\"tak\" 'nie'")
        XCTAssertEqual(target.text, "„tak” ‚nie’")
        smartField(language: .russian)
        keys("\"1\" '2'")
        XCTAssertEqual(target.text, "«1» ‘2’")
    }

    /// Apple's keyboard (black box, iOS 27.2) puts , . ! ? ; : and ) against a picked
    /// suggestion's word, taking the space the suggestion typed; a quote, a bracket or @ keeps
    /// it, and so does a space you typed yourself. A field's smartInsertDeleteType changed
    /// nothing there.
    func testMarksGoAgainstAPickedSuggestion() {
        for (mark, expected) in [(",", "hello,"), (".", "hello."), (")", "hello)"), ("(", "hello ("), ("@", "hello @")] {
            smartField(quotes: .no)
            type("hel")
            engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
            keys(mark)
            XCTAssertEqual(target.text, expected, mark)
        }
        smartField()
        type("hel")
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
        keys("\"")
        XCTAssertEqual(target.text, "hello “")
        smartField()
        type("hello ")
        keys(".")
        XCTAssertEqual(target.text, "hello .", "a space you typed stays")
    }

    /// X (Erick): "If I add punctuation after a typo autocorrect does not fix the typo." A
    /// mark that closes a word fixes it as space does and goes in after the fix, as on Apple's
    /// keyboard; delete right after takes the mark, and the strip offers the typo back.
    func testPunctuationAfterATypoFixesItFirst() {
        for mark in [",", ".", "!", "?", ";", ":", ")", "\""] {
            target = HexFixtureTextTarget()
            target.autocapitalizationType = UITextAutocapitalizationType.none
            engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
            engine.width = 393
            engine.clock = { [unowned self] in self.now }
            engine.configureForField()
            type("see teh")
            punctuate(mark)
            XCTAssertEqual(target.text, "see the" + mark, mark)
            type(" ok")
            XCTAssertEqual(target.text, "see the\(mark) ok", mark)
        }

        type(" recieve")
        punctuate(".")
        XCTAssertTrue(target.text.hasSuffix(" receive."))
        tap(.delete)
        XCTAssertTrue(target.text.hasSuffix(" receive"), "delete takes the mark")
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertTrue(target.text.hasSuffix(" recieve"), "the strip puts back what was typed")
        punctuate(".")
        XCTAssertTrue(target.text.hasSuffix(" recieve."), "the word you kept stays")

        type(" approx")
        punctuate(".")
        XCTAssertTrue(target.text.hasSuffix(" approx."), "an abbreviation's period")
        type(" a")
        punctuate(",")
        XCTAssertTrue(target.text.hasSuffix(" a,"))
    }

    /// X (Philippe): French puts a space before ? ! ; and :, but Apple's French keyboards type
    /// none (black box, iOS 27.2 simulator, Français (France) AZERTY: "Salut" then ? gave
    /// "Salut?", and "salut ?" kept the plain space typed before it). Hex types the marks as
    /// tapped too, in every French layout; dictation adds French spacing (`FrenchSpacing`).
    func testFrenchMarksGoInAsTyped() {
        for language in [KeyboardLanguage.french, .frenchCanadian, .frenchSwiss] {
            target = HexFixtureTextTarget()
            target.autocapitalizationType = UITextAutocapitalizationType.none
            engine = FullKeyboardEngine(target: target, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
            engine.width = 393
            engine.clock = { [unowned self] in self.now }
            engine.language = language
            engine.configureForField()
            type("salut")
            punctuate("?")
            XCTAssertEqual(target.text, "salut?", language.rawValue)
            type(" oui ")
            punctuate("!")
            XCTAssertEqual(target.text, "salut? oui !", "\(language.rawValue): the space you typed stays as it is")
            type(" non")
            punctuate(":")
            XCTAssertEqual(target.text, "salut? oui ! non:", language.rawValue)
        }
    }

    // MARK: - Number row (Settings › Keyboard › Number row)

    /// With the number row on, digits type straight from the letters page beside letters, and
    /// nothing corrects a word holding them: "12b", "9pm," and "0199" stay as typed, with
    /// Spatial autocorrect reading the letters around them.
    func testNumberRowTypesDigitsBesideLettersAndNothingCorrectsThem() throws {
        engine.showsNumberRow = true
        let model = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        engine.letterOdds = model
        engine.autocorrect.decoder = TypingDecoder(model: model)
        XCTAssertTrue(engine.layout.hasNumberRow)
        XCTAssertEqual(engine.layout.layer, .letters)
        tap(.shift)
        type("flat 12b at 9pm")
        XCTAssertEqual(engine.layout.layer, .letters, "the digits never leave the letters page")
        tap(.layerSwitch(.numbers))
        XCTAssertTrue(engine.layout.keys.filter(\.isNumberRow).isEmpty, "the 123 page's row 1 is the digits")
        tap(.character(","))
        type(" call 555 0199")
        XCTAssertEqual(target.text, "Flat 12b at 9pm, call 555 0199")
        tap(.space)
        XCTAssertEqual(target.text, "Flat 12b at 9pm, call 555 0199 ")
        let keys = try XCTUnwrap(engine.autocorrect.decoderKeys)
        XCTAssertFalse(keys.centres.keys.contains { $0.isNumber }, "digits aren't in the decoder's letters")
    }

    /// Next-letter touch help never turns a digit into a letter or a letter into a digit: a tap
    /// on a digit's edge right by row 1 types the digit, and a tap on a row-1 letter's top edge
    /// right under the digits types a letter, however likely the letters around them are.
    func testNextLetterHelpLeavesTheNumberRowAlone() throws {
        engine.showsNumberRow = true
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        type("th")
        let layout = engine.layout
        for digit in layout.keys where digit.isNumberRow {
            let edge = CGPoint(x: digit.frame.midX, y: digit.hitFrame.maxY - 0.5)
            XCTAssertEqual(engine.key(at: edge)?.kind, digit.kind)
        }
        for letter in layout.keys where letter.row == 0 {
            let edge = CGPoint(x: letter.frame.midX, y: letter.hitFrame.minY + 0.5)
            XCTAssertEqual(engine.key(at: edge)?.character?.first?.isLetter, true, letter.label)
        }
    }

    /// Without the switch, or on an iPad, the keys have no number row.
    func testNumberRowNeedsItsSwitchAndAnIPhone() {
        XCTAssertFalse(engine.layout.hasNumberRow, "off by default")
        engine.showsNumberRow = true
        XCTAssertTrue(engine.layout.hasNumberRow)
        engine.pad = .docked(.mini)
        XCTAssertFalse(engine.hasNumberRow)
        XCTAssertFalse(engine.layout.hasNumberRow)
    }

    func testSwipeInsertsAWordBoundaryAndCanBeUndoneAfterTheHostEcho() {
        target.insertText("hello")
        engine.textDidChange()

        down(1, .character("w"))
        engine.beginSwipe(touchID: 1)
        engine.endSwipe(typing: ["world", "word"], points: 12, decodeTime: nil)
        XCTAssertEqual(target.text, "hello world")

        engine.textDidChange()
        XCTAssertTrue(engine.suggestions.contains { $0.kind == .swiped && $0.replacement == "word" })
        tap(.delete)
        XCTAssertEqual(target.text, "hello")
        XCTAssertEqual(target.cursorIndex, 5)
    }

    func testASwipedWordFollowsSpacingAndPunctuationAsApplesDoes() {
        for (before, after) in [("Hi.", "Hi. "), ("(", "("), ("¿", "¿"), ("say \"", "say \""), ("3", "3 "), ("x\n", "x\n")] {
            XCTAssertEqual(SwipeTyping.needsSpace(before: before), after != before, before)
        }
        XCTAssertFalse(SwipeTyping.needsSpace(before: ""))
        XCTAssertFalse(SwipeTyping.needsSpace(before: nil))
        XCTAssertTrue(SwipeTyping.needsSpace(before: "\"hi\""), "a closing quote")
    }
}

// MARK: - Adaptive touch (Settings › Experiments)

extension FullKeyboardEngineTests {
    private func adaptive(on keys: FullKeyboardEngine? = nil) -> AdaptiveTouch {
        let touch = AdaptiveTouch(storage: .memory, settings: AdaptiveTouchSettings(defaults: defaults))
        (keys ?? engine).adaptiveTouch = touch
        return touch
    }

    private func learned(_ touch: AdaptiveTouch) -> (weak: Int, picked: Int, strong: Int) {
        touch.model.contexts.reduce((0, 0, 0)) { ($0.0 + Int($1.weak), $0.1 + Int($1.picked), $0.2 + Int($1.strong)) }
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

    private func tapAt(_ point: CGPoint, id: Int = 1) {
        engine.touchBegan(id: id, at: point)
        engine.touchEnded(id: id, at: point)
        now += 0.5
    }

    func testAdaptiveTouchLearnsFromAWordOnlyOnceTheNextOneShowsItStood() {
        let touch = adaptive()
        type("hello ")
        XCTAssertEqual(learned(touch).weak, 0, "a word waits for the next one")
        type("world ")
        XCTAssertEqual(learned(touch).weak, 5)
        target.insertText("x")
        engine.textDidChange()
        type(" again ")
        XCTAssertEqual(learned(touch).weak, 5, "the host changed the text: \"world\" teaches nothing")
    }

    func testAdaptiveTouchLearnsNothingFromAnAutocorrectionButKeepsWhatYouUndidItTo() {
        let touch = adaptive()
        type("teh ")
        XCTAssertEqual(target.text, "the ")
        type("cat ")
        XCTAssertEqual(learned(touch).weak, 0, "an autocorrection left in place can't confirm itself")
        type("teh ")
        engine.deleteBackward()
        XCTAssertEqual(engine.suggestions.first?.kind, .revert)
        engine.acceptSuggestion(engine.suggestions[0])
        type(" dog it ")
        XCTAssertEqual(target.text, "the cat teh dog it ")
        XCTAssertEqual(learned(touch).weak, 3 + 3, "cat and dog, as typed")
        XCTAssertEqual(learned(touch).strong, 3, "\"teh\", kept over its fix")
    }

    func testAdaptiveTouchLabelsAnErasedTapWithTheNeighbourThatReplacedIt() {
        let touch = adaptive()
        type("car")
        engine.deleteBackward()
        type("t is it ")
        XCTAssertEqual(target.text, "cat is it ")
        XCTAssertEqual(learned(touch).strong, 1, "the r tap meant t")
        XCTAssertEqual(learned(touch).weak, 3 + 2)

        // A different word, not a slip: p is no neighbour of t.
        type("cat")
        engine.deleteBackward()
        type("p it is ")
        XCTAssertEqual(learned(touch).strong, 1)
    }

    func testAdaptiveTouchLearnsFromAPickedSuggestionOfTheSameLength() {
        let touch = adaptive()
        type("thw")
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "the", replacement: "the", kind: .secondary))
        type("hel")
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
        type("is it ")
        XCTAssertEqual(target.text, "the hello is it ")
        XCTAssertEqual(learned(touch).picked, 3, "the w tap meant e")
        XCTAssertEqual(learned(touch).weak, 2, "a completion teaches nothing; \"is\" as typed")
    }

    func testAdaptiveTouchKeepsClaimedAndStripTouchesOutOfItsLabels() throws {
        engine.letterOdds = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        let touch = adaptive()
        let e = engine.layout.key(.character("e"))!
        let d = engine.layout.key(.character("d"))!
        type("th")
        tapAt(CGPoint(x: max(e.frame.minX, d.frame.minX) + 4, y: e.hitFrame.maxY + 2))
        XCTAssertEqual(target.text, "the", "the next-letter odds claimed a d tap for e")
        type(" w")
        let i = engine.layout.key(.character("i"))!.frame
        tapAt(CGPoint(x: i.midX, y: engine.layout.touchAreaFrame.minY - 4))
        type("n it ")
        XCTAssertEqual(target.text, "the win it ")
        XCTAssertEqual(learned(touch).weak, 2 + 2, "neither the claimed e nor the i from the strip")
    }

    func testAdaptiveTouchMovesTheDecodersCentresNeverTheKeys() throws {
        let model = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        engine.letterOdds = model
        engine.autocorrect.decoder = TypingDecoder(model: model)
        let keys = engine.layout.keys
        let area = engine.layout.touchAreaFrame
        let points = stride(from: area.minX + 1, to: area.maxX, by: 7).flatMap { x in
            stride(from: area.minY + 1, to: area.maxY, by: 5).map { CGPoint(x: x, y: $0) }
        }
        let pressed = points.map { engine.key(at: $0)?.kind }
        let stockCentres = try XCTUnwrap(engine.autocorrect.decoderKeys)

        let touch = adaptive()
        XCTAssertEqual(engine.autocorrect.decoderKeys, stockCentres, "nothing learned yet: the stock centres")
        XCTAssertNil(engine.autocorrect.decoderBaselineKeys)
        try teach(touch, dx: 0.2)
        XCTAssertTrue(touch.isActive)
        XCTAssertEqual(engine.layout.keys, keys, "keycaps and hit rectangles stay where they are")
        XCTAssertEqual(points.map { engine.key(at: $0)?.kind }, pressed)
        let e = engine.layout.key(.character("e"))!.frame
        let personal = try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"])
        XCTAssertEqual(personal.y, e.midY, accuracy: 0.01)
        XCTAssertGreaterThan(personal.x - e.midX, 0.12 * e.width)
        XCTAssertLessThanOrEqual(personal.x - e.midX, CGFloat(AdaptiveTouchModel.bound) * e.width + 0.01)
        XCTAssertEqual(engine.autocorrect.decoderBaselineKeys, stockCentres, "beside them, the stock centres")
        XCTAssertEqual(engine.swipeKeys.centres["e"]?.x, e.midX, "Swipe typing reads the drawn keys")
    }

    /// With Adaptive touch on, Learn how I type's per-letter offsets no longer move the centres
    /// the decoder reads (no stacking), but stay the baseline a correction must also clear.
    func testAdaptiveTouchReplacesLearnHowITypesOffsetsButKeepsThemAsTheBaseline() throws {
        let e = engine.layout.key(.character("e"))!.frame
        engine.tapOffsets = ["e": CGVector(dx: -4, dy: 2)]
        let journal = try XCTUnwrap(TypingDecoder.Keys(layout: engine.layout, offsets: engine.tapOffsets))
        let touch = adaptive()
        XCTAssertEqual(engine.autocorrect.decoderKeys, TypingDecoder.Keys(layout: engine.layout), "too little evidence: the stock centres")
        XCTAssertEqual(engine.autocorrect.decoderBaselineKeys, journal)
        try teach(touch, dx: 0.2)
        XCTAssertGreaterThan(try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"]).x, e.midX)
        XCTAssertEqual(engine.autocorrect.decoderBaselineKeys, journal)
        engine.adaptiveTouch = nil
        XCTAssertEqual(engine.autocorrect.decoderKeys, journal, "off: Learn how I type's offsets, as before")
        XCTAssertNil(engine.autocorrect.decoderBaselineKeys)
    }

    func testAdaptiveTouchKeepsEachKeyboardSizeAndHexKeySideApart() throws {
        let touch = adaptive()
        try teach(touch, dx: 0.2)
        let e = engine.layout.key(.character("e"))!.frame
        let shift = try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"]).x - e.midX
        engine.orientation = .landscape
        XCTAssertFalse(touch.isActive, "landscape starts from the stock centres")
        XCTAssertEqual(engine.autocorrect.decoderKeys, TypingDecoder.Keys(layout: engine.layout))
        engine.orientation = .portrait
        XCTAssertTrue(touch.isActive)
        engine.hexPlacement = .stripLeading
        XCTAssertFalse(touch.isActive, "the Hex key on the other side is another grip")
        engine.hexPlacement = .stripTrailing
        engine.width = 440
        XCTAssertFalse(touch.isActive, "another iPhone's width")
        engine.width = 390
        XCTAssertTrue(touch.isActive, "the same size, a slightly different key plane")
        let narrower = engine.layout.key(.character("e"))!.frame
        let moved = try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"]).x - narrower.midX
        XCTAssertEqual(moved / narrower.width, shift / e.width, accuracy: 0.001, "offsets are in keycaps")
    }

    /// Another arrangement of the letters is another key plane: what was learned on QWERTY
    /// never moves QWERTZ's centres, and comes back with QWERTY.
    func testAdaptiveTouchKeepsEachLetterLayoutApart() throws {
        let touch = adaptive()
        try teach(touch, dx: 0.2)
        XCTAssertTrue(touch.isActive)
        let qwerty = try XCTUnwrap(AdaptiveTouchGeometry(layout: engine.layout)).key
        engine.letterLayout = .qwertz
        XCTAssertNotEqual(try XCTUnwrap(AdaptiveTouchGeometry(layout: engine.layout)).key, qwerty)
        XCTAssertFalse(touch.isActive, "QWERTZ starts from the stock centres")
        XCTAssertEqual(engine.autocorrect.decoderKeys, TypingDecoder.Keys(layout: engine.layout))
        engine.letterLayout = .azerty
        XCTAssertFalse(touch.isActive)
        engine.letterLayout = .qwerty
        XCTAssertTrue(touch.isActive, "QWERTY's profile is still there")
    }

    func testAdaptiveTouchFallsBackToStockWhenTheGripChangesAndKeepsBothGrips() throws {
        let touch = adaptive()
        try teach(touch, dx: 0.2)
        XCTAssertTrue(touch.isActive)
        let e = engine.layout.key(.character("e"))!.frame
        try teach(touch, dx: -0.2, taps: 24, sessions: 1)
        XCTAssertFalse(touch.isActive, "the profile fits worse than the stock centres: stock at once")
        XCTAssertEqual(engine.autocorrect.decoderKeys, TypingDecoder.Keys(layout: engine.layout))
        XCTAssertNil(engine.autocorrect.decoderBaselineKeys)
        try teach(touch, dx: -0.2, taps: 420, sessions: 4)
        XCTAssertTrue(touch.isActive, "the new grip learned its own profile")
        XCTAssertLessThan(try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"]).x, e.midX)
        try teach(touch, dx: 0.2, taps: 40, sessions: 1)
        XCTAssertTrue(touch.isActive, "back to the first grip, whose profile was kept")
        XCTAssertGreaterThan(try XCTUnwrap(engine.autocorrect.decoderKeys?.centres["e"]).x, e.midX)
        XCTAssertEqual(touch.model.contexts.filter { $0.geometry != 0 }.count, 2)
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

    func testAdaptiveTouchUntrainedTypesExactlyAsWithItOff() throws {
        let model = try XCTUnwrap(TypingDecoderModel.bundled("en"))
        func typing(adaptive: Bool) -> [String] {
            let field = HexFixtureTextTarget()
            field.autocapitalizationType = UITextAutocapitalizationType.none
            let keys = FullKeyboardEngine(target: field, autocorrect: AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults)))
            keys.width = 402
            keys.letterOdds = model
            keys.autocorrect.decoder = TypingDecoder(model: model)
            keys.configureForField()
            if adaptive { keys.adaptiveTouch = AdaptiveTouch(storage: .memory, settings: AdaptiveTouchSettings(defaults: defaults)) }
            var seed: UInt64 = 7
            func jitter() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(Int(seed >> 33) % 1000) / 1000 - 0.5
            }
            var out: [String] = []
            for ch in "teh quick bronw fox jumsp ovr the lazt dog and keeos running " {
                let key = keys.layout.key(ch == " " ? .space : .character(String(ch)))!
                let p = CGPoint(x: key.frame.midX + jitter() * key.frame.width * 0.7, y: key.frame.midY + jitter() * key.frame.height * 0.6)
                keys.touchBegan(id: 1, at: p)
                keys.touchEnded(id: 1, at: p)
                if ch == "x" { keys.deleteBackward() }
                // The decoder reads exactly what it reads with the experiment off. (Suggestions
                // that tie can swap between runs: Swift seeds each dictionary's order.)
                XCTAssertEqual(keys.autocorrect.decoderKeys, TypingDecoder.Keys(layout: keys.layout))
                XCTAssertNil(keys.autocorrect.decoderBaselineKeys)
                out.append(field.text)
            }
            return out
        }
        XCTAssertEqual(typing(adaptive: true), typing(adaptive: false))
    }

    func testAdaptiveTouchFileIsSmallProtectedFromBackupAndReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AdaptiveTouchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(AdaptiveTouch.fileName)
        let settings = AdaptiveTouchSettings(defaults: defaults)
        let touch = AdaptiveTouch(storage: .file(url), settings: settings)
        engine.adaptiveTouch = touch
        try teach(touch, dx: 0.2)
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
        XCTAssertEqual(engine.autocorrect.decoderKeys, TypingDecoder.Keys(layout: engine.layout))
        XCTAssertTrue(touch.model.contexts.allSatisfy { $0.geometry == 0 })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try data.write(to: url)
        XCTAssertTrue(AdaptiveTouch(storage: .file(url), settings: settings).model.contexts.allSatisfy { $0.geometry == 0 })
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
}


/// Hex's Greek and Czech typing rules (`testGreekTypesAndSwitches`, `testCzechTypesAndSwitches`)
/// on the engine alone: the language set directly instead of through the view's space bar.
extension FullKeyboardEngineTests {
    private func hold(_ character: String, pick: String) {
        let key = engine.layout.key(.character(character))!
        engine.touchBegan(id: 7, at: CGPoint(x: key.frame.midX, y: key.frame.midY))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 7), character)
        guard let menu = engine.activeAccentMenu, let index = menu.options.firstIndex(of: pick) else {
            return XCTFail("\(character): no \(pick)")
        }
        let cell = menu.cellFrames[index]
        engine.touchMoved(id: 7, to: CGPoint(x: cell.midX, y: cell.midY))
        engine.touchEnded(id: 7, at: CGPoint(x: cell.midX, y: cell.midY))
    }

    func testGreekTypesItsTonosAndFinalSigma() {
        engine.language = .greek
        XCTAssertNil(engine.autocorrect.decoder, "no Greek typing model: the dictionary engine")
        type("καλημε´ρα")
        XCTAssertEqual(target.text, "καλημέρα")
        type("λο´γοσ")
        XCTAssertEqual(target.text, "καλημέραλόγος", "final sigma")
        type("ι")
        XCTAssertEqual(target.text, "καλημέραλόγοσι", "σ again once a letter follows")
        hold("ι", pick: "ϊ")
        type("´")
        XCTAssertEqual(target.text, "καλημέραλόγοσιΐ")
        type("´")
        XCTAssertEqual(target.text, "καλημέραλόγοσιΐ´", "an accented vowel takes no second tonos")
        type("ρ´")
        hold("σ", pick: "ς")
        XCTAssertEqual(Array(target.text.unicodeScalars.suffix(4)).map(\.value), [0x00B4, 0x03C1, 0x00B4, 0x03C2])
        engine.language = .english
        type("s")
        XCTAssertTrue(target.text.hasSuffix("ςs"), "English's s is never a final sigma")
        XCTAssertTrue(AutocorrectEngine.isSentenceStart("Τι κάνεις; ", language: .greek))
        XCTAssertFalse(AutocorrectEngine.isSentenceStart("first; "))
    }

    func testCzechMarksAccentTheLetterBeforeThem() {
        engine.language = .czech
        engine.autocorrect.isEnabled = false
        XCTAssertNil(engine.autocorrect.decoder, "no Czech typing model: the dictionary engine")
        tap(.shift)
        type("prˇi´lisˇ zˇlutˇoucˇky´ ku")
        hold("ˇ", pick: "˚")
        type("nˇ")
        XCTAssertEqual(target.text, "Příliš žluťoučký kůň")
        XCTAssertEqual(target.text.unicodeScalars.count, target.text.count, "precomposed letters, no combining marks")
        tap(.delete)
        XCTAssertEqual(target.text, "Příliš žluťoučký ků", "delete takes ň whole")
        while target.hasText { tap(.delete) }
        type("´ x´ aˇ e´´ ")
        XCTAssertEqual(target.text, "´ x´ aˇ é´ ", "a mark with nothing to accent types itself")
        type("a")
        hold("ˇ", pick: "˚")
        type("c")
        hold("ˇ", pick: "ˇ")
        type(" uˇ")
        XCTAssertEqual(target.text, "´ x´ aˇ é´ åč ů")
        tap(.shift)
        type("a´")
        tap(.shift)
        type("uˇ")
        XCTAssertTrue(target.text.hasSuffix("ÁŮ"), target.text)
        engine.language = .english
        XCTAssertNil(engine.layout.key(.character("ˇ")), "English has no ˇ key")
    }
}
