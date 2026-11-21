import AVFAudio

/// An input iOS offers (`AVAudioSessionPortDescription`), as a value tests can make.
nonisolated struct Microphone: Equatable, Sendable {
    let uid: String
    let port: AVAudioSession.Port
}

nonisolated enum MicrophoneRoute {
    /// The input a dictation records from; nil when none of the choice's kinds is offered.
    /// In CarPlay the car's microphone is the one it has for its driver, which Siri and calls
    /// use. A Bluetooth car kit can't be told from headphones, so it needs `bluetooth`.
    static func input(for choice: MicrophoneChoice, from inputs: [Microphone]) -> Microphone? {
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

    /// Bluetooth hands-free inputs are offered only with this option, and taking one puts the
    /// headset or car into call audio.
    static func categoryOptions(for choice: MicrophoneChoice) -> AVAudioSession.CategoryOptions {
        choice == .bluetooth ? [.allowBluetoothHFP] : []
    }
}
