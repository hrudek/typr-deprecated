import SwiftUI

/// Rows from Hex 0c1c13d7 `ios/HEXMobile/SettingsPages.swift`.
struct HexKeyboardKeysSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private let defaults: UserDefaults?
    @State private var keyPopups: Bool
    @State private var haptics: Bool
    @State private var hapticStrength: KeyHapticStrength
    @State private var emoji: Bool
    @State private var emojiHistoryEmpty: Bool

    static let hapticsDetail = "Needs Full Access."

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
        let hex = FullKeyboardSettings(defaults: defaults)
        _keyPopups = State(initialValue: hex.keyPopups)
        _haptics = State(initialValue: hex.haptics)
        _hapticStrength = State(initialValue: hex.hapticStrength)
        _emoji = State(initialValue: hex.emoji)
        _emojiHistoryEmpty = State(initialValue: EmojiUsageStore(defaults: defaults).isEmpty)
    }

    private var hex: FullKeyboardSettings { FullKeyboardSettings(defaults: defaults) }

    var body: some View {
        SettingsSection(title: "Keys") {
            SettingsToggle(title: "Key pop-ups", detail: "Shows the letter above your finger.", isOn: $keyPopups)
                .onChange(of: keyPopups) { _, enabled in hex.keyPopups = enabled }
            SettingsDivider()
            SettingsToggle(title: "Haptics", detail: Self.hapticsDetail, isOn: $haptics)
                .onChange(of: haptics) { _, enabled in hex.haptics = enabled }
            if haptics {
                SettingsDivider()
                HStack(spacing: 12) {
                    Text("Strength").font(.body).foregroundStyle(TyprTheme.textBase)
                    Spacer(minLength: 8)
                    Picker("Strength", selection: $hapticStrength) {
                        ForEach(KeyHapticStrength.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("haptic-strength")
                }
                .padding(16)
                .onChange(of: hapticStrength) { _, strength in hex.hapticStrength = strength }
            }
            SettingsDivider()
            SettingsToggle(title: "Emoji", detail: "Emoji key and suggestions.", isOn: $emoji)
                .onChange(of: emoji) { _, enabled in hex.emoji = enabled }
            if emoji {
                SettingsDivider()
                Button("Clear emoji history") {
                    EmojiUsageStore(defaults: defaults).clear()
                    emojiHistoryEmpty = true
                }
                .disabled(emojiHistoryEmpty)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 16)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        keyPopups = hex.keyPopups
        haptics = hex.haptics
        hapticStrength = hex.hapticStrength
        emoji = hex.emoji
        emojiHistoryEmpty = EmojiUsageStore(defaults: defaults).isEmpty
    }
}

struct HexDictationBarSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private let defaults: UserDefaults?
    @State private var autoStart: DictationBarAutoStart

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
        _autoStart = State(initialValue: FullKeyboardSettings(defaults: defaults).dictationBarAutoStart)
    }

    private var hex: FullKeyboardSettings { FullKeyboardSettings(defaults: defaults) }

    var body: some View {
        SettingsSection(title: "Dictation bar") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-start").font(.body).foregroundStyle(TyprTheme.textBase)
                    Text(autoStart.detail).font(.footnote).foregroundStyle(TyprTheme.textMuted)
                }
                Spacer(minLength: 8)
                Picker("Auto-start", selection: $autoStart) {
                    ForEach(DictationBarAutoStart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("dictation-bar-auto-start")
            }
            .padding(16)
            .onChange(of: autoStart) { _, choice in hex.dictationBarAutoStart = choice }
        }
        .onAppear { autoStart = hex.dictationBarAutoStart }
        .onChange(of: scenePhase) { _, phase in if phase == .active { autoStart = hex.dictationBarAutoStart } }
    }
}

extension DictationBarAutoStart {
    var label: String {
        switch self {
        case .never: "Never"
        case .whenSwitching: "On switch"
        case .always: "Always"
        }
    }

    var detail: String {
        switch self {
        case .never: "Tap Dictate to start"
        case .whenSwitching: "When you switch to Typr"
        case .always: "Each time the dictation bar opens"
        }
    }
}

extension KeyHapticStrength {
    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}

struct HexKeyboardLearningSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private let defaults: UserDefaults?
    @State private var learnTyping: Bool
    @State private var adaptiveTouch: Bool
    @State private var adaptiveTouchStatus: AdaptiveTouchStatus
    @State private var confirmTouchReset = false

    static let learnDetail = "Learns on this iPhone from your taps and the words you fix."

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
        _learnTyping = State(initialValue: TypingJournalSettings(defaults: defaults).isEnabled)
        _adaptiveTouch = State(initialValue: AdaptiveTouchSettings(defaults: defaults).isEnabled)
        _adaptiveTouchStatus = State(initialValue: Self.status(defaults: defaults))
    }

    static func status(defaults: UserDefaults?) -> AdaptiveTouchStatus {
        AdaptiveTouchStatus.current(
            settings: AdaptiveTouchSettings(defaults: defaults),
            fullAccessConfirmed: KeyboardBridge(defaults: defaults).fullAccessSeenAt != nil
        )
    }

    static func statusText(_ status: AdaptiveTouchStatus) -> String {
        switch status {
        case .sessionOnly: "Without Full Access, resets when the keyboard closes."
        case .learning(let taps): "Learning: \(taps) of \(AdaptiveTouchModel.activeTaps) taps."
        case .active: "Active, using your own key centers."
        }
    }

    var body: some View {
        SettingsSection(title: "Learning") {
            SettingsToggle(title: "Learn how I type", detail: Self.learnDetail, isOn: $learnTyping)
                .onChange(of: learnTyping) { _, enabled in TypingJournalSettings(defaults: defaults).isEnabled = enabled }
            if adaptiveTouch {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Adaptive touch").font(.body).foregroundStyle(TyprTheme.textBase)
                    Text(Self.statusText(adaptiveTouchStatus)).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                        .accessibilityIdentifier("adaptive-touch-status")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                SettingsDivider()
                Button("Reset touch learning", role: .destructive) { confirmTouchReset = true }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .confirmationDialog("Reset touch learning?", isPresented: $confirmTouchReset, titleVisibility: .visible) {
            Button("Reset touch learning", role: .destructive) {
                AdaptiveTouchSettings(defaults: defaults).requestReset()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        learnTyping = TypingJournalSettings(defaults: defaults).isEnabled
        adaptiveTouch = AdaptiveTouchSettings(defaults: defaults).isEnabled
        adaptiveTouchStatus = Self.status(defaults: defaults)
    }
}
