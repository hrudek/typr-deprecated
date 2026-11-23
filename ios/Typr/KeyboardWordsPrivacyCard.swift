import SwiftUI

struct KeyboardWordsPrivacyCard: View {
    @Environment(\.scenePhase) private var scenePhase
    private let defaults: UserDefaults?
    @State private var personalLearning: Bool
    @State private var typrKeyboard: Bool

    static let whatTyprLearns = "Typr adapts to your taps, chosen words, recent German/English usage and what follows one or two words. Undo remembers rejected corrections and their preceding words. Imported names and terms work independently of this switch."

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
        let typr = TyprSettings(defaults: defaults)
        _personalLearning = State(initialValue: typr.personalLearning)
        _typrKeyboard = State(initialValue: typr[experiment: .typrKeyboard])
    }

    var body: some View {
        VStack(spacing: 24) {
            if !typrKeyboard {
                HexKeyboardLearningSection(defaults: defaults)
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: typrKeyboard ? "Learning" : "Typr keyboard learning") {
                    SettingsToggle(title: "Learn from my typing", detail: "Adapt to your taps and word choices.", isOn: $personalLearning)
                        .onChange(of: personalLearning) { _, enabled in TyprSettings(defaults: defaults).personalLearning = enabled }
                    SettingsDivider()
                    NavigationLink(value: SettingsDestination.keyboardLearnedWords) {
                        SettingsLink(title: "Manage learned words", detail: "Find and delete saved words and corrections")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    SettingsDisclosure(title: "What Typr learns", text: Self.whatTyprLearns)
                }
                SettingsFooter("Turning this off keeps saved learning.")
            }
            PersonalLexiconSettingsCard()
            KeyboardLearningResetControls()
            TypingLogControls()
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        let typr = TyprSettings(defaults: defaults)
        personalLearning = typr.personalLearning
        typrKeyboard = typr[experiment: .typrKeyboard]
    }
}
