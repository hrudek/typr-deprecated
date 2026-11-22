import SwiftUI
@preconcurrency import Translation

/// A full-row selection target for settings choices.
struct SettingsChoiceRow: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(TyprTheme.textBase)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TyprTheme.success)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
struct DictationStyleSettingsCard: View {
    @Bindable var dictation: DictationController
    @State private var lowercase = TyprSettings().dictationLowercase
    @State private var formatLists = TyprSettings().dictationFormatLists
    @State private var spokenPunctuation = TyprSettings().dictationSpokenPunctuation
    @State private var endsWithPeriod = TyprSettings().dictationEndsWithPeriod
    private let typrFormattingRules = TyprSettings()[experiment: .typrGermanFormattingRules]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                HStack(spacing: 12) {
                    Text("Style").font(.body).foregroundStyle(TyprTheme.textBase)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(DictationStyle.allCases, id: \.self) { candidate in
                            Button {
                                dictation.setStyle(candidate)
                            } label: {
                                if dictation.style == candidate {
                                    Label(candidate.label, systemImage: "checkmark")
                                } else {
                                    Text(candidate.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(dictation.style.label)
                            Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                        }
                        .font(.body).foregroundStyle(TyprTheme.textMuted)
                    }
                    .accessibilityIdentifier("dictation-style-menu")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                SettingsDivider()
                SettingsToggle(title: "Lowercase", detail: "No capital letters", isOn: $lowercase)
                    .onChange(of: lowercase) { _, isOn in TyprSettings().dictationLowercase = isOn }
                SettingsDivider()
                if !typrFormattingRules {
                    SettingsToggle(title: "Format lists",
                                   detail: "Say “first, second” or “bullet” for a list",
                                   isOn: $formatLists)
                        .onChange(of: formatLists) { _, isOn in TyprSettings().dictationFormatLists = isOn }
                    SettingsDivider()
                    SettingsToggle(title: "Spoken punctuation",
                                   detail: "Say “comma” or “question mark”",
                                   isOn: $spokenPunctuation)
                        .onChange(of: spokenPunctuation) { _, isOn in TyprSettings().dictationSpokenPunctuation = isOn }
                    SettingsDivider()
                }
                SettingsToggle(title: "End with a period", detail: "Off still keeps ? and !", isOn: $endsWithPeriod)
                    .onChange(of: endsWithPeriod) { _, isOn in TyprSettings().dictationEndsWithPeriod = isOn }
            }
            Text("AI cleanup, when enabled and available, runs before formatting in every style except Verbatim. Lists, punctuation and the period apply to every style except Verbatim, from your next dictation.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}

@MainActor
struct DictationLanguageSettingsCard: View {
    @Bindable var dictation: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    if language != DictationLanguage.allCases.first { SettingsDivider() }
                    SettingsChoiceRow(title: language.label,
                                      isSelected: dictation.dictationLanguage == language) {
                        dictation.setDictationLanguage(language)
                    }
                }
            }
            if let warning = SpeechEngineRowState.languageWarning(
                engine: dictation.preferredEngine ?? dictation.currentEngine,
                language: dictation.dictationLanguage
            ) {
                Label("Parakeet V2 is English only. \(warning)", systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(TyprTheme.warmMic)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            Text("Changes apply to your next dictation. Apple Speech may need to prepare the selected language on this iPhone.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            TranslateDictationSettingsCard()
        }
    }
}

/// Translate what I say (Hex #2015, #2176): the switch, German or English as the language to
/// insert, the one-time download of Apple's language pack, and why the last dictation went in
/// as spoken.
@MainActor
struct TranslateDictationSettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = TyprSettings().translateDictation
    @State private var target = TyprSettings().translationTarget
    @State private var failure = TyprSettings().translationFailure
    @State private var status: LanguageAvailability.Status?
    @State private var download: TranslationSession.Configuration?
    private let available = DictationTranslator.system != nil

    var body: some View {
        SettingsSection(title: "Translate what I say") {
            SettingsToggle(title: "Translate what I say", detail: toggleDetail, isOn: $enabled)
                .disabled(!available)
                .onChange(of: enabled) { _, value in TyprSettings().translateDictation = value }
            if enabled && available {
                SettingsDivider()
                Picker("Insert in", selection: $target) {
                    Text(DictationLanguage.german.label).tag(DictationLanguage.german)
                    Text(DictationLanguage.english.label).tag(DictationLanguage.english)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityIdentifier("translation-target")
                .onChange(of: target) { _, value in
                    TyprSettings().translationTarget = value
                    Task { await refreshStatus() }
                }
                SettingsDivider()
                packStatus
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .translationTask(download) { session in
            try? await session.prepareTranslation()
            await refreshStatus()
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            failure = TyprSettings().translationFailure
            Task { await refreshStatus() }
        }
    }

    private var toggleDetail: String {
        available ? "Speak German, insert English, or the other way round. Works offline once the languages are downloaded."
            : "Needs iOS 26."
    }

    private var source: DictationLanguage { target == .english ? .german : .english }

    @ViewBuilder private var packStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .installed:
                Text(failure == .failed ? "Couldn't translate the last dictation; it went in as spoken." : "Ready. Works offline.")
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            case .supported:
                Text(failure == nil ? "Download German and English once to translate offline."
                     : TranslationFailure.notDownloaded.note)
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                Button("Download languages") {
                    let configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: source.rawValue),
                        target: Locale.Language(identifier: target.rawValue))
                    if download == configuration {
                        download?.invalidate()
                    } else {
                        download = configuration
                    }
                }
                .accessibilityIdentifier("download-translation")
            case .unsupported:
                Text("Apple can't translate between German and English on this iPhone.")
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            default:
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshStatus() async {
        let current = await LanguageAvailability().status(
            from: Locale.Language(identifier: source.rawValue), to: Locale.Language(identifier: target.rawValue))
        status = current
        if current == .installed, failure == .notDownloaded {
            TyprSettings().translationFailure = nil
            failure = nil
        }
    }
}
