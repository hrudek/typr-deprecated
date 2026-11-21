import AVFAudio

/// Keep the proven input-only session stable for the lifetime of the input graph.
/// The controller decides whether to retain it or fully deactivate after capture.
@MainActor
final class DictationAudioSession {
    private let setCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void
    private let setPreferredSampleRate: (Double) throws -> Void
    private let setActive: (Bool, AVAudioSession.SetActiveOptions) throws -> Void
    private let availableInputs: () -> [Microphone]
    private let setPreferredInput: (Microphone?) throws -> Void
    private let currentInput: () -> Microphone?

    init(
        setCategory: @escaping (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void = {
            try AVAudioSession.sharedInstance().setCategory($0, mode: $1, options: $2)
        },
        setPreferredSampleRate: @escaping (Double) throws -> Void = {
            try AVAudioSession.sharedInstance().setPreferredSampleRate($0)
        },
        setActive: @escaping (Bool, AVAudioSession.SetActiveOptions) throws -> Void = {
            try AVAudioSession.sharedInstance().setActive($0, options: $1)
        },
        availableInputs: @escaping () -> [Microphone] = {
            (AVAudioSession.sharedInstance().availableInputs ?? []).map {
                Microphone(uid: $0.uid, port: $0.portType)
            }
        },
        setPreferredInput: @escaping (Microphone?) throws -> Void = { wanted in
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredInput(wanted.flatMap { wanted in
                session.availableInputs?.first { $0.uid == wanted.uid }
            })
        },
        currentInput: @escaping () -> Microphone? = {
            AVAudioSession.sharedInstance().currentRoute.inputs.first.map {
                Microphone(uid: $0.uid, port: $0.portType)
            }
        }
    ) {
        self.setCategory = setCategory
        self.setPreferredSampleRate = setPreferredSampleRate
        self.setActive = setActive
        self.availableInputs = availableInputs
        self.setPreferredInput = setPreferredInput
        self.currentInput = currentInput
    }

    func input(for choice: MicrophoneChoice) -> Microphone? {
        MicrophoneRoute.input(for: choice, from: availableInputs())
    }

    /// Returns the input the route records from: iOS keeps its own when it refuses the preference.
    ///
    /// `mixWithOthers` uses `.playAndRecord`, which runs input and output at one hardware rate,
    /// so it clears the preferred sample rate (an earlier `.record` activation's 16 kHz otherwise
    /// stays for the process; 0 is undocumented as "none", so a refusal must not stop recording): 16 kHz would move every app's playback and
    /// recording (a screen recording too) to 16 kHz while Typr holds the session. The tap
    /// writer resamples to 16 kHz itself. Never `.duckOthers`: iOS lifts ducking only on
    /// deactivation.
    @discardableResult
    func activate(microphone: MicrophoneChoice, mixWithOthers: Bool = false) throws -> Microphone? {
        let options = MicrophoneRoute.categoryOptions(for: microphone)
        if mixWithOthers {
            try setCategory(.playAndRecord, .measurement, options.union([.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]))
            try? setPreferredSampleRate(0)
        } else {
            try setCategory(.record, .measurement, options)
            try setPreferredSampleRate(16_000)
        }
        try setActive(true, [])
        try? setPreferredInput(input(for: microphone))
        return currentInput()
    }

    func deactivate() {
        try? setActive(false, .notifyOthersOnDeactivation)
    }
}
