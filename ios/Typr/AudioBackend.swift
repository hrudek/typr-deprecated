import AVFAudio
import Foundation

nonisolated enum AudioSystemEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeOldDeviceUnavailable
    case routeNewDeviceAvailable
    case mediaServicesReset
}

@MainActor
protocol ActiveAudioCapture: AnyObject {
    var url: URL { get }
    var isRecording: Bool { get }
    /// After `stop()`: some audio never reached the file, so it must not be transcribed.
    var didFailWriting: Bool { get }
    var currentTime: TimeInterval { get }
    func normalizedPowerLevel() -> Float
    func averagePowerDB() -> Float
    func stop()
}

extension ActiveAudioCapture {
    var didFailWriting: Bool { false }

    func averagePowerDB() -> Float {
        DotScopeSimulation.loudness(fromNormalized: normalizedPowerLevel())
    }
}

@MainActor
protocol AudioManaging: AnyObject {
    var isKeepaliveRunning: Bool { get }
    var isOtherAudioPlaying: Bool { get }
    var onSystemEvent: ((AudioSystemEvent) -> Void)? { get set }
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)? { get set }

    func requestPermission() async -> Bool
    func startKeepalive(microphone: MicrophoneChoice) throws
    /// Starts the keepalive only when it isn't already running for this choice's input. Never
    /// restarts a running input: iOS refuses to start microphone input in the background,
    /// so a restart there would end the warm session.
    func ensureKeepalive(microphone: MicrophoneChoice) throws
    /// Whether the running keepalive records from the input `microphone` picks on the
    /// current route, which a newly connected car or headset can change.
    func keepaliveFollows(_ microphone: MicrophoneChoice) -> Bool
    func stopKeepalive()
    func deactivateSession()
    func beginCapture(at url: URL, maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ActiveAudioCapture
    /// Like `beginCapture`, but the audio stays in memory until `commit(to:)`.
    func beginArmedCapture(maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ArmedAudioCapture
}

/// Audio from the running input held in memory only (at most `TapFileWriter.heldLimit`).
/// `commit(to:)` writes it as the start of a capture that keeps recording there; `stop()` drops it.
@MainActor
protocol ArmedAudioCapture: AnyObject {
    var isRecording: Bool { get }
    func commit(to url: URL) throws -> any ActiveAudioCapture
    func stop()
}

extension AudioManaging {
    var isOtherAudioPlaying: Bool { false }

    func ensureKeepalive(microphone: MicrophoneChoice) throws {
        guard !isKeepaliveRunning else { return }
        try startKeepalive(microphone: microphone)
    }

    func keepaliveFollows(_ microphone: MicrophoneChoice) -> Bool { isKeepaliveRunning }

    func beginArmedCapture(maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ArmedAudioCapture {
        throw CocoaError(.featureUnsupported)
    }
}

nonisolated private struct HeldBuffers: @unchecked Sendable {
    let buffers: [AVAudioPCMBuffer]
}

protocol CaptureFileSink: AnyObject {
    func write(from buffer: AVAudioPCMBuffer) throws
}

extension AVAudioFile: CaptureFileSink {}

/// Writes the running input tap into a 16 kHz mono 16-bit WAV (the format the recorder used to
/// write). Called on the tap's thread; everything is guarded by `lock`.
nonisolated final class TapFileWriter: @unchecked Sendable {
    static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
    }

    /// Called once, off the main thread, when the writer ends by itself: `true` at the
    /// duration limit, `false` when writing failed.
    var onEnd: (@Sendable (Bool) -> Void)?

    static let heldLimit: TimeInterval = 3

    private let lock = NSLock()
    private let outputFormat: AVAudioFormat
    private let maxFrames: AVAudioFramePosition
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var framesWritten: AVAudioFramePosition = 0
    private var powerDB: Float = -160
    private var isOpen = true
    private var held: [AVAudioPCMBuffer] = []
    private let queue: DispatchQueue
    private var committed = false
    private var committedFile: (any CaptureFileSink)?
    private let openSink: @Sendable (URL) throws -> any CaptureFileSink
    private var writeFailed = false

    convenience init(url: URL, maxDuration: TimeInterval) throws {
        try self.init(maxDuration: maxDuration)
        file = try Self.openFile(at: url)
    }

    /// Holds the newest `heldLimit` of audio in memory and writes nothing until `persist(to:onEnd:)`.
    init(
        maxDuration: TimeInterval,
        queue: DispatchQueue = DispatchQueue(label: "dev.rudek.typr.armed-writer"),
        openSink: @escaping @Sendable (URL) throws -> any CaptureFileSink = { try TapFileWriter.openFile(at: $0) }
    ) throws {
        self.queue = queue
        self.openSink = openSink
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        outputFormat = format
        maxFrames = AVAudioFramePosition(maxDuration * format.sampleRate)
    }

    static func openFile(at url: URL) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Hands the held audio to `queue`, which writes it to a new file at `url`, then every later
    /// buffer in order. The tap never waits for file I/O. A failed write ends with `onEnd(false)`.
    func persist(to url: URL, onEnd: @escaping @Sendable (Bool) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen, file == nil, !committed else { throw CocoaError(.fileWriteUnknown) }
        let audio = HeldBuffers(buffers: held)
        held = []
        committed = true
        self.onEnd = onEnd
        queue.async { self.openCommitted(at: url, writing: audio) }
    }

    private func openCommitted(at url: URL, writing audio: HeldBuffers) {
        do {
            let file = try openSink(url)
            committedFile = file
            for buffer in audio.buffers {
                try file.write(from: buffer)
            }
        } catch {
            failCommitted()
        }
    }

    private func writeCommitted(_ audio: HeldBuffers) {
        guard let committedFile else { return }
        do {
            for buffer in audio.buffers {
                try committedFile.write(from: buffer)
            }
        } catch {
            failCommitted()
        }
    }

    private func failCommitted() {
        committedFile = nil
        lock.lock()
        writeFailed = true
        let wasOpen = isOpen
        closeLocked()
        let onEnd = self.onEnd
        lock.unlock()
        if wasOpen {
            onEnd?(false)
        }
    }

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOpen
    }

    /// Complete only after `close()`, which waits for queued writes.
    var didFailWriting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return writeFailed
    }

    var currentTime: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(framesWritten) / outputFormat.sampleRate
    }

    var averagePowerDB: Float {
        lock.lock()
        defer { lock.unlock() }
        return powerDB
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        var ended: Bool?
        lock.lock()
        if isOpen {
            do {
                if let converted = try convert(buffer) {
                    let remaining = max(0, maxFrames - framesWritten)
                    if AVAudioFramePosition(converted.frameLength) > remaining {
                        converted.frameLength = AVAudioFrameCount(remaining)
                    }
                    if converted.frameLength > 0 {
                        if let file {
                            try file.write(from: converted)
                        } else if committed {
                            let audio = HeldBuffers(buffers: [converted])
                            queue.async { self.writeCommitted(audio) }
                        } else {
                            held.append(converted)
                        }
                        framesWritten += AVAudioFramePosition(converted.frameLength)
                        powerDB = Self.powerDB(of: converted)
                        let heldFrames = AVAudioFramePosition(Self.heldLimit * outputFormat.sampleRate)
                        while file == nil, !committed, framesWritten > heldFrames, held.count > 1 {
                            framesWritten -= AVAudioFramePosition(held.removeFirst().frameLength)
                        }
                    }
                }
                if framesWritten >= maxFrames {
                    closeLocked()
                    ended = true
                }
            } catch {
                writeFailed = true
                closeLocked()
                ended = false
            }
        }
        let onEnd = self.onEnd
        lock.unlock()
        if let ended {
            onEnd?(ended)
        }
    }

    /// Closing releases the file, which finishes its WAV header. Waits for queued writes.
    func close() {
        lock.lock()
        closeLocked()
        let committed = self.committed
        lock.unlock()
        if committed {
            queue.sync {}
        }
    }

    private func closeLocked() {
        isOpen = false
        file = nil
        held = []
        converter = nil
        if committed {
            queue.async { self.committedFile = nil }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return nil }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.downmix = true
        }
        guard let converter else { throw CocoaError(.coderInvalidValue) }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw CocoaError(.coderInvalidValue)
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw conversionError ?? CocoaError(.fileWriteUnknown)
        }
        return output
    }

    private static func powerDB(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        guard rms > 0 else { return -160 }
        return max(-160, 20 * log10(rms))
    }
}

/// Hands the keepalive tap's buffers to the capture currently writing, if any.
nonisolated private final class TapRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: TapFileWriter?

    func attach(_ newWriter: TapFileWriter) {
        lock.lock()
        let previous = writer
        writer = newWriter
        lock.unlock()
        if let previous, previous !== newWriter {
            previous.close()
        }
    }

    func detach(_ oldWriter: TapFileWriter) {
        lock.lock()
        if writer === oldWriter {
            writer = nil
        }
        lock.unlock()
    }

    func route(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = writer
        lock.unlock()
        current?.append(buffer)
    }
}

/// A capture that records from the already running keepalive input. Stopping it leaves the
/// input running, so a warm session never has to start the microphone again in the background.
@MainActor
private final class TapCaptureAdapter: ActiveAudioCapture {
    let url: URL
    private let writer: TapFileWriter
    private let router: TapRouter
    private let onFinish: @MainActor (URL, Bool) -> Void
    private var stopped = false

    init(
        url: URL,
        writer: TapFileWriter,
        router: TapRouter,
        onFinish: @escaping @MainActor (URL, Bool) -> Void
    ) {
        self.url = url
        self.writer = writer
        self.router = router
        self.onFinish = onFinish
    }

    var isRecording: Bool {
        !stopped && writer.isRecording
    }

    var currentTime: TimeInterval {
        writer.currentTime
    }

    var didFailWriting: Bool {
        writer.didFailWriting
    }

    func averagePowerDB() -> Float {
        writer.averagePowerDB
    }

    func normalizedPowerLevel() -> Float {
        max(0, min(1, (averagePowerDB() + 48) / 48))
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        router.detach(writer)
        writer.close()
    }

    nonisolated var onWriterEnd: @Sendable (Bool) -> Void {
        { [weak self] succeeded in
            Task { @MainActor in
                self?.writerEnded(succeeded: succeeded)
            }
        }
    }

    func writerEnded(succeeded: Bool) {
        guard !stopped else { return }
        stopped = true
        router.detach(writer)
        writer.close()
        onFinish(url, succeeded && !writer.didFailWriting)
    }
}

@MainActor
private final class TapArmedCapture: ArmedAudioCapture {
    private let writer: TapFileWriter
    private let router: TapRouter
    private let makeCapture: (URL) -> TapCaptureAdapter
    private var stopped = false

    init(writer: TapFileWriter, router: TapRouter, makeCapture: @escaping (URL) -> TapCaptureAdapter) {
        self.writer = writer
        self.router = router
        self.makeCapture = makeCapture
    }

    var isRecording: Bool {
        !stopped && writer.isRecording
    }

    func commit(to url: URL) throws -> any ActiveAudioCapture {
        guard !stopped else { throw CocoaError(.fileWriteUnknown) }
        let capture = makeCapture(url)
        try writer.persist(to: url, onEnd: capture.onWriterEnd)
        stopped = true
        return capture
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        router.detach(writer)
        writer.close()
    }
}

@MainActor
final class SystemAudioManager: AudioManaging {
    private var inputGraph = TyprAudioInput()
    private let audioSession = DictationAudioSession()
    private let exclusiveSession: () -> Bool
    private var keepaliveMicrophone: MicrophoneChoice?
    private var keepaliveInput: Microphone?
    private var keepaliveExclusive = false
    private let tapRouter = TapRouter()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?

    var isKeepaliveRunning: Bool {
        inputGraph.isRunning
    }

    var isOtherAudioPlaying: Bool {
        AVAudioSession.sharedInstance().isOtherAudioPlaying
    }

    /// `exclusiveSession`: Typr exclusive audio session, read at each activation.
    init(exclusiveSession: @escaping () -> Bool) {
        self.exclusiveSession = exclusiveSession
        installNotifications()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startKeepalive(microphone: MicrophoneChoice) throws {
        stopKeepalive()
        let exclusive = exclusiveSession()
        let input = try audioSession.activate(microphone: microphone, exclusive: exclusive)

        try inputGraph.start(bufferHandler: Self.tapBlock(routingTo: tapRouter))
        keepaliveMicrophone = microphone
        keepaliveInput = input
        keepaliveExclusive = exclusive
    }

    func ensureKeepalive(microphone: MicrophoneChoice) throws {
        if inputGraph.isRunning, keepaliveExclusive == exclusiveSession(),
           keepaliveMicrophone == microphone || keepaliveFollows(microphone) {
            return
        }
        try startKeepalive(microphone: microphone)
    }

    func keepaliveFollows(_ microphone: MicrophoneChoice) -> Bool {
        guard inputGraph.isRunning, let keepaliveMicrophone, keepaliveExclusive == exclusiveSession() else { return false }
        return keepaliveMicrophone.allowsBluetooth == microphone.allowsBluetooth
            && audioSession.input(for: microphone) == keepaliveInput
    }

    func stopKeepalive() {
        keepaliveMicrophone = nil
        keepaliveInput = nil
        inputGraph.stop()
    }

    func deactivateSession() {
        stopKeepalive()
        audioSession.deactivate()
    }

    func beginCapture(
        at url: URL,
        maxDuration: TimeInterval,
        microphone: MicrophoneChoice
    ) throws -> any ActiveAudioCapture {
        // Record from the keepalive input instead of switching to a recorder: stopping the
        // input after a capture and starting it again fails while Typr is in the background,
        // which ended the warm session after every keyboard dictation.
        try ensureKeepalive(microphone: microphone)

        let writer = try TapFileWriter(url: url, maxDuration: maxDuration)
        let capture = adapter(for: writer, at: url)
        writer.onEnd = capture.onWriterEnd
        tapRouter.attach(writer)
        return capture
    }

    func beginArmedCapture(maxDuration: TimeInterval, microphone: MicrophoneChoice) throws -> any ArmedAudioCapture {
        try ensureKeepalive(microphone: microphone)
        let writer = try TapFileWriter(maxDuration: maxDuration)
        tapRouter.attach(writer)
        return TapArmedCapture(writer: writer, router: tapRouter) { [unowned self] url in
            self.adapter(for: writer, at: url)
        }
    }

    private func adapter(for writer: TapFileWriter, at url: URL) -> TapCaptureAdapter {
        TapCaptureAdapter(url: url, writer: writer, router: tapRouter) { [weak self] finishedURL, ok in
            self?.onUnexpectedCaptureEnd?(finishedURL, ok)
        }
    }

    /// Built outside the main actor so the tap thread never runs a main-actor closure.
    nonisolated private static func tapBlock(routingTo router: TapRouter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            router.route(buffer)
        }
    }

    private func installNotifications() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    guard let self,
                          let typeRaw,
                          let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
                        return
                    }
                    switch type {
                    case .began:
                        self.onSystemEvent?(.interruptionBegan)
                    case .ended:
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
                        self.onSystemEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                    @unknown default:
                        break
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated {
                    guard let self,
                          let reasonRaw,
                          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
                        return
                    }
                    switch reason {
                    case .oldDeviceUnavailable:
                        self.onSystemEvent?(.routeOldDeviceUnavailable)
                    case .newDeviceAvailable:
                        self.onSystemEvent?(.routeNewDeviceAvailable)
                    default:
                        break
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inputGraph.stop()
                    self.inputGraph = TyprAudioInput()
                    self.onSystemEvent?(.mediaServicesReset)
                }
            }
        )
    }
}
