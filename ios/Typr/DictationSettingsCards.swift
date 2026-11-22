import SwiftUI
@preconcurrency import Translation

extension DictationStyle {
    /// Hex's styles, or Typr's with Settings › Experimental › Typr dictation styles.
    func settingsDescription(typrStyles: Bool) -> String {
        switch self {
        case .polished where typrStyles: "Sentence case, clean punctuation and fewer fillers. For messages and longer text."
        case .polished: "Full sentences: fillers trimmed, each sentence capitalized and ended. For messages and longer text."
        case .typrCasual: "Chat text with natural capitalization, like typing with iPhone autocorrect. Drops the final period, even after several sentences; keeps question and exclamation marks."
        case .casual where typrStyles: "Lowercase chat text. Drops the final period, even after several sentences; keeps question and exclamation marks."
        case .casual: "Texting: sentences may start lowercase, and a short message has no final period. Acronyms and names keep their capitals."
        case .notes where typrStyles: "Turns spoken “bullet”, “new line” and “new paragraph” into bullets and line breaks. For lists and quick notes."
        case .notes: "Concise lines: spoken bullets and line breaks, else several sentences become a list, without final periods."
        case .verbatim: "Skips AI cleanup and style formatting. Vocabulary corrections, spaces instead of hyphens between words and basic spacing still apply."
        }
    }
}

/// A full-row selection target with enough room for decision copy and larger text.
struct SettingsChoiceRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: detail == nil ? .center : .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(TyprTheme.textBase)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    }
                }
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
    @State private var endsWithPeriod = TyprSettings().dictationEndsWithPeriod
    @State private var lowercase = TyprSettings().dictationLowercase
    @State private var formatLists = TyprSettings().dictationFormatLists
    @State private var spokenPunctuation = TyprSettings().dictationSpokenPunctuation
    private let typrStyles = DictationStyle.typrStylesEnabled
    private let typrFormattingRules = TyprSettings()[experiment: .typrGermanFormattingRules]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                let styles = DictationStyle.choices(typrStyles: typrStyles)
                ForEach(styles, id: \.self) { style in
                    if style != styles.first { SettingsDivider() }
                    SettingsChoiceRow(title: style.label(typrStyles: typrStyles),
                                      detail: style.settingsDescription(typrStyles: typrStyles),
                                      isSelected: dictation.style == style) {
                        dictation.setStyle(style)
                    }
                }
            }
            Text("AI cleanup, when enabled and available, runs before formatting in every style except Verbatim.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            SettingsSection {
                if !typrFormattingRules {
                    SettingsToggle(title: "Format lists",
                                   detail: "Say “first, second” or “bullet” for a list. English and Spanish.",
                                   isOn: $formatLists)
                        .onChange(of: formatLists) { _, isOn in TyprSettings().dictationFormatLists = isOn }
                    SettingsDivider()
                    SettingsToggle(title: "Spoken punctuation",
                                   detail: "Say “Komma” or “question mark” for the mark.",
                                   isOn: $spokenPunctuation)
                        .onChange(of: spokenPunctuation) { _, isOn in TyprSettings().dictationSpokenPunctuation = isOn }
                    SettingsDivider()
                }
                SettingsToggle(title: "End with a period",
                               detail: "Off: no line ends with a period. Question and exclamation marks stay.",
                               isOn: $endsWithPeriod)
                    .onChange(of: endsWithPeriod) { _, isOn in TyprSettings().dictationEndsWithPeriod = isOn }
                SettingsDivider()
                SettingsToggle(title: "Lowercase",
                               detail: "Lowercases everything, nouns and vocabulary included.",
                               isOn: $lowercase)
                    .onChange(of: lowercase) { _, isOn in TyprSettings().dictationLowercase = isOn }
            }
            Text("Lists, punctuation and the period apply to every style except Verbatim, from your next dictation.")
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
