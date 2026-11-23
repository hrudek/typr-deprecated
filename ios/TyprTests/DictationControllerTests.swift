import XCTest
@testable import Typr

@MainActor
private final class FakeAudioCapture: ActiveAudioCapture {
    let url: URL
    var isRecording = true
    var currentTime: TimeInterval
    var power: Float = 0.6
    var didFailWriting = false

    init(url: URL, initialDuration: TimeInterval = 1.2) {
        self.url = url
        self.currentTime = initialDuration
        FileManager.default.createFile(atPath: url.path, contents: Data("wav".utf8))
    }

    func normalizedPowerLevel() -> Float {
        power
    }

    func stop() {
        isRecording = false
    }
}

@MainActor
private final class FakeArmedCapture: ArmedAudioCapture {
    var isRecording = true
    var committedTo: URL?
    let duration: TimeInterval
    let onCommit: (FakeAudioCapture) -> Void

    init(duration: TimeInterval, onCommit: @escaping (FakeAudioCapture) -> Void) {
        self.duration = duration
        self.onCommit = onCommit
    }

    func commit(to url: URL) throws -> any ActiveAudioCapture {
        committedTo = url
        isRecording = false
        let capture = FakeAudioCapture(url: url, initialDuration: duration)
        onCommit(capture)
        return capture
    }

    func stop() {
        isRecording = false
    }
}

@MainActor
private final class FakeAudioManager: AudioManaging {
    var isKeepaliveRunning = false
    var isOtherAudioPlaying = false
    var permissionGranted = true
    var keepaliveShouldThrow = false
    /// False models Typr in the background: iOS refuses to start microphone input there,
    /// though input that is already running keeps going.
    var canStartInput = true
    /// Activations iOS refuses before one succeeds, as right after another app's audio ends.
    var busyActivationsRemaining = 0
    var captureShouldThrow = false
    static let busyError = NSError(domain: NSOSStatusErrorDomain, code: 0x2170_6C61) // '!pla'
    var startKeepaliveCount = 0
    var nextCaptureDuration: TimeInterval = 1.4
    var nextCaptureIsRecording = true
    var deactivateCount = 0
    var createdCaptures: [FakeAudioCapture] = []
    var armedCaptures: [FakeArmedCapture] = []
    var keepaliveMicrophones: [MicrophoneChoice] = []
    var captureMicrophones: [MicrophoneChoice] = []
    var keepaliveInputIsStale = false
    /// Hex's session mixes; Typr exclusive audio session interrupts playing media.
    var mixesWithOtherAudio = true
    /// A headset or CarPlay microphone that Automatic records from instead of the iPhone's.
    var externalMicrophone = false
    var keepaliveStopsRightAway = false

    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?

    func requestPermission() async -> Bool {
        permissionGranted
    }

    func startKeepalive(microphone: MicrophoneChoice) throws {
        startKeepaliveCount += 1
        keepaliveMicrophones.append(microphone)
        if busyActivationsRemaining > 0 {
            busyActivationsRemaining -= 1
            isKeepaliveRunning = false
            throw Self.busyError
        }
        if keepaliveShouldThrow || !canStartInput {
            isKeepaliveRunning = false
            throw CocoaError(.coderInvalidValue)
        }
        isKeepaliveRunning = !keepaliveStopsRightAway
        keepaliveInputIsStale = false
        // Activating input interrupts media, so subsequent queries no longer see it.
        isOtherAudioPlaying = isOtherAudioPlaying && mixesWithOtherAudio
    }

    func keepaliveFollows(_ microphone: MicrophoneChoice) -> Bool {
        isKeepaliveRunning && !keepaliveInputIsStale && keepaliveMicrophones.last.map { sharesInput($0, microphone) } == true
    }

    /// Without an external microphone, Automatic and iPhone both record from the iPhone's.
    private func sharesInput(_ one: MicrophoneChoice, _ other: MicrophoneChoice) -> Bool {
        one == other || (!externalMicrophone && Set([one, other]).isSubset(of: [.automatic, .iPhone]))
    }

    func ensureKeepalive(microphone: MicrophoneChoice) throws {
        if isKeepaliveRunning, keepaliveMicrophones.last == microphone || keepaliveFollows(microphone) { return }
        try startKeepalive(microphone: microphone)
    }

    func stopKeepalive() {
        isKeepaliveRunning = false
    }

    func deactivateSession() {
        isKeepaliveRunning = false
        deactivateCount += 1
    }

    func beginCapture(
        at url: URL,
        maxDuration: TimeInterval,
        microphone: MicrophoneChoice
    ) throws -> any ActiveAudioCapture {
        // Captures record from the keepalive input, starting it when it isn't running.
        try ensureKeepalive(microphone: microphone)
        captureMicrophones.append(microphone)
        if captureShouldThrow {
            throw CocoaError(.fileWriteUnknown)
        }
        let capture = FakeAudioCapture(url: url, initialDuration: nextCaptureDuration)
        capture.isRecording = nextCaptureIsRecording
        createdCaptures.append(capture)
        return capture
    }

    func beginArmedCapture(maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ArmedAudioCapture {
        try ensureKeepalive(microphone: microphone)
        let armed = FakeArmedCapture(duration: nextCaptureDuration) { [weak self] in self?.createdCaptures.append($0) }
        armedCaptures.append(armed)
        return armed
    }
}

private actor ControlledTranscriber: LocalTranscribing {
    nonisolated let displayName = "Controlled Speech"
    let languageName = "English"

    private var gate: CheckedContinuation<String, Error>?
    private var pendingResume: String?
    private var cannedOutput = "ship the build"
    private(set) var transcribedURLs: [URL] = []
    private(set) var vocabularyArguments: [[String]] = []
    private var suspendNext = false
    private var suspendPrepare = false
    private var prepareGate: CheckedContinuation<Void, Never>?

    func armSuspension() {
        suspendNext = true
        pendingResume = nil
    }

    func setCannedOutput(_ text: String) {
        cannedOutput = text
    }

    /// True once a transcription waits on the gate. Deliberately ignores task cancellation:
    /// a stale job's late result must reach the controller's generation fence.
    func isWaiting() -> Bool { gate != nil }

    func resumeSuspended(with text: String) {
        if let continuation = gate {
            gate = nil
            continuation.resume(returning: text)
        } else {
            pendingResume = text
        }
    }

    func armPrepareSuspension() {
        suspendPrepare = true
    }

    func isPreparing() -> Bool { prepareGate != nil }

    func resumePrepare() {
        suspendPrepare = false
        prepareGate?.resume()
        prepareGate = nil
    }

    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {
        if suspendPrepare {
            suspendPrepare = false
            await withCheckedContinuation { prepareGate = $0 }
        }
        progressHandler(ModelPreparationProgress(fractionCompleted: 1, detail: "Ready"))
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        transcribedURLs.append(audioURL)
        if suspendNext {
            suspendNext = false
            if let early = pendingResume {
                pendingResume = nil
                return early
            }
            return try await withCheckedThrowingContinuation { continuation in
                gate = continuation
            }
        }
        return cannedOutput
    }

    func transcribe(_ audioURL: URL, vocabulary: [String]) async throws -> String {
        vocabularyArguments.append(vocabulary)
        return try await transcribe(audioURL)
    }
}

@MainActor
private final class ClockReads {
    private(set) var count = 0

    func read() -> TimeInterval {
        count += 1
        return Date().timeIntervalSince1970
    }
}

@MainActor
private final class RecordingLiveActivity: LiveActivityPresenting {
    enum Event: Equatable { case start, transcribing, copied, end }
    private(set) var events: [Event] = []
    private var showing = false

    func startRecording(startedAt: Date) {
        showing = true
        events.append(.start)
    }

    func markTranscribing(startedAt: Date) {
        if showing { events.append(.transcribing) }
    }

    func finishCopied() {
        if showing { events.append(.copied) }
        showing = false
    }

    func endImmediately() {
        showing = false
        events.append(.end)
    }
}

@MainActor
final class DictationControllerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var controllers: [DictationController] = []

    override func setUp() async throws {
        suiteName = "typr.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        // End the warm loop and any resume retry, cancel the job and wait for its unwind.
        for controller in controllers {
            controller.endWarmSession()
            controller.cancelCurrentJob()
        }
        let controllers = controllers
        self.controllers = []
        try await waitForState("controllers idle before defaults removal") {
            controllers.allSatisfy { $0.isIdleForTest }
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStaleTranscriptionAfterSessionEndCannotClobberNewerCaptureOrDeleteItsFile() async throws {
        let now = 1_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)

        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        XCTAssertEqual(controller.phase, .ready)

        // Start Job A and suspend its transcription in-flight.
        await transcriber.armSuspension()
        controller.toggleWarmSession()
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled)

        bridge.send(.start, jobID: "job-a", style: .polished, sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        let firstCaptureURL = try XCTUnwrap(audio.createdCaptures.first?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstCaptureURL.path))

        controller.finishRecording()
        XCTAssertEqual(controller.phase, .transcribing)
        try await asrSuspended(transcriber)

        // Expire / end the warm session while Job A is still transcribing, then start a new capture Job B!
        controller.endWarmSession()
        XCTAssertFalse(controller.keyboardSessionEnabled)

        controller.startRecording(keyboardJobID: "job-b")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        let secondCaptureURL = try XCTUnwrap(audio.createdCaptures.last?.url)
        XCTAssertNotEqual(firstCaptureURL, secondCaptureURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondCaptureURL.path))

        // Complete stale Job A: it must clean up ONLY firstCaptureURL and leave Job B recording untouched!
        await transcriber.resumeSuspended(with: "stale transcript")
        // The stale task removes its own capture in its final `defer`, after the generation fence.
        try await waitForState("stale job A unwound") {
            !FileManager.default.fileExists(atPath: firstCaptureURL.path)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstCaptureURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondCaptureURL.path))
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(controller.transcript, "")

        controller.cancelCurrentJob()
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondCaptureURL.path))
    }

    func testAcceptedJobDeliversTranscriptEvenWhenWarmSessionCloses() async throws {
        let now = 2_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.armSuspension()
        let bridge = KeyboardBridge(defaults: defaults)

        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   hostReturner: HostReturner(openByBundleID: { _ in false }, openURL: { _ in false }))

        controller.setWarmDuration(.off)
        // Hex's Casual: no filler, a lowercase start and no final period on a short message.
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "one-shot-job", requestedAt: now, style: .casual, host: nil)
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)

        // Finishing capture in one-shot mode immediately releases the mic while transcription completes.
        controller.finishRecording()
        XCTAssertEqual(controller.phase, .transcribing)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        XCTAssertGreaterThan(audio.deactivateCount, 0)
        try await asrSuspended(transcriber)

        await transcriber.resumeSuspended(with: "Um, ship it tonight.")
        try await transcribed(controller)

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.transcript, "ship it tonight")
        let snap = bridge.snapshot()
        XCTAssertTrue(snap.hasDeliverableResult(at: now + 1))
        XCTAssertEqual(snap.transcript, "ship it tonight")
    }

    func testHexDefaultNeverOpensTheHostAfterAColdStart() async throws {
        let now = 4_000.0
        var opened: [String] = []
        let returner = HostReturner(openByBundleID: { id in opened.append(id); return true }, openURL: { _ in true })
        let controller = try await readyController(audio: FakeAudioManager(), now: { now }, hostReturner: returner)

        controller.handleKeyboardLaunch(
            .startRecording(jobID: "hex-job", requestedAt: now - 0.4, style: .polished, host: "com.openai.chat")
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(controller.autoReturnState, .swipeFallback)
        XCTAssertTrue(opened.isEmpty)
        controller.cancelCurrentJob()
    }

    func testTenSecondHandoffWindowAndAutoReturnBehavior() async throws {
        var now = 5_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        TyprSettings(defaults: defaults)[experiment: .typrAutomaticHostReturn] = true
        var openedBundleIDs: [String] = []
        var openedURLs: [URL] = []

        let returner = HostReturner(
            openByBundleID: { id in
                openedBundleIDs.append(id)
                return id == "com.openai.chat"
            },
            openURL: { url in
                openedURLs.append(url)
                return url.scheme == "ichat"
            }
        )
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   hostReturner: returner)

        // 1. Expired (>10s) handoff warms session without surprise-recording or returning.
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "expired-job", requestedAt: now - 11.5, style: .polished, host: "com.openai.chat")
        )
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotNil(controller.handoffNotice)
        XCTAssertTrue(openedBundleIDs.isEmpty)
        XCTAssertTrue(openedURLs.isEmpty)

        // 2. Fresh handoff starts recording and returns to the host by bundle ID first.
        now += 1
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "fresh-job", requestedAt: now - 0.4, style: .polished, host: "com.openai.chat")
        )
        try await activationSettled(controller)
        // The capture sets `.attempting`, then the return task opens the host off the main actor.
        try await waitForState("host opened by bundle ID") { openedBundleIDs.count == 1 }
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(openedBundleIDs, ["com.openai.chat"])
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertEqual(controller.autoReturnState, .attempting)
        controller.noteSceneDidEnterBackground()
        XCTAssertEqual(controller.autoReturnState, .succeeded)

        // 3. When opening by bundle ID fails, the host's own resuming URL is used.
        controller.cancelCurrentJob()
        now += 1
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "scheme-job", requestedAt: now - 0.2, style: .polished, host: "com.apple.MobileSMS")
        )
        try await activationSettled(controller)
        try await waitForState("bundle ID refused, then the scheme URL opened") { openedURLs.count == 1 }
        XCTAssertEqual(openedBundleIDs.last, "com.apple.MobileSMS")
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["ichat://"])
        XCTAssertEqual(controller.autoReturnState, .attempting)

        // 4. An app with neither way back falls back to the swipe cue.
        controller.cancelCurrentJob()
        now += 1
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "unknown-job", requestedAt: now - 0.2, style: .polished, host: "com.example.noscheme")
        )
        try await activationSettled(controller)
        // The launch reset the state to `.idle`; only this job's failed open sets the fallback.
        try await waitForState("return attempt fell back") { controller.autoReturnState == .swipeFallback }
        XCTAssertEqual(openedBundleIDs.last, "com.example.noscheme")
        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(controller.autoReturnState, .swipeFallback)

        // 5. A host the keyboard could not name gets the swipe cue without opening anything.
        controller.cancelCurrentJob()
        now += 1
        let opensBefore = openedBundleIDs.count
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "nameless-job", requestedAt: now - 0.2, style: .polished, host: nil)
        )
        try await activationSettled(controller)
        XCTAssertEqual(openedBundleIDs.count, opensBefore)
        XCTAssertEqual(controller.autoReturnState, .swipeFallback)

        // 6. A field inside Typr itself needs no return.
        controller.cancelCurrentJob()
        now += 1
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "self-job", requestedAt: now - 0.2, style: .polished, host: HostReturnCatalog.typrBundleID)
        )
        try await activationSettled(controller)
        XCTAssertEqual(openedBundleIDs.count, opensBefore)
        XCTAssertEqual(controller.autoReturnState, .idle)
        controller.cancelCurrentJob()
    }

    func testAudioInterruptionsAndRouteChangesNeverLeaveStuckListeningState() async throws {
        let now = 8_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("saved before call")
        let bridge = KeyboardBridge(defaults: defaults)

        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        controller.toggleWarmSession()
        try await activationSettled(controller)

        // Long capture (>= 0.3s) interrupted by phone call saves and transcribes spoken words!
        audio.nextCaptureDuration = 2.1
        controller.startRecording(keyboardJobID: "call-job")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)

        controller.handleAudioSystemEvent(.interruptionBegan)
        try await transcribed(controller)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.transcript, "Saved before call.")
        XCTAssertNotEqual(bridge.snapshot().state, .recording)

        // Short capture (< 0.3s) interrupted cancels cleanly out of recording.
        audio.nextCaptureDuration = 0.1
        controller.startRecording(keyboardJobID: "short-call-job")
        try await activationSettled(controller)
        controller.handleAudioSystemEvent(.interruptionBegan)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotEqual(bridge.snapshot().state, .recording)
    }

    func testWarmSessionStaysHotForTheNextKeyboardDictationWhileInBackground() async throws {
        let now = 9_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)

        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        let startsWhileForeground = audio.startKeepaliveCount

        // The person returns to the host app: from now on iOS won't start input again.
        audio.canStartInput = false

        for job in ["first", "second", "third"] {
            bridge.send(.start, jobID: job, style: .polished, sentAt: now)
            controller.processPendingKeyboardCommandForTesting()
            try await activationSettled(controller)
            XCTAssertEqual(controller.phase, .recording, "\(job) dictation should record from the keyboard")

            controller.finishRecording()
            try await transcribed(controller)
            XCTAssertEqual(controller.phase, .ready)
            XCTAssertTrue(controller.keyboardSessionEnabled, "\(job) dictation must not end the warm session")
            XCTAssertTrue(audio.isKeepaliveRunning)
            XCTAssertEqual(bridge.snapshot().state, .ready)
        }

        XCTAssertEqual(audio.startKeepaliveCount, startsWhileForeground, "no input restart in the background")
        XCTAssertEqual(audio.deactivateCount, 0)
    }

    func testExclusiveSessionMediaPreventsWarmOnlyActivationButAllowsColdKeyboardDictation() async throws {
        let now = 9_100.0
        let audio = FakeAudioManager()
        audio.mixesWithOtherAudio = false
        audio.isOtherAudioPlaying = true
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let settings = typrSettings(.typrExclusiveAudioSession, .mixWithOtherAudio)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   settings: settings)
        // Synchronous: with media playing a warm-only request ends the session without activating.
        controller.selectWarmDuration(.fifteenMinutes)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        XCTAssertFalse(audio.isKeepaliveRunning)
        XCTAssertEqual(audio.startKeepaliveCount, 0)
        XCTAssertTrue(audio.isOtherAudioPlaying, "warming must not interrupt media")
        XCTAssertEqual(bridge.snapshot().state, .offline)

        await transcriber.armSuspension()
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "media", requestedAt: now, style: .polished, host: nil)
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertFalse(audio.isOtherAudioPlaying, "the activation now interrupted playback")
        XCTAssertTrue(audio.isKeepaliveRunning)
        let releasesBeforeFinish = audio.deactivateCount
        controller.finishRecording()
        XCTAssertEqual(controller.phase, .transcribing)
        XCTAssertEqual(audio.deactivateCount, releasesBeforeFinish + 1)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        XCTAssertFalse(audio.isKeepaliveRunning)
        try await asrSuspended(transcriber)
        // Negative check over real time: a warm loop that survived would restart input within a tick.
        try await Task.sleep(for: Self.sessionLoopTick * 2)
        XCTAssertEqual(audio.startKeepaliveCount, 1, "warm loop must not restart input during ASR")
        await transcriber.resumeSuspended(with: "ship the build")
        try await transcribed(controller)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(bridge.snapshot().hasDeliverableResult(at: now + 1))
        XCTAssertFalse(audio.isKeepaliveRunning)

        // Nothing is playing on the next activation: ordinary warm behavior returns.
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning)
        controller.endWarmSession()
    }

    func testExclusiveSessionMediaCaptureReleasesOnCancelShortCaptureFailureAndUnexpectedEnd() async throws {
        for outcome in ["cancel", "short", "failure", "unexpected-success", "unexpected-failure"] {
            let audio = FakeAudioManager()
            audio.mixesWithOtherAudio = false
            audio.isOtherAudioPlaying = true
            audio.nextCaptureDuration = outcome == "short" ? 0.1 : 1.4
            audio.captureShouldThrow = outcome == "failure"
            let transcriber = ControlledTranscriber()
            let controller = try await readyController(audio: audio, transcriber: transcriber, retryDelays: [],
                                                       settings: typrSettings(.typrExclusiveAudioSession))
            controller.setWarmDuration(.fifteenMinutes)
            controller.startRecording()
            try await activationSettled(controller)
            if outcome != "failure" {
                XCTAssertEqual(controller.phase, .recording, outcome)
                if outcome == "cancel" {
                    controller.cancelCurrentJob()
                } else if outcome.hasPrefix("unexpected") {
                    let capture = try XCTUnwrap(audio.createdCaptures.last)
                    capture.isRecording = false
                    audio.onUnexpectedCaptureEnd?(capture.url, outcome == "unexpected-success")
                } else {
                    controller.finishRecording()
                }
            }
            // Every outcome releases audio synchronously; this drains the transcription that the
            // finished and unexpected-success captures start before the next controller.
            try await transcribed(controller)
            XCTAssertFalse(audio.isKeepaliveRunning, outcome)
            XCTAssertFalse(controller.keyboardSessionEnabled, outcome)
            XCTAssertGreaterThan(audio.deactivateCount, 0, outcome)
            XCTAssertEqual(audio.startKeepaliveCount, 1, outcome)
        }
    }

    func testExclusiveSessionMediaStartingDuringWarmSessionLeavesInputColdAfterInterruption() async throws {
        let audio = FakeAudioManager()
        audio.mixesWithOtherAudio = false
        let transcriber = ControlledTranscriber()
        let controller = try await readyController(audio: audio, transcriber: transcriber,
                                                   settings: typrSettings(.typrExclusiveAudioSession))
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(audio.isKeepaliveRunning)
        audio.isOtherAudioPlaying = true
        controller.handleAudioSystemEvent(.interruptionBegan)
        XCTAssertFalse(audio.isKeepaliveRunning)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        // Synchronous: the media-ended session has no suspended input to resume.
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(audio.startKeepaliveCount, 1, "do not interrupt media to restore idle input")
        XCTAssertTrue(audio.isOtherAudioPlaying)
    }

    func testSelectWarmDurationWarmsAndEndsWithoutSeparateButton() async throws {
        let now = 12_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)

        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })

        controller.setWarmDuration(.off)
        XCTAssertFalse(controller.keyboardSessionEnabled)

        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning)
        XCTAssertEqual(controller.warmDuration, .fifteenMinutes)

        controller.selectWarmDuration(.off)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        XCTAssertFalse(audio.isKeepaliveRunning)
    }

    func testOneShotColdStartFromAnotherAppStopsOnKeyboardDone() async throws {
        let now = 13_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   hostReturner: HostReturner(openByBundleID: { _ in true }, openURL: { _ in false }))
        controller.setWarmDuration(.off)

        controller.handleKeyboardLaunch(
            .startRecording(jobID: "notes-job", requestedAt: now - 0.3, style: .polished, host: "com.apple.mobilenotes")
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertFalse(controller.keyboardSessionEnabled)
        XCTAssertEqual(bridge.snapshot().jobID, "notes-job")

        bridge.send(.stop, jobID: "notes-job", sentAt: now)
        try await waitForState("keyboard Done stopped the recording") { controller.phase != .recording }
        try await transcribed(controller)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotEqual(bridge.snapshot().state, .recording)
        XCTAssertNotNil(bridge.snapshot().resultID)
    }

    func testKeyboardStillSeesALongTranscriptionAfterTheMicIsReleased() async throws {
        var now = 14_000.0
        let audio = FakeAudioManager()
        audio.mixesWithOtherAudio = false
        audio.isOtherAudioPlaying = true
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   settings: typrSettings(.typrExclusiveAudioSession))
        controller.setWarmDuration(.off)
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "media-job", requestedAt: now - 0.3, style: .polished, host: nil)
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)

        await transcriber.armSuspension()
        bridge.send(.stop, jobID: "media-job", sentAt: now)
        try await waitForState("keyboard Done stopped the recording") { controller.phase == .transcribing }
        try await asrSuspended(transcriber)

        now += 5
        try await waitForState("transcription heartbeat") { bridge.snapshot().heartbeat == now }
        XCTAssertEqual(bridge.snapshot().live(at: now).state, .transcribing)

        await transcriber.resumeSuspended(with: "ship it")
        try await transcribed(controller)
    }

    /// Hex #2163: ✕ in the keyboard after a One shot handoff ends the recording without a result.
    func testOneShotHandoffCancelledFromTheKeyboardStops() async throws {
        let now = 14_500.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now },
                                                   hostReturner: HostReturner(openByBundleID: { _ in true }, openURL: { _ in false }))
        controller.setWarmDuration(.off)
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "notizen", requestedAt: now - 0.3, style: .polished, host: "com.apple.mobilenotes")
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)

        bridge.send(.cancel, jobID: "notizen", sentAt: now)
        try await waitForState("keyboard cancel stopped the recording") { controller.phase == .ready }
        XCTAssertEqual(bridge.snapshot().state, .offline)
        XCTAssertNil(bridge.snapshot().jobID)
        XCTAssertNil(bridge.snapshot().resultID)
        XCTAssertFalse(audio.isKeepaliveRunning)
    }

    /// Hex #2163: in One shot the microphone closes when Done arrives, and with it the audio
    /// background mode. Typr holds background time until the transcription ends, so iOS does not
    /// suspend it in the host app before the text reaches the keyboard.
    func testOneShotHandoffTranscriptionKeepsBackgroundTimeUntilItsResultIsPublished() async throws {
        let now = 14_600.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let background = CleanupTestBackground()
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   hostReturner: HostReturner(openByBundleID: { _ in true }, openURL: { _ in false }),
                                                   background: background)
        controller.setWarmDuration(.off)
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "nachricht", requestedAt: now - 0.3, style: .polished, host: "net.whatsapp.WhatsApp")
        )
        try await activationSettled(controller)
        XCTAssertEqual(background.begins, 0)

        await transcriber.armSuspension()
        bridge.send(.stop, jobID: "nachricht", sentAt: now)
        try await waitForState("keyboard Done stopped the recording") { controller.phase == .transcribing }
        try await asrSuspended(transcriber)
        XCTAssertFalse(audio.isKeepaliveRunning)
        XCTAssertEqual(background.begins, 1)
        XCTAssertEqual(background.ends, [])

        await transcriber.resumeSuspended(with: "Bin gleich da")
        try await transcribed(controller)
        XCTAssertEqual(background.ends, [1])
        XCTAssertTrue(bridge.snapshot().hasDeliverableResult(at: now))
    }

    /// Hex #2163: the keyboard was dismissed (or the user switched apps) while Typr transcribed. The
    /// result waits in the App Group for 30 s, for whichever keyboard process shows next.
    func testAResultFinishedWhileNoKeyboardShowsReachesTheNextKeyboard() async throws {
        let now = 14_700.0
        let transcriber = ControlledTranscriber()
        let controller = try await readyController(audio: FakeAudioManager(), bridge: KeyboardBridge(defaults: defaults),
                                                   transcriber: transcriber, now: { now },
                                                   hostReturner: HostReturner(openByBundleID: { _ in true }, openURL: { _ in false }))
        controller.setWarmDuration(.off)
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "mail", requestedAt: now - 0.3, style: .polished, host: "com.apple.mobilemail")
        )
        try await activationSettled(controller)
        await transcriber.setCannedOutput("bis morgen")
        KeyboardBridge(defaults: defaults).send(.stop, jobID: "mail", sentAt: now)
        try await waitForState("keyboard Done stopped the recording") { controller.phase != .recording }
        try await transcribed(controller)

        let nextKeyboard = KeyboardBridge(defaults: defaults).snapshot()
        XCTAssertNotNil(nextKeyboard.transcript)
        XCTAssertEqual(nextKeyboard.transcript, controller.transcript)
        XCTAssertTrue(nextKeyboard.hasDeliverableResult(at: now + 29))
        XCTAssertFalse(nextKeyboard.hasDeliverableResult(at: now + 31))
        XCTAssertTrue(nextKeyboard.hasOfferableResult(at: now + 31))
        XCTAssertFalse(nextKeyboard.hasOfferableResult(at: now + 30 + KeyboardSnapshot.resultOfferWindow + 1))
    }

    func testMeterRecoversAfterCaptureStartsTemporarilyNotRecording() async throws {
        try await checkMeterRecovery(initiallyRecording: false)
    }

    func testMeterRecoversAfterRecordingTemporarilyStops() async throws {
        try await checkMeterRecovery(initiallyRecording: true)
    }

    private func checkMeterRecovery(initiallyRecording: Bool) async throws {
        var now = 20_000.0
        let audio = FakeAudioManager()
        audio.nextCaptureIsRecording = initiallyRecording
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        controller.startRecording(keyboardJobID: "meter-recovery")
        try await activationSettled(controller)
        let capture = try XCTUnwrap(audio.createdCaptures.last)
        defer { controller.cancelCurrentJob() }

        // No completion/interruption callback: the same capture becomes available again.
        capture.isRecording = false
        // Real meter cycles: let samples see the paused capture (nothing observable changes).
        try await Task.sleep(for: Self.meterCycle * 3)
        capture.power = 0.9
        capture.currentTime = 2.4
        capture.isRecording = true
        now += 1
        try await waitForState("meter read the recovered capture") { controller.recordingDuration == 2.4 }

        let db = capture.averagePowerDB()
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(controller.loudnessDB, db, accuracy: 0.001)
        XCTAssertEqual(controller.audioLevel, (db + 48) / 48, accuracy: 0.001)
        XCTAssertEqual(controller.recordingDuration, 2.4)
        XCTAssertEqual(bridge.snapshot().state, .recording)
        XCTAssertEqual(bridge.snapshot().effectiveLoudnessDB, db, accuracy: 0.001)
        XCTAssertEqual(bridge.snapshot().heartbeat, now)

        // A level-only change must still get through the keyboard publication throttle.
        capture.power = 0.2
        now += 1
        try await waitForState("meter read the new level") { controller.loudnessDB == capture.averagePowerDB() }
        XCTAssertEqual(controller.loudnessDB, capture.averagePowerDB(), accuracy: 0.001)
        XCTAssertEqual(bridge.snapshot().effectiveLoudnessDB, capture.averagePowerDB(), accuracy: 0.001)

        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(controller.transcript, "Ship the build.")
        XCTAssertEqual(controller.audioLevel, 0)
        XCTAssertEqual(bridge.snapshot().audioLevel, 0)
    }

    func testCustomVocabularyAppliesOnlyWhenCaptured() async throws {
        let now = 50_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("i use open code")
        let bridge = KeyboardBridge(defaults: defaults)
        let settings = CustomVocabularySettings(defaults: defaults)
        settings.terms = ["OpenCode"]
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   vocabulary: settings)

        // Off: the transcript is formatted exactly as before.
        settings.isEnabled = false
        controller.startRecording(keyboardJobID: "vocabulary-off", styleOverride: .verbatim)
        try await activationSettled(controller)
        settings.isEnabled = true // A mid-capture toggle must not affect this session.
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(controller.transcript, "i use open code")

        // On: the setting is captured at start, before formatting.
        controller.clearTranscript()
        settings.isEnabled = true
        controller.startRecording(keyboardJobID: "vocabulary-on", styleOverride: .verbatim)
        try await activationSettled(controller)
        settings.isEnabled = false
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(controller.transcript, "i use OpenCode")

    }

    func testCustomVocabularyReachesTheTranscriberOnlyWhileEnabledBeforeGlossaryHints() async throws {
        let now = 60_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("i use open code")
        let bridge = KeyboardBridge(defaults: defaults)
        let settings = CustomVocabularySettings(defaults: defaults)
        settings.terms = ["OpenCode"]
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   vocabulary: settings)

        settings.isEnabled = false
        controller.startRecording(keyboardJobID: "vocabulary-hint-off")
        try await activationSettled(controller)
        controller.finishRecording()
        try await transcribed(controller)
        // The built-in tech glossary always gives Apple Speech its hints; user terms come first.
        var arguments = await transcriber.vocabularyArguments
        XCTAssertEqual(arguments, [TechGlossary.listedTerms])

        settings.isEnabled = true
        controller.startRecording(keyboardJobID: "vocabulary-hint-on")
        try await activationSettled(controller)
        controller.finishRecording()
        try await transcribed(controller)
        arguments = await transcriber.vocabularyArguments
        XCTAssertEqual(arguments, [TechGlossary.listedTerms, ["OpenCode"] + TechGlossary.listedTerms])
    }

    func testCustomVocabularySurvivesPolishedFormatting() async throws {
        let now = 80_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("iphone 17 broke")
        let bridge = KeyboardBridge(defaults: defaults)
        let settings = CustomVocabularySettings(defaults: defaults)
        settings.terms = ["iPhone 17"]
        settings.isEnabled = true
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   vocabulary: settings)

        // Polished capitalizes the sentence start ("IPhone"), so the second pass
        // has to restore the listed term.
        controller.startRecording(keyboardJobID: "vocabulary-polished", styleOverride: .polished)
        try await activationSettled(controller)
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(controller.transcript, "iPhone 17 broke.")
    }

    // MARK: - Start without waiting after failures (2026-11-12 device logs)

    private func recoveryController(audio: FakeAudioManager, bridge: KeyboardBridge, now: TimeInterval,
                                    retryDelays: [Duration], onPrepare: @escaping () -> Void = {},
                                    settings: TyprSettings? = nil) async throws -> DictationController {
        try await readyController(audio: audio, bridge: bridge, now: { now },
                                  hostReturner: HostReturner(openByBundleID: { _ in false }, openURL: { _ in false }),
                                  retryDelays: retryDelays, onPrepare: onPrepare, settings: settings)
    }

    private func typrSettings(_ switches: ExperimentalSwitch...) -> TyprSettings {
        let settings = TyprSettings(defaults: defaults)
        for item in switches { settings[experiment: item] = true }
        return settings
    }

    func testActivationRetriesWhileAnotherAppStillHoldsAudio() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 20_000,
                                                      retryDelays: [.milliseconds(1), .milliseconds(1)],
                                                      settings: typrSettings(.typrAudioActivationRetries))

        audio.busyActivationsRemaining = 2
        controller.startRecording(keyboardJobID: "after-voice-message")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording, "a brief refusal must not fail the dictation")
        XCTAssertEqual(audio.startKeepaliveCount, 3)
        controller.cancelCurrentJob()
    }

    func testHexDefaultTriesAudioActivationOnce() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 20_500,
                                                      retryDelays: [.milliseconds(1), .milliseconds(1)])

        audio.busyActivationsRemaining = 1
        controller.startRecording(keyboardJobID: "busy-once")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .failed(DictationController.audioBusyMessage))
        XCTAssertEqual(audio.startKeepaliveCount, 1, "Typr audio activation retries is off")
    }

    func testHexDefaultStopsADictationAfterOneMinute() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let controller = try await readyController(audio: audio, transcriber: transcriber, retryDelays: [])
        audio.nextCaptureDuration = 59
        controller.startRecording(keyboardJobID: "a-minute")
        try await activationSettled(controller)
        let capture = try XCTUnwrap(audio.createdCaptures.last)
        try await waitForState("meter read 59 s") { controller.recordingDuration == 59 }
        XCTAssertEqual(controller.phase, .recording)

        capture.currentTime = 59.74
        try await waitForState("meter read 59.74 s") { controller.recordingDuration == 59.74 }
        XCTAssertEqual(controller.phase, .recording, "just below the limit keeps recording")

        capture.currentTime = 59.75
        try await waitForState("the one-minute limit stopped the capture") { controller.phase != .recording }
        try await transcribed(controller)
        XCTAssertEqual(controller.phase, .ready)
        let transcribedCaptures = await transcriber.transcribedURLs.count
        XCTAssertEqual(transcribedCaptures, 1, "the capture at the limit is transcribed")
        XCTAssertFalse(capture.isRecording)
    }

    func testHeadsetInTheBackgroundNeedsKeepSelectedWarmMicrophone() async throws {
        for keepSelected in [false, true] {
            let now = 21_500.0
            let audio = FakeAudioManager()
            audio.externalMicrophone = true
            let bridge = KeyboardBridge(defaults: defaults)
            let settings = keepSelected ? typrSettings(.typrKeepSelectedWarmMicrophone) : TyprSettings(defaults: defaults)
            let controller = try await recoveryController(audio: audio, bridge: bridge, now: now, retryDelays: [],
                                                          settings: settings)
            controller.selectWarmDuration(.fifteenMinutes)
            try await activationSettled(controller)
            XCTAssertEqual(audio.keepaliveMicrophones, [keepSelected ? .automatic : .iPhone])

            audio.canStartInput = false
            bridge.send(.start, jobID: "headset-\(keepSelected)", style: .polished, sentAt: now)
            controller.processPendingKeyboardCommandForTesting()
            try await activationSettled(controller)
            if keepSelected {
                XCTAssertEqual(controller.phase, .recording, "the warm input already records from the headset")
                XCTAssertEqual(audio.startKeepaliveCount, 1)
            } else {
                // Hex moves to the headset for the dictation, which iOS refuses in the background.
                guard case .failed = controller.phase else { return XCTFail("expected failure, got \(controller.phase)") }
                XCTAssertEqual(Array(audio.keepaliveMicrophones.prefix(2)), [.iPhone, .automatic])
            }
            controller.cancelCurrentJob()
            controller.endWarmSession()
        }
    }

    func testRefusalBeyondRetriesExplainsThatAudioIsBusy() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 21_000,
                                                      retryDelays: [.milliseconds(1)],
                                                      settings: typrSettings(.typrAudioActivationRetries))

        audio.busyActivationsRemaining = 5
        controller.startRecording(keyboardJobID: "busy")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .failed(DictationController.audioBusyMessage))
        XCTAssertEqual(audio.startKeepaliveCount, 2)
    }

    func testKeyboardHandoffAfterFailureReusesPreparedModel() async throws {
        let now = 22_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        var prepares = 0
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: now,
                                                      retryDelays: [], onPrepare: { prepares += 1 })
        XCTAssertEqual(prepares, 1)

        audio.captureShouldThrow = true
        controller.startRecording(keyboardJobID: "fails")
        try await activationSettled(controller)
        guard case .failed = controller.phase else { return XCTFail("expected failure, got \(controller.phase)") }

        audio.captureShouldThrow = false
        controller.handleKeyboardLaunch(
            .startRecording(jobID: "next", requestedAt: now, style: .polished, host: nil)
        )
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(prepares, 1, "a microphone failure must not reload the speech model")
        controller.cancelCurrentJob()
    }

    func testWarmKeyboardStartWorksAgainAfterFailedCapture() async throws {
        let now = 23_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: now, retryDelays: [])
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(audio.isKeepaliveRunning)

        audio.captureShouldThrow = true
        bridge.send(.start, jobID: "fails", style: .polished, sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        guard case .failed = controller.phase else { return XCTFail("expected failure, got \(controller.phase)") }
        XCTAssertTrue(audio.isKeepaliveRunning)

        audio.captureShouldThrow = false
        bridge.send(.start, jobID: "retry", style: .polished, sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording, "the warm keyboard start must not be ignored after a failure")
        controller.cancelCurrentJob()
    }

    func testInterruptionResumeRetriesBeforeEndingWarmSession() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 24_000,
                                                      retryDelays: [.milliseconds(1), .milliseconds(1)],
                                                      settings: typrSettings(.typrAudioActivationRetries))
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        controller.handleAudioSystemEvent(.interruptionBegan)
        XCTAssertFalse(audio.isKeepaliveRunning)
        audio.busyActivationsRemaining = 2
        var starts = audio.startKeepaliveCount
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        try await waitForState("resume made all three activation attempts") { audio.startKeepaliveCount == starts + 3 }
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning)

        controller.handleAudioSystemEvent(.interruptionBegan)
        audio.busyActivationsRemaining = 10
        starts = audio.startKeepaliveCount
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        // The last refusal ends the session in the same main-actor job.
        try await waitForState("resume used up its retries") { audio.startKeepaliveCount == starts + 3 }
        XCTAssertFalse(controller.keyboardSessionEnabled, "a lasting refusal still ends the warm session")
    }

    func testKeyboardStartDuringInterruptionResumeKeepsItsCapture() async throws {
        let now = 25_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: now,
                                                      retryDelays: [.milliseconds(50), .milliseconds(50)],
                                                      settings: typrSettings(.typrAudioActivationRetries))
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        controller.handleAudioSystemEvent(.interruptionBegan)
        audio.busyActivationsRemaining = 2
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        // Dictate right away, while the resume would still be retrying.
        bridge.send(.start, jobID: "right-after-voice-message", style: .polished, sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        let capture = try XCTUnwrap(audio.createdCaptures.last)
        let startsAfterCapture = audio.startKeepaliveCount

        // Negative check over real time: outlast the injected 2 × 50 ms resume retries the capture
        // took over and warm-loop ticks; nothing may restart the input under the capture.
        try await Task.sleep(for: Self.sessionLoopTick * 4)
        XCTAssertEqual(controller.phase, .recording, "the capture must keep recording")
        XCTAssertTrue(capture.isRecording)
        XCTAssertEqual(audio.startKeepaliveCount, startsAfterCapture, "no input restart under the capture")
        XCTAssertTrue(controller.keyboardSessionEnabled)
        controller.cancelCurrentJob()
    }

    func testFailedStartDuringCallKeepsWarmSessionUntilTheCallEnds() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 26_000, retryDelays: [])
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        // A phone call holds audio: every activation fails until it ends.
        controller.handleAudioSystemEvent(.interruptionBegan)
        audio.keepaliveShouldThrow = true
        controller.startRecording(keyboardJobID: "during-call")
        try await activationSettled(controller)
        guard case .failed = controller.phase else { return XCTFail("expected failure, got \(controller.phase)") }
        XCTAssertTrue(controller.keyboardSessionEnabled, "a failed start during the call must not end the session")

        audio.keepaliveShouldThrow = false
        let startsBeforeResume = audio.startKeepaliveCount
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        try await waitForState("resume activated the input") { audio.startKeepaliveCount == startsBeforeResume + 1 }
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning, "the end of the call still resumes the warm input")
    }

    func testSuccessfulStartDuringInterruptionEndsTheSuspension() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 27_000, retryDelays: [])
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        controller.handleAudioSystemEvent(.interruptionBegan)
        XCTAssertFalse(audio.isKeepaliveRunning)
        controller.startRecording(keyboardJobID: "during-voice-playback")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(audio.isKeepaliveRunning)
        let startsAfterDictation = audio.startKeepaliveCount

        // A late end of the interruption must not restart the running input or end the session.
        // Synchronous: the capture already cleared the suspension, so nothing is resumed.
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(audio.startKeepaliveCount, startsAfterDictation)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning)

        // The input is no longer treated as suspended: the session loop restarts a dead input.
        audio.stopKeepalive()
        try await waitForState("warm loop restarted the dead input") {
            audio.startKeepaliveCount == startsAfterDictation + 1
        }
        XCTAssertTrue(audio.isKeepaliveRunning, "the session loop must not skip a dead input after the suspension")
    }

    func testKeepSelectedWarmMicrophoneHoldsTheChosenMicrophoneBetweenDictations() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.microphone = .bluetooth
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 28_000, retryDelays: [],
                                                      settings: typrSettings(.typrKeepSelectedWarmMicrophone, .warmMicOnIPhone))
        XCTAssertEqual(controller.microphone, .bluetooth)
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertEqual(audio.keepaliveMicrophones, [.bluetooth])

        controller.startRecording(keyboardJobID: "bluetooth")
        try await activationSettled(controller)
        XCTAssertEqual(audio.captureMicrophones, [.bluetooth])
        controller.cancelCurrentJob()

        controller.setMicrophone(.iPhone)
        XCTAssertEqual(bridge.microphone, .iPhone)
        XCTAssertEqual(audio.keepaliveMicrophones.last, .iPhone, "the warm input moves to the new choice")
        controller.startRecording(keyboardJobID: "iphone")
        try await activationSettled(controller)
        XCTAssertEqual(audio.captureMicrophones.last, .iPhone)
        controller.cancelCurrentJob()
    }

    func testBluetoothWarmSessionStaysOffTheCallRouteAfterACall() async throws {
        let now = 29_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.microphone = .bluetooth
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: now, retryDelays: [],
                                                      settings: typrSettings(.typrKeepSelectedWarmMicrophone))
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        controller.handleAudioSystemEvent(.interruptionBegan)
        let startsBeforeResume = audio.startKeepaliveCount
        controller.handleAudioSystemEvent(.interruptionEnded(shouldResume: true))
        try await waitForState("resume activated the input") { audio.startKeepaliveCount == startsBeforeResume + 1 }
        XCTAssertEqual(audio.keepaliveMicrophones.last, .automatic, "the resumed input takes no hands-free route")

        audio.canStartInput = false
        let startsAfterResume = audio.startKeepaliveCount
        bridge.send(.start, jobID: "after-call", style: .polished, sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(audio.captureMicrophones.last, .automatic)
        XCTAssertEqual(audio.startKeepaliveCount, startsAfterResume)
        controller.cancelCurrentJob()

        audio.canStartInput = true
        controller.endWarmSession()
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertEqual(audio.keepaliveMicrophones.last, .bluetooth)
    }

    func testNewRouteDeviceRestartsWarmInputOnlyWhenItsInputChanged() async throws {
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await recoveryController(audio: audio, bridge: bridge, now: 30_000, retryDelays: [],
                                                      settings: typrSettings(.typrKeepSelectedWarmMicrophone))
        XCTAssertEqual(controller.microphone, .automatic, "Automatic is the default")
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        var starts = audio.startKeepaliveCount

        controller.handleAudioSystemEvent(.routeNewDeviceAvailable)
        XCTAssertEqual(audio.startKeepaliveCount, starts)

        audio.keepaliveInputIsStale = true
        controller.handleAudioSystemEvent(.routeNewDeviceAvailable)
        XCTAssertEqual(audio.startKeepaliveCount, starts + 1)
        XCTAssertEqual(audio.keepaliveMicrophones.last, .automatic)
        XCTAssertTrue(controller.keyboardSessionEnabled)

        controller.handleAudioSystemEvent(.interruptionBegan)
        starts = audio.startKeepaliveCount
        controller.handleAudioSystemEvent(.routeNewDeviceAvailable)
        XCTAssertEqual(audio.startKeepaliveCount, starts)
        XCTAssertTrue(controller.keyboardSessionEnabled)
    }

    func testHexWarmMicIdlesOnIPhoneAndMovesEachDictationToTheChosenMicrophone() async throws {
        let settings = TyprSettings(defaults: defaults)
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.microphone = .bluetooth
        let controller = try await readyController(audio: audio, bridge: bridge, now: { 31_000 }, retryDelays: [],
                                                   settings: settings)
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertEqual(audio.keepaliveMicrophones, [.iPhone], "idle warm input holds no hands-free route")

        controller.startRecording(keyboardJobID: "airpods")
        try await activationSettled(controller)
        XCTAssertEqual(audio.captureMicrophones, [.bluetooth])
        XCTAssertEqual(audio.keepaliveMicrophones, [.iPhone, .bluetooth])
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(audio.keepaliveMicrophones.last, .iPhone, "back on the iPhone after the dictation")
        XCTAssertTrue(controller.keyboardSessionEnabled)
    }

    func testHexSessionWarmsAndDictatesOverMedia() async throws {
        let settings = TyprSettings(defaults: defaults)
        let audio = FakeAudioManager()
        audio.isOtherAudioPlaying = true
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { 32_000 }, settings: settings)
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(controller.keyboardSessionEnabled, "media no longer keeps the mic cold")
        XCTAssertTrue(audio.isKeepaliveRunning)
        XCTAssertEqual(bridge.snapshot().state, .ready)

        audio.canStartInput = false
        for job in ["erste", "zweite"] {
            bridge.send(.start, jobID: job, style: .polished, sentAt: 32_000)
            controller.processPendingKeyboardCommandForTesting()
            try await activationSettled(controller)
            XCTAssertEqual(controller.phase, .recording, job)
            controller.finishRecording()
            try await transcribed(controller)
            XCTAssertTrue(controller.keyboardSessionEnabled, "\(job): the warm session outlasts the dictation")
            XCTAssertTrue(audio.isKeepaliveRunning, job)
        }
        XCTAssertTrue(audio.isOtherAudioPlaying)
        XCTAssertEqual(audio.deactivateCount, 0)
        XCTAssertEqual(audio.startKeepaliveCount, 1)
    }

    func testAKeepaliveThatKeepsStoppingIsRestartedLessAndLessOften() async throws {
        var now = 52_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        XCTAssertTrue(audio.isKeepaliveRunning)
        let started = audio.startKeepaliveCount

        audio.keepaliveStopsRightAway = true
        audio.isKeepaliveRunning = false
        try await waitForState("restarted at once") { audio.startKeepaliveCount == started + 1 }
        for (offset, delay) in [1.0, 2, 4, 8, 16, 30, 30].enumerated() {
            try await waitForState("next restart scheduled in \(delay) s") { controller.keepaliveRestartDue == now + delay }
            XCTAssertEqual(audio.startKeepaliveCount, started + 1 + offset, "waits \(delay) s")
            now += delay
            try await waitForState("restarted after \(delay) s") { audio.startKeepaliveCount == started + 2 + offset }
        }
        XCTAssertTrue(controller.keyboardSessionEnabled, "the warm session stays on meanwhile")
        try await waitForState("the keyboard sees the mic offline") { bridge.snapshot().state == .offline }

        audio.keepaliveStopsRightAway = false
        try await waitForState("next restart scheduled in 30 s") { controller.keepaliveRestartDue == now + 30 }
        now += 30
        try await waitForState("running again") { audio.isKeepaliveRunning }
        now += DictationController.steadyKeepalive
        let steady = audio.startKeepaliveCount
        audio.isKeepaliveRunning = false
        try await waitForState("a keepalive that ran a while restarts at once") {
            audio.startKeepaliveCount == steady + 1
        }
    }

    func testHoldCommitsTheCaptureArmedOnTouchDownAndTranscribesIt() async throws {
        let now = 60_000.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("Wir sehen uns morgen um zehn")
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        let keepaliveStarts = audio.startKeepaliveCount

        bridge.send(.arm, jobID: "diktat", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        let armed = try XCTUnwrap(audio.armedCaptures.first)
        XCTAssertTrue(armed.isRecording, "holds audio from the touch-down on")
        XCTAssertTrue(audio.createdCaptures.isEmpty, "nothing is written before the hold")
        XCTAssertEqual(controller.phase, .ready, "an armed capture is not a dictation yet")
        XCTAssertEqual(bridge.snapshot().state, .ready)
        XCTAssertNil(bridge.snapshot().jobID)

        bridge.send(.start, jobID: "diktat", sentAt: now + 0.35)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertEqual(controller.phase, .recording, "the hold starts at once, without a new activation")
        let capture = try XCTUnwrap(audio.createdCaptures.first)
        XCTAssertEqual(armed.committedTo, capture.url, "the held audio starts the dictation's capture")
        XCTAssertEqual(audio.createdCaptures.count, 1)
        XCTAssertEqual(bridge.snapshot().state, .recording)
        XCTAssertEqual(bridge.snapshot().jobID, "diktat")
        XCTAssertEqual(bridge.snapshot().recordingStartedAt, now)
        XCTAssertEqual(audio.startKeepaliveCount, keepaliveStarts)

        controller.finishRecording()
        try await transcribed(controller)
        let transcribedURLs = await transcriber.transcribedURLs
        XCTAssertEqual(transcribedURLs, [capture.url])
        XCTAssertTrue(bridge.snapshot().hasDeliverableResult(at: now + 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.url.path))
        XCTAssertTrue(controller.keyboardSessionEnabled)
    }

    func testAnArmedStartKeepsEveryPerCaptureSettingOfANormalStart() async throws {
        let now = 60_200.0
        let settings = TyprSettings(defaults: defaults)
        settings[experiment: .spokenPunctuation] = true
        settings[experiment: .formatLists] = true
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        await transcriber.setCannedOutput("Erstens Milch Komma Brot zweitens Käse Punkt Hallo Anna")
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now },
                                                   settings: settings)
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        func dictate(_ job: String, armed: Bool) async throws -> String {
            if armed {
                bridge.send(.arm, jobID: job, sentAt: now)
                controller.processPendingKeyboardCommandForTesting()
            }
            bridge.send(.start, jobID: job, style: .polished, sentAt: now)
            controller.processPendingKeyboardCommandForTesting()
            try await activationSettled(controller)
            XCTAssertEqual(controller.phase, .recording, job)
            controller.finishRecording()
            try await transcribed(controller)
            return controller.transcript
        }

        var outputs: [String] = []
        for (endsWithPeriod, lowercase) in [(true, false), (false, true)] {
            settings.dictationEndsWithPeriod = endsWithPeriod
            settings.dictationLowercase = lowercase
            let normal = try await dictate("normal-\(lowercase)", armed: false)
            let armedCaptures = audio.armedCaptures.count
            let armed = try await dictate("armed-\(lowercase)", armed: true)
            XCTAssertEqual(audio.armedCaptures.count, armedCaptures + 1, "the second start was armed")
            XCTAssertEqual(armed, normal, "period \(endsWithPeriod), lowercase \(lowercase)")
            outputs.append(armed)
        }
        XCTAssertNotEqual(outputs[0], outputs[1], "the settings change the text, so equal results are not vacuous")
        XCTAssertEqual(outputs[1], outputs[1].lowercased())
    }

    func testAWriteFailureAfterTheCommitFailsTheDictationInsteadOfTranscribingPartialAudio() async throws {
        let now = 60_500.0
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, transcriber: transcriber, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        bridge.send(.arm, jobID: "voll", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        bridge.send(.start, jobID: "voll", sentAt: now + 0.35)
        controller.processPendingKeyboardCommandForTesting()
        let capture = try XCTUnwrap(audio.createdCaptures.first)
        capture.didFailWriting = true

        controller.finishRecording()
        XCTAssertEqual(controller.phase, .failed("Recording stopped unexpectedly."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.url.path))
        XCTAssertEqual(bridge.snapshot().state, .failed)
        XCTAssertNil(bridge.snapshot().resultID)
        let transcribedURLs = await transcriber.transcribedURLs
        XCTAssertTrue(transcribedURLs.isEmpty)
        XCTAssertTrue(controller.keyboardSessionEnabled)
    }

    func testATapOrSlideDropsTheArmedAudioWithoutWritingAFile() async throws {
        let now = 61_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        let keepaliveStarts = audio.startKeepaliveCount
        let temporaryFiles = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)

        for (index, job) in ["leertaste", "wischen", "abbruch"].enumerated() {
            bridge.send(.arm, jobID: job, sentAt: now)
            controller.processPendingKeyboardCommandForTesting()
            bridge.send(.cancel, jobID: job, sentAt: now)
            controller.processPendingKeyboardCommandForTesting()
            let armed = audio.armedCaptures[index]
            XCTAssertFalse(armed.isRecording, job)
            XCTAssertNil(armed.committedTo, job)
        }
        XCTAssertTrue(audio.createdCaptures.isEmpty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).sorted(),
            temporaryFiles.sorted(),
            "a discarded arm writes no file"
        )
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(bridge.snapshot().state, .ready)
        XCTAssertNil(bridge.snapshot().resultID)
        XCTAssertTrue(controller.keyboardSessionEnabled)
        XCTAssertTrue(audio.isKeepaliveRunning, "the warm input keeps running")
        XCTAssertEqual(audio.startKeepaliveCount, keepaliveStarts)
        XCTAssertEqual(audio.deactivateCount, 0)
    }

    func testAnArmedCaptureNobodyCommitsEndsAtItsDeadlineAndALateHoldStartsAfresh() async throws {
        var now = 62_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        bridge.send(.arm, jobID: "vergessen", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        let armed = try XCTUnwrap(audio.armedCaptures.first)
        now += DictationController.armedCaptureLifetime + 0.1
        try await waitForState("the warm loop drops the armed capture") { !armed.isRecording }
        XCTAssertNil(armed.committedTo)

        bridge.send(.start, jobID: "vergessen", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording, "a late hold is an ordinary start")
        XCTAssertEqual(audio.createdCaptures.count, 1)
        XCTAssertTrue(audio.createdCaptures[0].isRecording)
        XCTAssertNil(armed.committedTo)
    }

    func testAStartForAnotherJobDiscardsTheArmedCapture() async throws {
        let now = 63_000.0
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now })
        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)

        bridge.send(.arm, jobID: "alt", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        bridge.send(.arm, jobID: "neu", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertFalse(audio.armedCaptures[0].isRecording, "a new touch-down replaces the old arming")
        XCTAssertTrue(audio.armedCaptures[1].isRecording)

        bridge.send(.start, jobID: "andere", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        try await activationSettled(controller)
        XCTAssertFalse(audio.armedCaptures[1].isRecording)
        XCTAssertNil(audio.armedCaptures[1].committedTo)
        XCTAssertEqual(audio.createdCaptures.count, 1)
        XCTAssertEqual(bridge.snapshot().jobID, "andere")

        bridge.send(.cancel, jobID: "neu", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertEqual(controller.phase, .recording, "a cancel for a job that was only armed leaves the dictation")
    }

    func testArmingOnlyUsesARunningWarmInputThatAlreadyFollowsTheMicrophone() async throws {
        let now = 64_000.0
        let settings = TyprSettings(defaults: defaults)
        let audio = FakeAudioManager()
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.microphone = .bluetooth
        let controller = try await readyController(audio: audio, bridge: bridge, now: { now }, settings: settings)

        bridge.send(.arm, jobID: "kalt", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertTrue(audio.armedCaptures.isEmpty, "no warm session: never opens the microphone")

        controller.selectWarmDuration(.fifteenMinutes)
        try await activationSettled(controller)
        let keepalives = audio.keepaliveMicrophones
        bridge.send(.arm, jobID: "umweg", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertTrue(audio.armedCaptures.isEmpty, "the iPhone warm input would have to move to Bluetooth")
        XCTAssertEqual(audio.keepaliveMicrophones, keepalives)

        controller.setMicrophone(.iPhone)
        bridge.send(.arm, jobID: "alt", sentAt: now - DictationController.armedCaptureLifetime - 1)
        controller.processPendingKeyboardCommandForTesting()
        XCTAssertTrue(audio.armedCaptures.isEmpty, "a stale touch-down arms nothing")

        bridge.send(.arm, jobID: "anruf", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        let armed = try XCTUnwrap(audio.armedCaptures.first)
        controller.handleAudioSystemEvent(.routeNewDeviceAvailable)
        XCTAssertFalse(armed.isRecording, "a route change drops the arming")

        bridge.send(.arm, jobID: "neustart", sentAt: now)
        controller.processPendingKeyboardCommandForTesting()
        let rearmed = try XCTUnwrap(audio.armedCaptures.last)
        XCTAssertTrue(rearmed.isRecording)
        controller.setMicrophone(.automatic)
        XCTAssertFalse(rearmed.isRecording, "restarting the warm input drops the arming")
        XCTAssertTrue(audio.createdCaptures.isEmpty)
    }

    func testOnlyEngineFailuresRequireReloadingTheModel() {
        XCTAssertTrue(DictationController.transcriptionFailureKeepsModel(WhisperTranscriber.TranscriberError.silentAudio))
        XCTAssertTrue(DictationController.transcriptionFailureKeepsModel(WhisperTranscriber.TranscriberError.emptyTranscript))
        XCTAssertTrue(DictationController.transcriptionFailureKeepsModel(CancellationError()))
        XCTAssertFalse(DictationController.transcriptionFailureKeepsModel(
            WhisperTranscriber.TranscriberError.corruptModel("ANE")))
        XCTAssertFalse(DictationController.transcriptionFailureKeepsModel(WhisperTranscriber.TranscriberError.notPrepared))
    }

    /// Real production periods, used only for negative checks where correct code changes nothing.
    private static let meterCycle = Duration.milliseconds(33)
    private static let sessionLoopTick = Duration.milliseconds(100)

    func testOnlyCopyingDictationsShowALiveActivity() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let controller = try await readyController(audio: audio, transcriber: transcriber, liveActivity: liveActivity)

        controller.startRecording(keyboardJobID: "keyboard-job")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        controller.cancelCurrentJob()
        XCTAssertEqual(liveActivity.events, [.end])

        await transcriber.setCannedOutput("")
        try await dictateInApp(controller)
        XCTAssertEqual(liveActivity.events, [.end, .end])

        controller.startRecording(copyToPasteboard: true)
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(liveActivity.events, [.end, .end, .start, .transcribing, .end])
    }

    func testCopiedDictationFinishesItsLiveActivityOnce() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let controller = try await readyController(audio: audio, transcriber: transcriber, liveActivity: liveActivity)

        controller.startRecording(copyToPasteboard: true)
        try await activationSettled(controller)
        controller.finishRecording()
        try await transcribed(controller)

        XCTAssertEqual(controller.transcript, "Ship the build.")
        XCTAssertEqual(liveActivity.events, [.start, .transcribing, .copied])
    }

    func testCancelledTranscriptionEndsTheLiveActivityAndItsLateResultLeavesItEnded() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let controller = try await readyController(audio: audio, transcriber: transcriber, liveActivity: liveActivity)

        await transcriber.armSuspension()
        controller.startRecording(copyToPasteboard: true)
        try await activationSettled(controller)
        controller.finishRecording()
        try await asrSuspended(transcriber)
        controller.cancelCurrentJob()
        XCTAssertEqual(liveActivity.events, [.start, .transcribing, .end])

        await transcriber.resumeSuspended(with: "too late")
        try await transcribed(controller)
        XCTAssertEqual(liveActivity.events, [.start, .transcribing, .end])
        XCTAssertEqual(controller.transcript, "")
    }

    func testStaleLiveActivitiesEndOnlyWhenNoDictationOwnsThem() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let controller = try await readyController(audio: audio, transcriber: transcriber, liveActivity: liveActivity)

        controller.endStaleLiveActivities()
        XCTAssertEqual(liveActivity.events, [.end])

        await transcriber.armSuspension()
        controller.startRecording(copyToPasteboard: true)
        try await activationSettled(controller)
        controller.endStaleLiveActivities()
        controller.finishRecording()
        try await asrSuspended(transcriber)
        controller.endStaleLiveActivities()
        XCTAssertEqual(liveActivity.events, [.end, .start, .transcribing])

        await transcriber.resumeSuspended(with: "")
        try await transcribed(controller)
        XCTAssertEqual(liveActivity.events, [.end, .start, .transcribing, .end])
    }

    func testTyprLiveActivityForAllDictationsShowsItForKeyboardAndInAppDictations() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let settings = typrSettings(.typrLiveActivityForAllDictations)
        let controller = try await readyController(audio: audio, transcriber: transcriber, settings: settings,
                                                   liveActivity: liveActivity)

        await transcriber.setCannedOutput("")
        controller.startRecording(keyboardJobID: "keyboard-job")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        controller.finishRecording()
        try await transcribed(controller)
        XCTAssertEqual(liveActivity.events, [.start, .transcribing, .end])

        try await dictateInApp(controller)
        XCTAssertEqual(liveActivity.events, [.start, .transcribing, .end, .start, .transcribing, .end])
    }

    private func dictateInApp(_ controller: DictationController) async throws {
        controller.performPrimaryAction()
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        controller.performPrimaryAction()
        try await transcribed(controller)
    }

    func testDictateToggleWaitsForAModelThatIsAlreadyPreparing() async throws {
        let audio = FakeAudioManager()
        let transcriber = ControlledTranscriber()
        let liveActivity = RecordingLiveActivity()
        let clock = ClockReads()
        let controller = DictationController(
            audio: audio, keyboardBridge: KeyboardBridge(defaults: defaults), transcriber: transcriber,
            transcriberFactory: { transcriber }, now: { clock.read() }, autoPrepareOnInit: false,
            liveActivity: liveActivity, languageSettings: TyprSettings(defaults: defaults))
        controllers.append(controller)
        await transcriber.armPrepareSuspension()
        controller.prepareModel()
        try await waitForState("model preparation suspended") { await transcriber.isPreparing() }
        XCTAssertEqual(controller.phase, .preparingModel)
        let marker = UUID().uuidString
        controller.transcript = marker
        try await waitForState("this controller handles system commands") {
            await TyprSystemCommandBus.shared.dispatch(.stopDictation) == marker
        }
        controller.transcript = ""

        let readsBefore = clock.count
        let toggle = Task { await TyprSystemCommandBus.shared.dispatch(.toggleDictation) }
        try await waitForState("toggle waits for the model") { clock.count > readsBefore }
        XCTAssertEqual(controller.phase, .preparingModel)
        await transcriber.resumePrepare()
        let result = await toggle.value

        XCTAssertEqual(result, "")
        try await activationSettled(controller)
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(liveActivity.events, [.start])
        controller.cancelCurrentJob()
    }

    private func readyController(
        audio: FakeAudioManager, bridge: KeyboardBridge? = nil, transcriber: ControlledTranscriber = ControlledTranscriber(),
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }, hostReturner: HostReturner? = nil,
        vocabulary: CustomVocabularySettings = CustomVocabularySettings(),
        retryDelays: [Duration] = DictationController.audioActivationRetryDelays, onPrepare: @escaping () -> Void = {},
        settings: TyprSettings? = nil, background: (any BackgroundTaskStarting)? = nil,
        liveActivity: (any LiveActivityPresenting)? = nil
    ) async throws -> DictationController {
        let settings = settings ?? TyprSettings(defaults: defaults)
        let controller = DictationController(
            audio: audio, keyboardBridge: bridge ?? KeyboardBridge(defaults: defaults), transcriber: transcriber,
            transcriberFactory: { onPrepare(); return transcriber }, now: now, autoPrepareOnInit: false,
            hostReturner: hostReturner, customVocabularySettings: vocabulary, transcriptionBackground: background,
            liveActivity: liveActivity, languageSettings: settings, audioActivationRetryDelays: retryDelays)
        controllers.append(controller)
        controller.prepareModel()
        try await waitForState("model ready") { controller.phase == .ready }
        return controller
    }

    /// A warm-session activation or a capture start sets `.requestingPermission` synchronously and
    /// leaves it, with the session, capture or failure in place, in the task's last main-actor job.
    private func activationSettled(_ controller: DictationController) async throws {
        try await waitForState("microphone activation finished") { controller.phase != .requestingPermission }
    }

    /// Covers the unwind as well: `isIdleForTest` waits for the transcription task to be released.
    private func transcribed(_ controller: DictationController) async throws {
        try await waitForState("transcription finished") { controller.isIdleForTest }
    }

    private func asrSuspended(_ transcriber: ControlledTranscriber) async throws {
        try await waitForState("transcription suspended in ASR") { await transcriber.isWaiting() }
    }
}
