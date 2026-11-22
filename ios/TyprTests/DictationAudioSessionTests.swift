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

    func testActivationUsesProvenInputOnlyMeasurementSession() throws {
        let spy = SessionSpy()
        let session = spy.makeSession()
        try session.activate(microphone: .automatic)
        XCTAssertEqual(spy.categories, [.record])
        XCTAssertEqual(spy.modes, [.measurement])
        XCTAssertEqual(spy.options, [[]])
        XCTAssertEqual(spy.sampleRates, [16_000])
        XCTAssertEqual(spy.activations, [true])
        XCTAssertEqual(spy.activationOptions, [[]])
    }

    func testOnlyBluetoothAllowsHandsFreeInputs() throws {
        for choice in MicrophoneChoice.allCases {
            let spy = SessionSpy()
            try spy.makeSession().activate(microphone: choice)
            XCTAssertEqual(spy.options, [choice == .bluetooth ? [.allowBluetoothHFP] : []], "\(choice)")
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
        XCTAssertEqual(spy.options, [[], []])
    }

    func testMixingSessionPlaysAndRecordsAtTheHardwaresRateWithoutDucking() throws {
        for choice in MicrophoneChoice.allCases {
            let spy = SessionSpy()
            try spy.makeSession().activate(microphone: choice, mixWithOthers: true)
            XCTAssertEqual(spy.categories, [.playAndRecord], "\(choice)")
            XCTAssertEqual(spy.modes, [.measurement], "\(choice)")
            let expected: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            XCTAssertEqual(spy.options, [choice == .bluetooth ? expected.union(.allowBluetoothHFP) : expected], "\(choice)")
            XCTAssertEqual(spy.sampleRates, [0], "\(choice): the hardware keeps its own rate")
            XCTAssertEqual(spy.activations, [true], "\(choice)")
        }
    }

    func testMixingAfterADefaultRecordingClearsThe16kHzPreference() throws {
        let spy = SessionSpy()
        let session = spy.makeSession()
        try session.activate(microphone: .automatic)
        session.deactivate()
        try session.activate(microphone: .automatic, mixWithOthers: true)
        XCTAssertEqual(spy.sampleRates, [16_000, 0])
        XCTAssertEqual(spy.categories, [.record, .playAndRecord])
        try session.activate(microphone: .automatic)
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
                XCTAssertEqual(MicrophoneRoute.input(for: choice, from: inputs), expected[choice], "\(choice) on \(name)")
            }
        }
        XCTAssertNil(MicrophoneRoute.input(for: .iPhone, from: [Self.car]))
    }
}
