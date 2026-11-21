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

    /// The input `choice` records from on the current route.
    func input(for choice: MicrophoneChoice) -> Microphone? {
        MicrophoneRoute.input(for: choice, from: availableInputs())
    }

    /// Always sets the input, so a preference from an earlier choice or route never sticks.
    /// Returns the input the route records from, which is iOS's choice when it refuses the
    /// preference: recording from another microphone beats not recording.
    @discardableResult
    func activate(microphone: MicrophoneChoice) throws -> Microphone? {
        try setCategory(.record, .measurement, MicrophoneRoute.categoryOptions(for: microphone))
        try setPreferredSampleRate(16_000)
        try setActive(true, [])
        try? setPreferredInput(input(for: microphone))
        return currentInput()
    }

    func deactivate() {
        try? setActive(false, .notifyOthersOnDeactivation)
    }
}
