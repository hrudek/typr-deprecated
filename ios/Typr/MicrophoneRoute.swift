import AVFAudio

nonisolated struct Microphone: Equatable, Sendable {
    let uid: String
    let port: AVAudioSession.Port
}

/// Which of the inputs iOS offers a dictation and the warm session record from (Hex
/// `MicrophoneRoute`, anomalyco/hex 0c1c13d7).
nonisolated enum MicrophoneRoute {
    /// The input a dictation records from; nil when none of the choice's kinds is offered.
    ///
    /// Automatic takes a wired or USB headset's microphone and, in CarPlay, the car's. iOS
    /// reports a Bluetooth car kit like headphones, so only `bluetooth` reaches it.
    static func capture(_ choice: MicrophoneChoice, from inputs: [Microphone]) -> Microphone? {
        let order: [AVAudioSession.Port] = switch choice {
        case .iPhone: [.builtInMic]
        case .automatic: [.headsetMic, .usbAudio, .carAudio, .builtInMic]
        case .bluetooth: [.headsetMic, .usbAudio, .carAudio, .bluetoothHFP, .bluetoothLE, .builtInMic]
        }
        for port in order {
            if let input = inputs.first(where: { $0.port == port }) { return input }
        }
        return nil
    }

    /// The category options for recording: `.mixWithOthers` keeps other apps' video and music
    /// playing, and A2DP keeps headphones in stereo while another microphone records.
    /// Bluetooth hands-free inputs are offered only when allowed; taking one puts the headset
    /// or car into call audio.
    static func categoryOptions(allowingBluetooth: Bool) -> AVAudioSession.CategoryOptions {
        allowingBluetooth
            ? [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
            : [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
    }

    /// Typr exclusive audio session: `.record` interrupts other audio and has no output.
    static func exclusiveCategoryOptions(allowingBluetooth: Bool) -> AVAudioSession.CategoryOptions {
        allowingBluetooth ? [.allowBluetoothHFP] : []
    }
}
