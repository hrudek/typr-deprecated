import SwiftUI

struct ExperimentalSettingsCard: View {
    static let hexTitle = "Hex experiments"
    static let hexKeyboardTitle = "Hex keyboard experiments"
    static let hexKeyboardNotice = "These apply to the full keyboard, except while Typr keyboard is on under Typr variants."
    static let typrTitle = "Typr variants"
    static let emptyNotice = "No experiments right now."

    var hexExperiments = ExperimentalSwitch.hexExperiments
    var hexKeyboardExperiments = ExperimentalSwitch.hexKeyboardExperiments
    var typrVariants = ExperimentalSwitch.typrVariants
    var defaults = UserDefaults(suiteName: KeyboardBridge.appGroup)
    var dictation: DictationController?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            group(Self.hexTitle, switches: hexExperiments)
            group(Self.hexKeyboardTitle, switches: hexKeyboardExperiments, notice: Self.hexKeyboardNotice)
            group(Self.typrTitle, switches: typrVariants)
        }
    }

    private func group(_ title: String, switches: [ExperimentalSwitch], notice: String? = nil) -> some View {
        SettingsSection(title: title) {
            if let notice, !switches.isEmpty {
                Text(notice)
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                SettingsDivider()
            }
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
                } else if experiment == .hexKeyboardThemes {
                    KeyboardThemesToggle(defaults: defaults)
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

/// Hex's Keyboard themes switch and, while it is on, the theme the Hex keyboard draws.
struct KeyboardThemesToggle: View {
    let defaults: UserDefaults?
    @State private var isOn: Bool
    @State private var theme: KeyboardTheme

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let settings = FullKeyboardSettings(defaults: defaults)
        _isOn = State(initialValue: settings.keyboardThemesEnabled)
        _theme = State(initialValue: settings.keyboardTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(title: ExperimentalSwitch.hexKeyboardThemes.title, detail: ExperimentalSwitch.hexKeyboardThemes.detail, isOn: $isOn)
                .onChange(of: isOn) { _, enabled in FullKeyboardSettings(defaults: defaults).keyboardThemesEnabled = enabled }
            if isOn {
                SettingsDivider()
                Picker("Theme", selection: $theme) {
                    ForEach(KeyboardTheme.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .onChange(of: theme) { _, choice in FullKeyboardSettings(defaults: defaults).keyboardTheme = choice }
            }
        }
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
