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
    @State private var spokenCleanup = TyprSettings().dictationSpokenCleanup
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
                SettingsDivider()
                SettingsToggle(title: "Clean up what I say",
                               detail: "Drops “äh” and “ähm”",
                               isOn: $spokenCleanup)
                    .onChange(of: spokenCleanup) { _, isOn in TyprSettings().dictationSpokenCleanup = isOn }
            }
            Text("AI cleanup, when enabled and available, runs before formatting in every style except Verbatim. Clean up what I say, lists, punctuation and the period apply to every style except Verbatim, from your next dictation.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}

/// Hex's Dictation language rows, German and English only: Automatic follows the keyboard
/// while it switches between them, and Switch dictation too moves a hand-picked language back
/// to Automatic when the space bar switches.
@MainActor
struct DictationLanguageSettingsCard: View {
    @Bindable var dictation: DictationController
    @State private var switchDictation = LanguageSettings().dictationFollowsKeyboard
    private let fixed = TyprSettings()[experiment: .typrFixedDictationLanguage]
    private let keyboardSwitches = LanguageSettings().keyboardLanguages.count > 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    if language != DictationLanguage.allCases.first { SettingsDivider() }
                    SettingsChoiceRow(title: title(of: language),
                                      isSelected: dictation.dictationLanguageChoice == language) {
                        dictation.setDictationLanguage(language)
                    }
                }
                if !fixed && keyboardSwitches {
                    SettingsDivider()
                    SettingsToggle(title: "Switch dictation too", detail: "Dictate in the keyboard's language",
                                   isOn: $switchDictation)
                        .onChange(of: switchDictation) { _, value in LanguageSettings().dictationFollowsKeyboard = value }
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
        .onAppear { dictation.followDictationLanguage() }
    }

    /// Automatic names the keyboard's language while dictation follows it.
    private func title(of language: DictationLanguage) -> String {
        guard language == .automatic, !fixed, dictation.dictationLanguageChoice == .automatic,
              dictation.dictationLanguage != .automatic else { return language.label }
        return "Automatic (\(dictation.dictationLanguage.label), follows the keyboard)"
    }
}

/// Translate what I say (Hex's `TranslateDictationRow`): the switch, the language to insert,
/// the one-time download of Apple's on-device language pack, and why the last dictation went in
/// as spoken, with its fix. The keyboard's note after such a dictation opens this page. Typr
/// offers German and English only.
@MainActor
struct TranslateDictationSettingsCard: View {
    @State private var enabled = DictationTranslationSettings().isEnabled
    @State private var target = DictationTranslationSettings().targetLanguage
    @State private var lastFailure = DictationTranslationSettings().lastFailure
    @State private var languages: [Locale.Language] = []
    @State private var status: LanguageAvailability.Status?
    @State private var download: TranslationSession.Configuration?
    private let typrPolicy = TyprSettings()[experiment: .typrTranslationPolicy]

    /// What the dictation is translated into: German or English under the Typr policy.
    private var effectiveTarget: Locale.Language {
        Locale.Language(identifier: typrPolicy ? TyprDictationTranslator.target(for: target).rawValue : target)
    }

    /// What you dictate in: the language of the dictation that last went in as spoken, else
    /// Settings › Language, or the language it last resolved.
    private var source: Locale.Language {
        if let lastFailure, lastFailure.target == effectiveTarget.minimalIdentifier {
            return Locale.Language(identifier: lastFailure.source)
        }
        if typrPolicy {
            return Locale.Language(identifier: effectiveTarget.languageCode == .german ? "en" : "de")
        }
        let language = LanguageSettings().typrDictationLanguage(typr: TyprSettings()).whisperLanguageCode
            ?? LanguageSettings().effectiveDictationLanguage()
        return language.map { Locale(identifier: $0).language } ?? Locale.current.language
    }

    var body: some View {
        SettingsSection(title: "Translate what I say") {
            SettingsToggle(title: "Translate what I say", detail: "Speak one language, insert another", isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    let settings = DictationTranslationSettings()
                    if settings.isEnabled != value { settings.isEnabled = value }
                }
            if enabled {
                SettingsDivider()
                HStack {
                    Text("Insert in").font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    Spacer()
                    Menu {
                        ForEach(languages, id: \.minimalIdentifier) { language in
                            Button {
                                target = language.minimalIdentifier
                            } label: {
                                if effectiveTarget.minimalIdentifier == language.minimalIdentifier {
                                    Label(name(of: language), systemImage: "checkmark")
                                } else {
                                    Text(name(of: language))
                                }
                            }
                        }
                    } label: {
                        Text(name(of: effectiveTarget))
                    }
                    .accessibilityLabel("Insert in")
                    .accessibilityIdentifier("translation-target")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .onChange(of: target) { _, value in
                    DictationTranslationSettings().targetLanguage = value
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
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // The keyboard may have failed to translate, and the pack may have been removed in
            // iOS Settings meanwhile.
            reload()
            Task { await refreshStatus() }
        }
        .task {
            languages = [Locale.Language(identifier: "de"), Locale.Language(identifier: "en")]
                .sorted { name(of: $0) < name(of: $1) }
            await refreshStatus()
        }
    }

    @ViewBuilder private var packStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if effectiveTarget.languageCode == source.languageCode {
                note("You dictate in this language already. Choose another dictation language above.")
            } else {
                switch status {
                case .installed where lastFailure?.reason == .needsTyprOpen:
                    // Before iOS 26 the session lives in Typr's window (TranslationSessionHost).
                    note("On iOS 18, dictations translate only with Typr open.")
                case .installed where lastFailure?.reason == .failed:
                    // Apple's own pack is there but translating failed, as when its Translate
                    // app was removed.
                    note("Couldn't translate the last dictation. If it keeps happening, reinstall Apple's Translate app.")
                    downloadButton(again: true)
                case .installed:
                    note("Ready. Works offline.")
                case .supported:
                    if lastFailure != nil { note(TranslationFailure.note) }
                    downloadButton(again: false)
                case .unsupported:
                    note("Apple can't translate between these languages.")
                default:
                    EmptyView()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
    }

    private func reload() {
        let settings = DictationTranslationSettings()
        enabled = settings.isEnabled
        target = settings.targetLanguage
        lastFailure = settings.lastFailure
    }

    /// Asks Apple to download the pair. Asking again for the same pair invalidates the last
    /// request, or `translationTask` would not run it again after a cancelled download.
    private func downloadButton(again: Bool) -> some View {
        let language = name(of: Locale.Language(identifier: lastFailure?.language ?? effectiveTarget.minimalIdentifier))
        return Button(again ? "Download \(language) again" : "Download \(language)") {
            let configuration = TranslationSession.Configuration(source: source, target: effectiveTarget)
            if download == configuration {
                download?.invalidate()
            } else {
                download = configuration
            }
        }
        .accessibilityIdentifier("download-translation")
    }

    private func refreshStatus() async {
        let current = await LanguageAvailability().status(from: source, to: effectiveTarget)
        status = current
        // Downloaded now: the note about a missing pack is out of date.
        if current == .installed, lastFailure?.reason == .notDownloaded {
            DictationTranslationSettings().lastFailure = nil
            lastFailure = nil
        }
    }

    private func name(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
