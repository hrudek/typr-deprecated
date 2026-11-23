import Foundation
import XCTest
@testable import Typr

/// Hex's multilingual model tests (HEXMobileTests `DictationControllerTests`, Experiments ›
/// Multilingual model), with Typr's language rule: the one set, else the iPhone's first.
@MainActor
final class MultilingualParakeetTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "typr.tests.multilingual.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }


    /// 6 GB and 4 GB iPhones report about this much.
    private static let sixGB: UInt64 = 5_900_000_000
    private static let fourGB: UInt64 = 3_700_000_000

    func testMultilingualParakeetIsOffByDefaultAndPicksNothing() {
        let settings = MultilingualParakeetSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertNil(settings.language(set: "nl-NL", preferred: ["nl-NL"], physicalMemory: Self.sixGB))
        XCTAssertNil(
            ParakeetUltraTranscriber.chosenLanguage(language: settings.language(), availableMemory: 0, setAside: false),
            "off, Typr keeps the engine it uses without it"
        )
    }

    func testMultilingualParakeetTakesItsLanguagesOnIPhonesWithRoom() {
        let settings = MultilingualParakeetSettings(defaults: defaults)
        settings.isEnabled = true
        func language(set: String? = nil, preferred: [String] = ["en-US"], memory: UInt64 = Self.sixGB) -> String? {
            settings.language(set: set, preferred: preferred, physicalMemory: memory)
        }
        XCTAssertEqual(language(set: "nl-NL"), "nl-NL")
        XCTAssertEqual(language(set: "de-DE", preferred: ["en-US"]), "de-DE", "the language set wins over the iPhone's")
        XCTAssertEqual(language(preferred: ["en-NL", "nl-NL"]), "en-NL", "else the iPhone's first language")
        XCTAssertNil(language(set: "ja-JP"), "a language it doesn't know stays with Apple Speech")
        XCTAssertNil(language(set: "hi-IN"))
        XCTAssertNil(language(preferred: ["ja-JP", "en-US"]), "Automatic doesn't skip the iPhone's first language")
        XCTAssertNil(language(set: "nl-NL", memory: Self.fourGB), "4 GB iPhones can't load it")

        XCTAssertEqual(ParakeetUltraTranscriber.chosenLanguage(language: "nl-NL", availableMemory: 2_500 << 20, setAside: false), "nl-NL")
        XCTAssertEqual(ParakeetUltraTranscriber.chosenLanguage(language: "nl-NL", availableMemory: 0, setAside: false), "nl-NL", "no limit (simulator)")
        XCTAssertNil(ParakeetUltraTranscriber.chosenLanguage(language: "nl-NL", availableMemory: 900 << 20, setAside: false), "too little left")
        XCTAssertNil(ParakeetUltraTranscriber.chosenLanguage(language: "nl-NL", availableMemory: 0, setAside: true), "a load ended Typr")
    }

    func testAMultilingualParakeetLoadThatEndedTyprIsKeptApartFromV2s() {
        let ultra = ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel, defaults: defaults)
        for _ in 0..<2 {
            ultra.begin()
            ultra.noteLaunch()
        }
        let v2 = ParakeetLoadGuard(defaults: defaults)
        v2.noteLaunch()
        XCTAssertFalse(v2.lastLoadWasInterrupted)
        XCTAssertTrue(ultra.lastLoadWasInterrupted)
        ultra.forget()
        XCTAssertFalse(ultra.lastLoadWasInterrupted, "turning the experiment on again tries again")
        XCTAssertFalse(ParakeetCompileRecord(key: ParakeetUltraTranscriber.compileRecordKey, defaults: defaults).isCurrent)
    }

    func testMultilingualParakeetNeverTakesDictationUntilItIsReady() {
        let step = DictationController.multilingualStep
        XCTAssertEqual(step(nil, true, true), .none, "off, another language, or set aside")
        XCTAssertEqual(step("nl-NL", false, false), .download, "the usual engine dictates while it downloads")
        XCTAssertEqual(step("nl-NL", false, true), .download)
        XCTAssertEqual(step("nl-NL", true, false), .loadBeside, "a first load compiles beside the usual engine")
        XCTAssertEqual(step("nl-NL", true, true), .dictate)
        XCTAssertEqual(
            ParakeetPreparationProgress(downloads: true, compiledBefore: false).downloadDetail,
            "Downloading the speech model",
            "V2's words are unchanged"
        )
    }

    func testTheKeyboardOpensTyprForMultilingualParakeetOnlyOnceItIsReady() {
        let settings = MultilingualParakeetSettings(defaults: defaults)
        XCTAssertFalse(settings.keyboardOpensTypr(language: "nl-NL"), "off")
        settings.isEnabled = true
        XCTAssertFalse(settings.keyboardOpensTypr(language: "nl-NL"), "on, still downloading: the keyboard dictates itself")
        settings.isModelReady = true
        XCTAssertTrue(settings.keyboardOpensTypr(language: "nl-NL"))
        XCTAssertFalse(settings.keyboardOpensTypr(language: nil), "a language it doesn't take")
        settings.isEnabled = false
        XCTAssertFalse(settings.keyboardOpensTypr(language: "nl-NL"))
    }

    func testChoosingASpeechEngineStopsTheKeyboardFromOpeningTyprForUltra() {
        let settings = MultilingualParakeetSettings(defaults: defaults)
        let typr = TyprSettings(defaults: defaults)
        settings.isEnabled = true
        settings.isModelReady = true
        XCTAssertTrue(settings.keyboardOpensTypr(language: "nl-NL"))

        typr.preferredSpeechEngine = .orukeet

        XCTAssertFalse(settings.keyboardOpensTypr(language: "nl-NL"))
    }

    func testOnlyASwitchTurnedOffDeletesTheMultilingualModelAtLaunch() {
        let settings = MultilingualParakeetSettings(defaults: defaults)
        XCTAssertFalse(settings.isTurnedOff, "never set: nothing to delete")
        settings.isEnabled = true
        XCTAssertFalse(settings.isTurnedOff)
        settings.isEnabled = false
        XCTAssertTrue(settings.isTurnedOff)
        XCTAssertFalse(
            MultilingualParakeetSettings(defaults: nil).isTurnedOff,
            "an App Group Typr can't read says nothing about the switch"
        )
    }

    func testTheMultilingualDownloadResumesFromItsPartialFileAndSaysItsBytes() async throws {
        let model = try UltraStubModel()
        defer { model.remove() }
        let first = model.files[0]
        let partial = model.folder.appendingPathComponent(first.path).appendingPathExtension("partial")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try model.bodies[first.path]!.prefix(1000).write(to: partial)
        XCTAssertEqual(ParakeetUltraModel.bytesOnDisk(in: model.folder, files: model.files), 1000)

        let download = model.download()
        download.start()
        if case .downloading(let bytes) = download.state {
            XCTAssertEqual(bytes, 1000, "picks up from what's on disk")
        } else {
            XCTFail("\(download.state)")
        }
        XCTAssertEqual(download.status, "Downloading the multilingual model: 1\u{00A0}KB of 5\u{00A0}KB")
        try await waitUntil { download.state == .loading }

        XCTAssertTrue(ParakeetUltraModel.isDownloaded(in: model.folder, files: model.files))
        XCTAssertEqual(UltraStubProtocol.requested.first ?? nil, "bytes=1000-", "resumed with a range")
    }

    func testAMultilingualDownloadThatDropsOrStallsTriesAgainFromWhereItWas() async throws {
        let model = try UltraStubModel()
        defer { model.remove() }
        UltraStubProtocol.script([.cut(1200), .hang(800), .serve])
        let download = model.download()
        var finished = 0
        download.onDownloaded = { finished += 1 }
        download.start()
        try await waitUntil(seconds: 10) { download.state == .loading }

        XCTAssertEqual(finished, 1)
        XCTAssertTrue(ParakeetUltraModel.isDownloaded(in: model.folder, files: model.files))
        XCTAssertEqual(
            Array(UltraStubProtocol.requested.prefix(3)),
            [nil, "bytes=1200-", "bytes=2000-"],
            "a dropped connection and a stalled one each pick up from the partial file"
        )
    }

    func testAMultilingualDownloadThatKeepsMovingNeverRunsOutOfTries() async throws {
        let model = try UltraStubModel()
        defer { model.remove() }
        UltraStubProtocol.script(Array(repeating: .cut(400), count: ParakeetUltraDownload.automaticTries + 1))
        let download = model.download()
        download.start()
        try await waitUntil(seconds: 10) { download.state == .loading || download.isFailed }
        XCTAssertEqual(download.state, .loading, "each drop came after more bytes, so it kept going")
        XCTAssertTrue(ParakeetUltraModel.isDownloaded(in: model.folder, files: model.files))
    }

    func testAMultilingualDownloadThatKeepsFailingSaysWhatHappened() async throws {
        let model = try UltraStubModel()
        defer { model.remove() }
        UltraStubProtocol.script(Array(repeating: .status(503), count: 10))
        let download = model.download()
        download.start()
        try await waitUntil { download.isFailed }
        XCTAssertEqual(UltraStubProtocol.requested.count, ParakeetUltraDownload.automaticTries)
        XCTAssertEqual(download.status, "The multilingual model didn't download (error 503). Try again later.")

        UltraStubProtocol.script([.status(404)])
        download.restart()
        try await waitUntil { download.isFailed }
        XCTAssertEqual(UltraStubProtocol.requested.count, 1, "a refused request isn't tried again by itself")

        XCTAssertEqual(
            ParakeetUltraDownload.message(for: URLError(.notConnectedToInternet)),
            "The multilingual model's download stopped. Check your connection and try again."
        )
        XCTAssertTrue(ParakeetUltraDownload.message(for: CocoaError(.fileWriteOutOfSpace)).contains("free space"))
        XCTAssertEqual(ParakeetUltraDownload.backoff(1), 2)
        XCTAssertEqual(ParakeetUltraDownload.backoff(4), 16)
        XCTAssertEqual(ParakeetUltraDownload.backoff(9), 30)
    }

    func testTurningTheMultilingualModelOffStopsItsDownloadBeforeItIsDeleted() async throws {
        let model = try UltraStubModel()
        defer { model.remove() }
        UltraStubProtocol.script([.hang(800)])
        let download = model.download(stallLimit: .seconds(30))
        download.start()
        try await waitUntil { ParakeetUltraModel.bytesOnDisk(in: model.folder, files: model.files) == 800 }

        await download.cancel()?.value
        XCTAssertEqual(download.state, .idle)
        ParakeetUltraModel.remove(from: model.folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.folder.path), "nothing wrote after stop")
    }

    func testAForegroundRestartWaitsForThePreviousWriter() async throws {
        let writer = GatedUltraWriter()
        let download = ParakeetUltraDownload(fetch: { _ in await writer.write() })
        download.start()
        try await waitForState("first writer started") { writer.events == [.started] }

        download.appMovedToBackground()
        download.appBecameActive(canRetry: true, now: Date().addingTimeInterval(26))
        await mainActorBarrier()
        XCTAssertEqual(writer.events, [.started])
        writer.release()
        try await waitForState("replacement finished") { download.state == .loading }

        XCTAssertEqual(writer.events, [.started, .finished, .started, .finished])
    }

    func testCancellingAQueuedRestartDrainsTheOriginalWriter() async throws {
        let writer = GatedUltraWriter()
        let download = ParakeetUltraDownload(fetch: { _ in await writer.write() })
        download.start()
        try await waitForState("first writer started") { writer.events == [.started] }

        download.restart()
        let drain = try XCTUnwrap(download.cancel())
        let deletion = Task {
            await drain.value
            writer.events.append(.deleted)
        }
        await mainActorBarrier()
        XCTAssertEqual(writer.events, [.started])
        writer.release()
        await deletion.value

        XCTAssertEqual(writer.events, [.started, .finished, .deleted])
        XCTAssertEqual(download.state, .idle)
    }

    func testForegroundDropsPausedRetriesWhenUltraIsIneligible() async throws {
        let download = ParakeetUltraDownload(backoff: { _ in 30 }, fetch: { _ in
            throw URLError(.networkConnectionLost)
        })
        download.start()
        try await waitForState("download retry is waiting") {
            if case .waiting = download.state { return true }
            return false
        }

        download.appBecameActive(canRetry: false)
        XCTAssertEqual(download.state, .idle)
        XCTAssertFalse(download.isRunning)
        await download.cancel()?.value
    }

    func testParakeetUltrasFilesArePinnedAndComplete() throws {
        let files = ParakeetUltraModel.files
        XCTAssertEqual(Set(files.map(\.path)).count, files.count)
        for model in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            XCTAssertTrue(files.contains { $0.path == "\(model).mlmodelc/weights/weight.bin" }, model)
            XCTAssertTrue(files.contains { $0.path == "\(model).mlmodelc/model.mil" }, model)
        }
        XCTAssertTrue(files.allSatisfy { $0.sha256.count == 64 })
        XCTAssertEqual(ParakeetUltraModel.totalBytes, 632_162_964)
        for file in files {
            XCTAssertTrue(ParakeetUltraModel.url(for: file).absoluteString.contains("/resolve/\(ParakeetUltraModel.revision)/"))
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertFalse(ParakeetUltraModel.isDownloaded(in: folder))
        let vocabulary = folder.appendingPathComponent("vocab.json")
        try Data(#"{"0": "<unk>", "8191": "▁ja"}"#.utf8).write(to: vocabulary)
        XCTAssertEqual(try ParakeetUltraModel.vocabulary(at: vocabulary), [0: "<unk>", 8191: "▁ja"])
        XCTAssertEqual(
            try ParakeetUltraModel.sha256(of: vocabulary),
            "ec2185c71d79a203174eba2b46e5d20431bdc1d0f275735d1f22f284d1759b24"
        )
    }

    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class GatedUltraWriter {
    enum Event: Equatable { case started, finished, deleted }

    var events: [Event] = []
    private var gate: CheckedContinuation<Void, Never>?

    func write() async {
        events.append(.started)
        if events.count == 1 {
            await withCheckedContinuation { gate = $0 }
        }
        events.append(.finished)
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// Two small files standing in for Parakeet Ultra's, served by `UltraStubProtocol`.
@MainActor
private struct UltraStubModel {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ultra-\(UUID().uuidString)")
    let bodies: [String: Data]
    let files: [ParakeetUltraModel.File]

    init() throws {
        var bodies: [String: Data] = [:]
        var files: [ParakeetUltraModel.File] = []
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for (path, size) in [("Encoder.mlmodelc/weights/weight.bin", 3000), ("parakeet_vocab.json", 2000)] {
            let body = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ path.count) })
            try body.write(to: scratch)
            bodies[path] = body
            files.append(.init(path: path, size: Int64(size), sha256: try ParakeetUltraModel.sha256(of: scratch)))
        }
        self.bodies = bodies
        self.files = files
        UltraStubProtocol.reset(bodies: bodies)
    }

    func download(stallLimit: Duration = .seconds(1)) -> ParakeetUltraDownload {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UltraStubProtocol.self]
        return ParakeetUltraDownload(
            directory: folder,
            files: files,
            base: "https://stub.invalid/model",
            session: URLSession(configuration: configuration),
            stallLimit: stallLimit,
            backoff: { _ in 0 }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Serves `UltraStubModel`'s files with ranges, following a script for its next requests:
/// cut the connection after some bytes, send some and then nothing, or answer a status.
private final class UltraStubProtocol: URLProtocol, @unchecked Sendable {
    enum Step: Sendable {
        case serve
        case cut(Int)
        case hang(Int)
        case status(Int)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String: Data] = [:]
    nonisolated(unsafe) private static var steps: [Step] = []
    nonisolated(unsafe) private static var ranges: [String?] = []

    static func reset(bodies: [String: Data]) {
        lock.withLock {
            self.bodies = bodies
            steps = []
            ranges = []
        }
    }

    static func script(_ steps: [Step]) {
        lock.withLock {
            self.steps = steps
            ranges = []
        }
    }

    /// Each request's Range header, in order.
    static var requested: [String?] {
        lock.withLock { ranges }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let range = request.value(forHTTPHeaderField: "Range")
        let path = url.path.replacingOccurrences(of: "/model/", with: "")
        let (step, body): (Step, Data?) = Self.lock.withLock {
            Self.ranges.append(range)
            let step = Self.steps.isEmpty ? .serve : Self.steps.removeFirst()
            return (step, Self.bodies[path])
        }
        guard let body else {
            respond(404, url: url)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if case .status(let status) = step {
            respond(status, url: url)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let offset = range.flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
        respond(offset > 0 ? 206 : 200, url: url)
        let rest = body.dropFirst(offset)
        switch step {
        case .cut(let count):
            client?.urlProtocol(self, didLoad: Data(rest.prefix(count)))
            // The connection drops a moment after the bytes arrive, as on a network.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
        case .hang(let count):
            client?.urlProtocol(self, didLoad: Data(rest.prefix(count)))
        case .serve, .status:
            client?.urlProtocol(self, didLoad: Data(rest))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private func respond(_ status: Int, url: URL) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}
