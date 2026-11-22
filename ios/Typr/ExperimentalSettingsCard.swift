import SwiftUI

struct ExperimentalSettingsCard: View {
    static let hexTitle = "Hex experiments"
    static let typrTitle = "Typr variants"
    static let emptyNotice = "No experiments right now."

    var hexExperiments = ExperimentalSwitch.hexExperiments
    var typrVariants = ExperimentalSwitch.typrVariants
    var defaults = UserDefaults(suiteName: KeyboardBridge.appGroup)
    var dictation: DictationController?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            group(Self.hexTitle, switches: hexExperiments)
            group(Self.typrTitle, switches: typrVariants)
        }
    }

    private func group(_ title: String, switches: [ExperimentalSwitch]) -> some View {
        SettingsSection(title: title) {
            if switches.isEmpty {
                Text(Self.emptyNotice)
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            ForEach(Array(switches.enumerated()), id: \.element) { index, experiment in
                if index > 0 { SettingsDivider() }
                if experiment == .multilingualParakeet {
                    MultilingualParakeetToggle(settings: TyprSettings(defaults: defaults), dictation: dictation)
                } else {
                    ExperimentalToggle(experiment: experiment, settings: TyprSettings(defaults: defaults))
                }
            }
        }
    }
}

struct ExperimentalToggle: View {
    let experiment: ExperimentalSwitch
    let settings: TyprSettings
    @State private var isOn: Bool

    init(experiment: ExperimentalSwitch, settings: TyprSettings) {
        self.experiment = experiment
        self.settings = settings
        _isOn = State(initialValue: settings[experiment: experiment])
    }

    var body: some View {
        SettingsToggle(title: experiment.title, detail: experiment.detail, isOn: $isOn)
            .onChange(of: isOn) { _, enabled in settings[experiment: experiment] = enabled }
    }
}

/// Hex's multilingual model switch: downloads Parakeet Ultra when turned on, deletes it when
/// turned off, and shows the download or load beneath it.
struct MultilingualParakeetToggle: View {
    static let doesNotFitDetail = "Needs an iPhone with 6 GB of memory or more."

    let settings: TyprSettings
    let dictation: DictationController?
    private let fits = MultilingualParakeetSettings.fits()
    @State private var isOn: Bool

    init(settings: TyprSettings, dictation: DictationController?) {
        self.settings = settings
        self.dictation = dictation
        _isOn = State(initialValue: settings[experiment: .multilingualParakeet])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(
                title: ExperimentalSwitch.multilingualParakeet.title,
                detail: fits ? ExperimentalSwitch.multilingualParakeet.detail : Self.doesNotFitDetail,
                isOn: $isOn
            )
            .disabled(!fits)
            .onChange(of: isOn) { _, enabled in
                guard enabled != settings[experiment: .multilingualParakeet] else { return }
                settings[experiment: .multilingualParakeet] = enabled
                dictation?.multilingualParakeetChanged()
            }
            if isOn, let dictation {
                MultilingualModelStatus(
                    download: dictation.multilingualDownload,
                    retry: { dictation.retryMultilingualParakeet() },
                    turnOff: { isOn = false }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .onAppear { isOn = settings[experiment: .multilingualParakeet] }
    }
}
