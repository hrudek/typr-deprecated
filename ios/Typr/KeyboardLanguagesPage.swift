import SwiftUI
import UIKit

// Hex's Settings › Keyboard › Languages (anomalyco/hex 0c1c13d7, HEXMobile/LanguageSettingsRows.swift),
// for Hex's full keyboard: Typr colours, no Switch dictation too (D7 owns language follow).

@MainActor
func automaticKeyboardLanguage(settings: LanguageSettings = LanguageSettings()) -> KeyboardLanguage {
    KeyboardLanguage.automatic(
        dictationLanguage: settings.effectiveDictationLanguage(),
        inputModes: UITextInputMode.activeInputModes.compactMap(\.primaryLanguage),
        preferredLanguages: Locale.preferredLanguages
    )
}

struct KeyboardLanguagesRow: View {
    @State private var chosen = LanguageSettings().keyboardLanguages
    @State private var showsPage = false

    static func summary(chosen: [KeyboardLanguage], automatic: KeyboardLanguage) -> String {
        chosen.isEmpty ? "\(automatic.displayName), same as dictation" : chosen.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        Button {
            showsPage = true
        } label: {
            SettingsLink(title: "Languages", detail: "Languages and letter layouts",
                         value: Self.summary(chosen: chosen, automatic: automaticKeyboardLanguage()))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keyboard-languages")
        .navigationDestination(isPresented: $showsPage) {
            KeyboardLanguagesPage()
        }
        .onAppear { chosen = LanguageSettings().keyboardLanguages }
        .onChange(of: showsPage) { _, shown in
            if !shown { chosen = LanguageSettings().keyboardLanguages }
        }
    }
}

struct KeyboardLanguagesPage: View {
    @State private var chosen = LanguageSettings().keyboardLanguages
    @State private var letterLayouts = LanguageSettings().letterLayouts
    private let automatic = automaticKeyboardLanguage()
    private let suggested = KeyboardLanguage.suggested(
        inputModes: UITextInputMode.activeInputModes.compactMap(\.primaryLanguage),
        preferred: Locale.preferredLanguages
    )

    var body: some View {
        let onPhone = suggested.filter { !chosen.contains($0) }
        let others = KeyboardLanguage.selectable().filter { !chosen.contains($0) && !onPhone.contains($0) }
        List {
            Section {
                LanguageChoiceRow(title: "Automatic", detail: "\(automatic.displayName), same as dictation",
                                  isChosen: chosen.isEmpty) {
                    choose([])
                }
            }

            if !chosen.isEmpty {
                Section {
                    ForEach(chosen, id: \.self) { language in
                        languageRow(language)
                    }
                    .onMove { from, to in
                        var next = chosen
                        next.move(fromOffsets: from, toOffset: to)
                        choose(next)
                    }
                    // A row added in edit mode gets no drag handle until its rows are rebuilt.
                    .id(chosen.map(\.rawValue).joined(separator: ","))
                } footer: {
                    if chosen.count > 1 {
                        LanguageSectionFooter(text: "Slide the space bar to switch. Hold it first to move the cursor.")
                    }
                }
            }

            let arranged = Self.arranged(chosen: chosen, automatic: automatic)
            if !arranged.isEmpty {
                Section {
                    ForEach(arranged, id: \.self) { language in
                        layoutRow(language)
                    }
                } header: {
                    LanguageSectionHeader(title: "Layout")
                } footer: {
                    LanguageSectionFooter(text: "Accents and autocorrect still follow the language.")
                }
            }

            if !onPhone.isEmpty {
                Section {
                    ForEach(onPhone, id: \.self) { language in
                        languageRow(language)
                    }
                } header: {
                    LanguageSectionHeader(title: "On this iPhone")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.self) { language in
                        languageRow(language)
                    }
                } header: {
                    LanguageSectionHeader(title: "More languages")
                }
            }
        }
        // Always in edit mode, so the chosen languages show their drag handles.
        .environment(\.editMode, .constant(.active))
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .background(TyprTheme.bgDeep.ignoresSafeArea())
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TyprTheme.bgDeep, for: .navigationBar)
        .onAppear {
            chosen = LanguageSettings().keyboardLanguages
            letterLayouts = LanguageSettings().letterLayouts
        }
    }

    static func arranged(chosen: [KeyboardLanguage], automatic: KeyboardLanguage) -> [KeyboardLanguage] {
        let typing = chosen.isEmpty ? [automatic] : chosen
        var seen = Set<KeyboardLanguage>()
        return typing
            .map { KeyboardLanguageList(languages: typing, current: $0).layout }
            .filter { $0.letterLayouts.count > 1 && seen.insert($0).inserted }
    }

    private func layoutRow(_ language: KeyboardLanguage) -> some View {
        let current = language.offered(letterLayouts[language.rawValue].flatMap(KeyboardLetterLayout.init(rawValue:)))
        return HStack(spacing: 12) {
            Text(language.displayName).font(.body).foregroundStyle(TyprTheme.textBase)
            Spacer(minLength: 8)
            Menu {
                ForEach(language.letterLayouts, id: \.self) { letters in
                    Button {
                        LanguageSettings().setLetterLayout(letters, for: language)
                        letterLayouts = LanguageSettings().letterLayouts
                    } label: {
                        if letters == current {
                            Label(language.layoutName(letters), systemImage: "checkmark")
                        } else {
                            Text(language.layoutName(letters))
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(language.layoutName(current)).font(.body).foregroundStyle(TyprTheme.textMuted).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.medium))
                        .foregroundStyle(TyprTheme.textMuted)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("letter-layout-\(language.rawValue)")
        }
        .frame(minHeight: 34)
        .listRowBackground(TyprTheme.bgBase)
        .listRowSeparatorTint(TyprTheme.borderWeak)
    }

    private func languageRow(_ language: KeyboardLanguage) -> some View {
        let local = Locale.current.localizedString(forIdentifier: language == .french ? "fr-FR" : language.rawValue)
        return LanguageChoiceRow(
            title: language.displayName,
            detail: local.flatMap { $0.caseInsensitiveCompare(language.displayName) == .orderedSame ? nil : $0 },
            isChosen: chosen.contains(language)
        ) {
            choose(Self.toggled(language, in: chosen, automatic: automatic))
        }
    }

    static func toggled(_ language: KeyboardLanguage, in chosen: [KeyboardLanguage],
                        automatic: KeyboardLanguage) -> [KeyboardLanguage] {
        if let index = chosen.firstIndex(of: language) {
            var next = chosen
            next.remove(at: index)
            return next
        }
        if chosen.isEmpty { return language == automatic ? [language] : [automatic, language] }
        return chosen + [language]
    }

    private func choose(_ languages: [KeyboardLanguage]) {
        chosen = languages
        LanguageSettings().keyboardLanguages = languages
    }
}

private struct LanguageChoiceRow: View {
    let title: String
    let detail: String?
    let isChosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isChosen ? TyprTheme.success : TyprTheme.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(TyprTheme.textBase)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(TyprTheme.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .listRowBackground(TyprTheme.bgBase)
        .listRowSeparatorTint(TyprTheme.borderWeak)
    }
}

private struct LanguageSectionHeader: View {
    let title: String

    var body: some View {
        Text(title).font(.footnote.weight(.medium)).foregroundStyle(TyprTheme.textMuted).textCase(nil)
    }
}

private struct LanguageSectionFooter: View {
    let text: String

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(TyprTheme.textMuted)
    }
}
