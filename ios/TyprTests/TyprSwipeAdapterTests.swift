import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprSwipeAdapterTests: XCTestCase {
    private enum Keys: CaseIterable {
        case joined, bottomRow, unfoldedJoined, split, splitColumns
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var runningSystemMajorVersion = 0

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "TyprSwipeAdapterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeView(_ keys: Keys = .joined, typrSwipe: Bool = true, decoding: @escaping SwipeDecoding,
                          configure: (HexFixtureTextTarget) -> Void = { _ in })
        -> (FullKeyboardView, HexFixtureTextTarget, TyprAutocorrectAdapter) {
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .typrTyping] = true
        settings[experiment: .typrSwipeTyping] = typrSwipe
        let keyboard = TyprFullKeyboardSettings(defaults: defaults)
        settings[experiment: .typrBottomRow] = keys == .bottomRow
        keyboard.bottomRow = BottomRow(order: [.typr, .space, .period], periodKey: true)
        settings[experiment: .typrSplitKeyboard] = keys == .split || keys == .splitColumns
        keyboard.splitKeyboard = keys == .split || keys == .splitColumns
        keyboard.splitColumns = keys == .splitColumns
        let adapter = TyprAutocorrectAdapter(engine: TyprAutocorrectEngine(
            checker: Checker(valid: ["hello"]), learning: KeyboardLearningSession(defaults: defaults),
            spatialDecoder: SpatialWordDecoder(lexicons: [.english: spatialLexicon([("hello", 100)])]),
            contextResources: .init(model: nil)))
        adapter.swipeDecoding = decoding
        let target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        configure(target)
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target, autocorrect: adapter, defaults: defaults)
        view.hexPlacementOverride = .stripTrailing
        view.swipeOverride = true
        let unfolded = keys == .unfoldedJoined || keys == .split || keys == .splitColumns
        if unfolded {
            view.engine.showsNumberRow = false
            view.engine.posture = .unfoldedWide
            view.engine.windowInset = 75
        }
        view.syncTyprVariants()
        view.frame = CGRect(x: 0, y: 0, width: unfolded ? 801 : 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        XCTAssertEqual(view.engine.layout.split != nil, keys == .split || keys == .splitColumns, "\(keys)")
        return (view, target, adapter)
    }

    private func swipe(_ word: String, on view: FullKeyboardView) async throws {
        let engine = view.engine
        let swipe = try XCTUnwrap(view.plane.swipe)
        let centres = try word.map { letter -> CGPoint in
            let key = try XCTUnwrap(engine.layout.key(.character(String(letter))))
            return CGPoint(x: key.frame.midX, y: key.frame.midY)
        }
        var path: [CGPoint] = [centres[0]]
        for (from, to) in zip(centres, centres.dropFirst()) {
            for step in 1...6 {
                let t = CGFloat(step) / 6
                path.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        var time: TimeInterval = 0
        engine.touchBegan(id: 1, at: path[0])
        swipe.began(id: 1, at: path[0], time: time)
        for point in path.dropFirst().dropLast() {
            time += 0.016
            if !swipe.moved(id: 1, to: point, time: time) { engine.touchMoved(id: 1, to: point) }
        }
        time += 0.016
        swipe.ended(id: 1, at: path[path.count - 1], time: time)
        await swipe.typrDecoding?.value
    }

    private func nearest(_ point: SwipePoint, in layout: SwipeLayout) -> Character {
        let letters = (0..<26).map { Character(UnicodeScalar(UInt8(97 + $0))) }
        let x = (point.x - Double(layout.frame.minX)) / Double(layout.frame.width)
        let y = (point.y - Double(layout.frame.minY)) / Double(layout.frame.height)
        let index = layout.centers.indices.min { a, b in
            hypot(layout.centers[a].x - x, layout.centers[a].y - y) < hypot(layout.centers[b].x - x, layout.centers[b].y - y)
        }!
        return letters[index]
    }

    func testASwipeOnEveryLayoutReachesTyprsRecogniserOnTheSameKeys() async throws {
        for keys in Keys.allCases {
            let requests = Recorded<SwipeRequest>()
            let (view, target, _) = makeView(keys, decoding: { request in
                await requests.append(request)
                return [.init(word: "hello", score: 1, language: .english)]
            })
            XCTAssertNotNil(view.plane.swipe?.typrDecode, "\(keys)")
            try await swipe("hello", on: view)
            let recorded = await requests.all
            let request = try XCTUnwrap(recorded.first, "\(keys)")
            XCTAssertEqual(nearest(request.path[0], in: request.layout), "h", "\(keys)")
            XCTAssertEqual(nearest(request.path[request.path.count - 1], in: request.layout), "o", "\(keys)")
            XCTAssertEqual(target.text, "hello", "\(keys)")
        }
    }

    func testOffHexSwipesAndTyprsModelIsNeverLoaded() async throws {
        let loads = Counter()
        let recognizer = SwipeRecognizer(loadEncoder: {
            loads.increment()
            return nil
        })
        let (off, _, _) = makeView(typrSwipe: false, decoding: { await recognizer.decode($0) })
        XCTAssertNotNil(off.plane.swipe, "Hex's own swipe typing")
        XCTAssertNil(off.plane.swipe?.typrDecode)
        try await swipe("hello", on: off)
        XCTAssertEqual(loads.count, 0)

        let (on, _, _) = makeView(typrSwipe: true, decoding: { await recognizer.decode($0) })
        try await swipe("hello", on: on)
        XCTAssertEqual(loads.count, 1, "the model loads on the first Typr swipe")
    }

    func testGermanSwipesOnlyWithTyprSwipeTyping() {
        LanguageSettings(defaults: defaults).keyboardLanguages = [.german]
        let (hexOnly, _, _) = makeView(typrSwipe: false, decoding: { _ in [] })
        XCTAssertEqual(hexOnly.engine.language, .german)
        XCTAssertNil(hexOnly.plane.swipe, "Hex leaves German out of swipe typing")
        let (typr, _, _) = makeView(typrSwipe: true, decoding: { _ in [] })
        XCTAssertNotNil(typr.plane.swipe?.typrDecode)
    }

    func testNoTyprSwipeOutsideAutocorrectedTextFields() async throws {
        let requests = Recorded<SwipeRequest>()
        let (view, target, adapter) = makeView(decoding: { request in
            await requests.append(request)
            return [.init(word: "hello", score: 1, language: .english)]
        }, configure: { $0.autocorrectionType = .no })
        let keys = view.engine.swipeKeys
        let words = await adapter.swipeWords([.zero, CGPoint(x: 10, y: 0)], times: [0, 0.1], keys: keys,
                                             keySize: CGSize(width: 30, height: 40), before: "")
        XCTAssertTrue(words.isEmpty)
        let none = await requests.all
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(target.text, "")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private actor Recorded<Value: Sendable> {
    private(set) var all: [Value] = []
    func append(_ value: Value) { all.append(value) }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    init(valid: Set<String>) { self.valid = valid }
    func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
    func guesses(for word: String) -> [String] { [] }
    func completions(for prefix: String) -> [String] { [] }
}
