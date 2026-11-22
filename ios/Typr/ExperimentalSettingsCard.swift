import SwiftUI

struct ExperimentalSettingsCard: View {
    static let hexTitle = "Hex experiments"
    static let typrTitle = "Typr variants"
    static let emptyNotice = "No experiments right now."

    var hexExperiments = ExperimentalSwitch.hexExperiments
    var typrVariants = ExperimentalSwitch.typrVariants
    var defaults = UserDefaults(suiteName: KeyboardBridge.appGroup)

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
                ExperimentalToggle(experiment: experiment, settings: TyprSettings(defaults: defaults))
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
