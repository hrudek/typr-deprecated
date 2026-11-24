import UIKit
import XCTest
@testable import Typr

@MainActor
final class TyprNextWordTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var runningSystemMajorVersion = 0

    override func setUp() async throws {
        runningSystemMajorVersion = KeyboardLanguage.systemMajorVersion
        KeyboardLanguage.systemMajorVersion = 27
        suiteName = "TyprNextWordTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        KeyboardLanguage.systemMajorVersion = runningSystemMajorVersion
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeAdapter() -> TyprAutocorrectAdapter {
        TyprAutocorrectAdapter(engine: TyprAutocorrectEngine(
            checker: Checker(valid: ["hello", "world"]),
            learning: KeyboardLearningSession(defaults: defaults), spatialDecoder: nil,
            contextResources: .init(model: BundledKeyboardData.contextModel)))
    }

    private func makeKeyboard(_ provider: FakeProvider,
                              configure: (HexFixtureTextTarget) -> Void = { _ in })
        -> (FullKeyboardEngine, TyprAutocorrectAdapter) {
        let adapter = makeAdapter()
        adapter.cloudPredictions = provider
        adapter.hasCloudKey = { true }
        adapter.syncPredictions()
        let target = HexFixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        configure(target)
        let engine = FullKeyboardEngine(target: target, autocorrect: adapter)
        engine.width = 393
        engine.configureForField()
        return (engine, adapter)
    }

    private func type(_ text: String, on engine: FullKeyboardEngine) throws {
        for character in text {
            if character == " " {
                let key = try XCTUnwrap(engine.layout.key(.space))
                let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
                engine.touchBegan(id: 1, at: point)
                engine.touchEnded(id: 1, at: point)
            } else {
                let key = engine.layout.key(.character(String(character)))
                engine.insert(String(character), source: nil, at: key.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) })
            }
        }
    }

    private func arrival(on adapter: TyprAutocorrectAdapter) -> XCTestExpectation {
        let arrived = expectation(description: "late prediction")
        let refresh = adapter.onLateSuggestions
        adapter.onLateSuggestions = {
            refresh?()
            arrived.fulfill()
        }
        return arrived
    }

    func testALateAnswerReachesHexsStripForItsContext() async throws {
        let provider = FakeProvider { $0 == "hello " ? ["wonderful"] : nil }
        let (engine, adapter) = makeKeyboard(provider)
        XCTAssertEqual(adapter.predictionSource, .cloud)
        let arrived = arrival(on: adapter)
        try type("hello ", on: engine)
        await fulfillment(of: [arrived], timeout: 5)
        XCTAssertTrue(engine.suggestions.contains { $0.replacement == "wonderful" && $0.kind == .nextWord })
        XCTAssertEqual(provider.contexts, ["hello "])
    }

    func testAnAnswerForAnEarlierContextNeverShows() async throws {
        let provider = FakeProvider { $0 == "hello " ? ["wonderful"] : nil }
        let (engine, adapter) = makeKeyboard(provider)
        let arrived = arrival(on: adapter)
        try type("hello ", on: engine)
        await fulfillment(of: [arrived], timeout: 5)
        let cancelled = expectation(description: "the request for the old context is cancelled")
        provider.onCancel = { if $0 == "hello world " { cancelled.fulfill() } }
        try type("world ", on: engine)
        XCTAssertFalse(engine.suggestions.contains { $0.replacement == "wonderful" }, "an answer for \"hello\" only")
        try type("x", on: engine)
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertFalse(engine.suggestions.contains { $0.replacement == "wonderful" })
    }

    func testANextWordStartsASentenceWithACapitalWhereHexWouldCapitalise() async throws {
        let provider = FakeProvider { $0 == "Hello. " ? ["wonderful"] : nil }
        let (engine, adapter) = makeKeyboard(provider) { $0.autocapitalizationType = .sentences }
        let arrived = arrival(on: adapter)
        engine.insert("Hello.", source: nil)
        try type(" ", on: engine)
        await fulfillment(of: [arrived], timeout: 5)
        XCTAssertTrue(engine.suggestions.contains { $0.replacement == "Wonderful" && $0.kind == .nextWord })
    }

    func testNoRequestWhereTyprKeyboardWouldNotPredict() throws {
        let gated: [(String, (HexFixtureTextTarget) -> Void)] = [
            ("secure", { $0.isSecureTextEntry = true }),
            ("URL", { $0.keyboardType = .URL }),
            ("email", { $0.keyboardType = .emailAddress }),
            ("autocorrect off", { $0.autocorrectionType = .no }),
            ("inline predictions off", { $0.inlinePredictionType = .no }),
            ("numbers and punctuation", { $0.keyboardType = .numbersAndPunctuation }),
        ]
        let (allowed, allowedAdapter) = makeKeyboard(FakeProvider { _ in nil })
        try type("hello ", on: allowed)
        XCTAssertEqual(allowedAdapter.predictions?.isActive, true, "an ordinary text field asks")
        for (name, configure) in gated {
            let provider = FakeProvider { _ in nil }
            let (engine, adapter) = makeKeyboard(provider, configure: configure)
            try type("hello ", on: engine)
            XCTAssertEqual(adapter.predictions?.isActive, false, name)
            XCTAssertTrue(provider.contexts.isEmpty, name)
        }
    }

    func testTheProviderFollowsTyprsSettings() {
        let onDevice = FakeModel()
        let adapter = makeAdapter()
        adapter.onDeviceModel = onDevice
        adapter.cloudPredictions = FakeProvider { _ in nil }
        adapter.hasCloudKey = { true }
        adapter.syncPredictions()
        XCTAssertEqual(adapter.predictionSource, .cloud, "your Anthropic key, with Full Access")
        adapter.hasCloudKey = { false }
        adapter.syncPredictions()
        XCTAssertEqual(adapter.predictionSource, .onDevice, "no key: the on-device model")
        adapter.cloudPredictions = nil
        adapter.hasCloudKey = { true }
        adapter.syncPredictions()
        XCTAssertEqual(adapter.predictionSource, .onDevice, "no Full Access: never the cloud")
        onDevice.isAvailable = false
        adapter.syncPredictions()
        XCTAssertNil(adapter.predictionSource)
        XCTAssertNil(adapter.predictions)
    }
}

private final class FakeProvider: ModelPredictionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let answer: @Sendable (String) -> [String]?
    private var recorded: [String] = []
    private var cancelHandler: (@MainActor @Sendable (String) -> Void)?

    init(answer: @escaping @Sendable (String) -> [String]?) { self.answer = answer }

    var contexts: [String] { lock.withLock { recorded } }
    var onCancel: (@MainActor @Sendable (String) -> Void)? {
        get { lock.withLock { cancelHandler } }
        set { lock.withLock { cancelHandler = newValue } }
    }

    func predictions(for request: ModelPredictionRequest) async throws -> [String] {
        lock.withLock { recorded.append(request.context) }
        if let words = answer(request.context) { return words }
        let handler = onCancel
        await withTaskCancellationHandler {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            for await _ in stream {}
            continuation.finish()
        } onCancel: {
            Task { @MainActor in handler?(request.context) }
        }
        throw CancellationError()
    }
}

private final class FakeModel: OnDeviceNextWordModel, @unchecked Sendable {
    var isAvailable = true
    func supports(_ language: SpatialWordDecoder.Language) -> Bool { true }
    func prewarm() {}
    func nextWords(after context: String) async throws -> [String] { [] }
}

private final class Checker: TyprTextChecking {
    let valid: Set<String>
    init(valid: Set<String>) { self.valid = valid }
    func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
    func guesses(for word: String) -> [String] { [] }
    func completions(for prefix: String) -> [String] { [] }
}
