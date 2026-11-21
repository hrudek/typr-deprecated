import AVFAudio

nonisolated struct Microphone: Equatable, Sendable {
    let uid: String
    let port: AVAudioSession.Port
}

nonisolated enum MicrophoneRoute {
    /// iOS reports a Bluetooth car kit like headphones, so only `bluetooth` reaches it.
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
