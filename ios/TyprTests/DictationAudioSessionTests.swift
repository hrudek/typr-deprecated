import AVFAudio
import XCTest
@testable import Typr

@MainActor
final class DictationAudioSessionTests: XCTestCase {
    private static let iPhone = Microphone(uid: "Built-In Microphone", port: .builtInMic)
    private static let car = Microphone(uid: "CarPlay", port: .carAudio)
    private static let airPods = Microphone(uid: "AirPods", port: .bluetoothHFP)
    private static let wired = Microphone(uid: "Wired Headset", port: .headsetMic)

    @MainActor
    private final class SessionSpy {
        var categories: [AVAudioSession.Category] = []
        var modes: [AVAudioSession.Mode] = []
        var options: [AVAudioSession.CategoryOptions] = []
        var activations: [Bool] = []
        var activationOptions: [AVAudioSession.SetActiveOptions] = []
        var sampleRates: [Double] = []
        var preferredInputs: [Microphone?] = []
        var inputs: [Microphone] = [DictationAudioSessionTests.iPhone]
        var current: Microphone? = DictationAudioSessionTests.iPhone
        var failCategory = false
        var refusePreferredInput = false

        func makeSession() -> DictationAudioSession {
            DictationAudioSession(setCategory: { category, mode, options in
                if self.failCategory { throw CocoaError(.coderInvalidValue) }
                self.categories.append(category)
                self.modes.append(mode)
                self.options.append(options)
            }, setPreferredSampleRate: {
                self.sampleRates.append($0)
            }, setActive: { active, options in
                self.activations.append(active)
                self.activationOptions.append(options)
            }, availableInputs: {
                self.inputs
            }, setPreferredInput: {
                self.preferredInputs.append($0)
                if self.refusePreferredInput { throw CocoaError(.coderInvalidValue) }
                self.current = $0
            }, currentInput: {
                self.current
            })
        }
    }

    func testExclusiveActivationUsesTyprsInputOnly16kHzSession() throws {
        let spy = SessionSpy()
        let session = spy.makeSession()
        try session.activate(microphone: .automatic, exclusive: true)
        XCTAssertEqual(spy.categories, [.record])
        XCTAssertEqual(spy.modes, [.measurement])
        XCTAssertEqual(spy.options, [[]])
        XCTAssertEqual(spy.sampleRates, [16_000])
        XCTAssertEqual(spy.activations, [true])
        XCTAssertEqual(spy.activationOptions, [[]])
    }

    func testOnlyBluetoothAllowsHandsFreeInputs() throws {
        for choice in MicrophoneChoice.allCases {
            for exclusive in [false, true] {
                let spy = SessionSpy()
                try spy.makeSession().activate(microphone: choice, exclusive: exclusive)
                XCTAssertEqual(spy.options.first?.contains(.allowBluetoothHFP), choice == .bluetooth, "\(choice), exclusive \(exclusive)")
            }
        }
    }

    func testActivationAlwaysSetsTheChoicesInput() throws {
        let spy = SessionSpy()
        spy.inputs = [Self.iPhone, Self.car]
        let session = spy.makeSession()
        XCTAssertEqual(try session.activate(microphone: .automatic), Self.car)
        XCTAssertEqual(try session.activate(microphone: .iPhone), Self.iPhone)
        spy.inputs = []
        XCTAssertNil(try session.activate(microphone: .automatic))
        XCTAssertEqual(spy.preferredInputs, [Self.car, Self.iPhone, nil], "an earlier preference never sticks")
    }

    func testRefusedInputReportsTheInputTheRouteRecordsFrom() throws {
        let spy = SessionSpy()
        spy.inputs = [Self.iPhone, Self.car]
        spy.current = Self.car
        spy.refusePreferredInput = true
        let session = spy.makeSession()
        XCTAssertEqual(try session.activate(microphone: .iPhone), Self.car)
        XCTAssertEqual(spy.activations, [true], "recording goes on from iOS's input")
    }

    func testReleaseNotifiesInterruptedAppsBeforeNextActivation() throws {
        let spy = SessionSpy()
        let session = spy.makeSession()
        try session.activate(microphone: .automatic)
        session.deactivate()
        XCTAssertEqual(spy.activations, [true, false])
        XCTAssertEqual(spy.activationOptions.last, .notifyOthersOnDeactivation)
        try session.activate(microphone: .automatic)
        XCTAssertEqual(spy.activations, [true, false, true])
        XCTAssertEqual(spy.categories, [.playAndRecord, .playAndRecord])
    }

    func testHexDefaultSessionMixesAndRecordsAtTheHardwaresRateWithoutDucking() throws {
        for choice in MicrophoneChoice.allCases {
            let spy = SessionSpy()
            try spy.makeSession().activate(microphone: choice)
            XCTAssertEqual(spy.categories, [.playAndRecord], "\(choice)")
            XCTAssertEqual(spy.modes, [.measurement], "\(choice)")
            let expected: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            XCTAssertEqual(spy.options, [choice == .bluetooth ? expected.union(.allowBluetoothHFP) : expected], "\(choice)")
            XCTAssertEqual(spy.sampleRates, [0], "\(choice): the hardware keeps its own rate")
            XCTAssertEqual(spy.activations, [true], "\(choice)")
        }
    }

    func testHexSessionAfterAnExclusiveRecordingClearsThe16kHzPreference() throws {
        let spy = SessionSpy()
        let session = spy.makeSession()
        try session.activate(microphone: .automatic, exclusive: true)
        session.deactivate()
        try session.activate(microphone: .automatic)
        XCTAssertEqual(spy.sampleRates, [16_000, 0])
        XCTAssertEqual(spy.categories, [.record, .playAndRecord])
        try session.activate(microphone: .automatic, exclusive: true)
        XCTAssertEqual(spy.sampleRates, [16_000, 0, 16_000], "switching back asks for 16 kHz again")
    }

    func testResampledCaptureIs16kHzMonoAtAnyHardwareRate() throws {
        for hardwareRate in [48_000.0, 44_100, 24_000, 16_000] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("resample-\(Int(hardwareRate))-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let writer = try TapFileWriter(url: url, maxDuration: 30)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: hardwareRate, channels: 2))
            let chunk = AVAudioFrameCount(hardwareRate / 10)
            for index in 0..<10 {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk))
                buffer.frameLength = chunk
                for channel in 0..<2 {
                    for frame in 0..<Int(chunk) {
                        let time = Double(index * Int(chunk) + frame) / hardwareRate
                        buffer.floatChannelData![channel][frame] = Float(0.3 * sin(2 * .pi * 220 * time))
                    }
                }
                writer.append(buffer)
            }
            writer.close()

            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000, "\(hardwareRate)")
            XCTAssertEqual(file.fileFormat.channelCount, 1, "\(hardwareRate)")
            XCTAssertEqual(Double(file.length), 16_000, accuracy: 400, "\(hardwareRate): one second")
        }
    }

    func testArmedWriterHoldsAudioInMemoryUntilPersisted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("armed-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TapFileWriter(maxDuration: 30)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        func appendSeconds(_ seconds: Int, to writer: TapFileWriter) throws {
            for _ in 0..<(seconds * 10) {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
                buffer.frameLength = 4_800
                for frame in 0..<4_800 { buffer.floatChannelData![0][frame] = 0.2 }
                writer.append(buffer)
            }
        }

        try appendSeconds(5, to: writer)
        XCTAssertEqual(writer.currentTime, TapFileWriter.heldLimit, accuracy: 0.1, "keeps only the newest audio")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try writer.persist(to: url, onEnd: { _ in })
        try appendSeconds(1, to: writer)
        writer.close()
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length), (TapFileWriter.heldLimit + 1) * 16_000, accuracy: 1_600)

        let dropped = try TapFileWriter(maxDuration: 30)
        try appendSeconds(1, to: dropped)
        dropped.close()
        XCTAssertThrowsError(try dropped.persist(to: url, onEnd: { _ in }), "a dropped arming cannot be written later")
    }

    func testCommitWhileTheTapAppendsNeverWaitsForTheFileAndKeepsTheOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("armed-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "armed-writer-test")
        let writer = try TapFileWriter(maxDuration: 30, queue: queue)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let chunks = 30
        var buffers: [AVAudioPCMBuffer] = []
        for index in 0..<chunks {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            for frame in 0..<4_800 { buffer.floatChannelData![0][frame] = Float(index + 1) / 40 }
            buffers.append(buffer)
        }
        let audio = HeldTestBuffers(buffers: buffers)

        queue.suspend()
        let half = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for (index, buffer) in audio.buffers.enumerated() {
                writer.append(buffer)
                if index == chunks / 3 { half.signal() }
            }
            done.signal()
        }
        XCTAssertEqual(half.wait(timeout: .now() + 5), .success)
        try writer.persist(to: url, onEnd: { _ in })
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success, "appends never wait for the file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "commit and appends did no file I/O")

        queue.resume()
        writer.close()
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length), 3 * 16_000, accuracy: 1_600)
        let read = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: read)
        let samples = read.floatChannelData![0]
        var previous: Float = 0
        for chunk in 0..<Int(read.frameLength) / 1_600 {
            let middle = samples[chunk * 1_600 + 800]
            XCTAssertGreaterThan(middle, previous, "chunk \(chunk) out of order")
            previous = middle
        }
    }

    func testAFullDiskAfterTheCommitFailsTheCaptureOnStopAndAtItsLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("armed-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        func appendSeconds(_ seconds: Double, to writer: TapFileWriter) throws {
            for _ in 0..<Int(seconds * 10) {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
                buffer.frameLength = 4_800
                for frame in 0..<4_800 { buffer.floatChannelData![0][frame] = 0.2 }
                writer.append(buffer)
            }
        }

        for space in [0, 8_000, 64_000] {
            let disk = FullDisk(capacity: space)
            let writer = try TapFileWriter(maxDuration: 30, openSink: { _ in disk })
            try appendSeconds(1, to: writer)
            try writer.persist(to: url, onEnd: { _ in })
            try appendSeconds(1, to: writer)
            writer.close()
            XCTAssertEqual(writer.didFailWriting, space < 32_000, "\(space) frames free")
            XCTAssertFalse(writer.isRecording)
        }

        let disk = FullDisk(capacity: 8_000)
        let ends = EndRecorder()
        let queue = DispatchQueue(label: "full-disk-test")
        let limited = try TapFileWriter(maxDuration: 1, queue: queue, openSink: { _ in disk })
        queue.suspend()
        try appendSeconds(0.5, to: limited)
        try limited.persist(to: url, onEnd: { ends.record($0) })
        try appendSeconds(1, to: limited)
        queue.resume()
        limited.close()
        XCTAssertEqual(ends.values.first, true, "the limit is reached before the queued write fails")
        XCTAssertTrue(limited.didFailWriting, "so the drained writer reports the lost audio")
    }

    func testConfigurationFailureDoesNotActivateAnUnknownSession() {
        let spy = SessionSpy()
        let session = spy.makeSession()
        spy.failCategory = true
        XCTAssertThrowsError(try session.activate(microphone: .automatic))
        XCTAssertTrue(spy.activations.isEmpty)
        XCTAssertTrue(spy.preferredInputs.isEmpty)
    }

    func testEachChoicePicksItsInputOnEachRoute() {
        let routes: [(String, [Microphone], [MicrophoneChoice: Microphone])] = [
            ("iPhone only", [Self.iPhone], [.automatic: Self.iPhone, .iPhone: Self.iPhone, .bluetooth: Self.iPhone]),
            ("CarPlay", [Self.iPhone, Self.car], [.automatic: Self.car, .iPhone: Self.iPhone, .bluetooth: Self.car]),
            ("AirPods", [Self.iPhone, Self.airPods], [.automatic: Self.iPhone, .iPhone: Self.iPhone, .bluetooth: Self.airPods]),
            ("wired headset", [Self.iPhone, Self.wired], [.automatic: Self.wired, .iPhone: Self.iPhone, .bluetooth: Self.wired]),
        ]
        for (name, inputs, expected) in routes {
            for choice in MicrophoneChoice.allCases {
                XCTAssertEqual(MicrophoneRoute.capture(choice, from: inputs), expected[choice], "\(choice) on \(name)")
            }
        }
        XCTAssertNil(MicrophoneRoute.capture(.iPhone, from: [Self.car]))
    }
}

private struct HeldTestBuffers: @unchecked Sendable {
    let buffers: [AVAudioPCMBuffer]
}

private final class FullDisk: CaptureFileSink, @unchecked Sendable {
    private let lock = NSLock()
    private var free: Int

    init(capacity: Int) {
        free = capacity
    }

    func write(from buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard Int(buffer.frameLength) <= free else { throw POSIXError(.ENOSPC) }
        free -= Int(buffer.frameLength)
    }
}

private final class EndRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ value: Bool) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
}
