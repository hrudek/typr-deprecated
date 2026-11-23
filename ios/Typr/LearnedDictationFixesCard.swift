import SwiftUI

struct LearnedDictationFixesCard: View {
    static let emptyNotice = "Nothing learned yet. Replace a dictated word with a similar one twice, and Typr writes it that way."
    static let offNotice = "Turn on Learn from my edits in Experimental."
    static let about = "Typr keeps only the words you replaced, what you wrote instead (up to three words each) and how often, never the dictation. Fixes made once stay unlisted until you delete everything."
    static let hexOffNotice = "Turn on Learn how I type in Keyboard."
    static let hexAbout = "Learn how I type keeps the words you replaced in a dictation and what you wrote instead, never the dictation. Switch a fix off to stop using it."
    static let hexListLimit = 12

    var store = DictationLearningStore()
    var defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)
    var journalDirectory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)

    @Environment(\.scenePhase) private var scenePhase
    @State private var usesTypr = false
    @State private var fixes: [TyprDictationLearnedFix] = []
    @State private var hexFixes: [DictationLearnedFix] = []
    @State private var disabledHexFixes: Set<String> = []
    @State private var hasRecords = false
    @State private var isOn = false
    @State private var confirmingDelete = false

    var body: some View {
        SettingsSection(title: "Learned from your edits", subtitle: usesTypr ? Self.about : Self.hexAbout) {
            if usesTypr { content } else { hexContent }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    @ViewBuilder private var content: some View {
        if fixes.isEmpty {
            Text(isOn ? Self.emptyNotice : Self.offNotice)
                .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        ForEach(Array(fixes.enumerated()), id: \.element.id) { index, fix in
            if index > 0 { SettingsDivider() }
            HStack(spacing: 10) {
                Text("\(fix.heard) → \(fix.meant)")
                    .font(.body).foregroundStyle(TyprTheme.textBase)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(fix.count)×").font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                Button {
                    store.delete(fix)
                    reload()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TyprTheme.textMuted)
                        .frame(width: 32, height: 32)
                        .background(TyprTheme.layer02, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(fix.heard) → \(fix.meant)")
            }
            .padding(.leading, 16).padding(.trailing, 6)
        }
        if hasRecords {
            SettingsDivider()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("Delete what Typr learned from your edits")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .confirmationDialog("Delete every fix Typr learned from your edits?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    store.deleteAll()
                    reload()
                }
            }
        }
    }

    @ViewBuilder private var hexContent: some View {
        if hexFixes.isEmpty {
            Text(isOn ? Self.emptyNotice : Self.hexOffNotice)
                .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        ForEach(Array(hexFixes.enumerated()), id: \.element.id) { index, fix in
            if index > 0 { SettingsDivider() }
            SettingsToggle(title: "\(fix.heard) → \(fix.meant)", detail: "\(fix.count)×", isOn: isApplied(fix))
        }
    }

    private func isApplied(_ fix: DictationLearnedFix) -> Binding<Bool> {
        Binding(
            get: { !disabledHexFixes.contains(fix.id) },
            set: { applied in
                if applied {
                    disabledHexFixes.remove(fix.id)
                } else {
                    disabledHexFixes.insert(fix.id)
                }
                TypingJournalSettings(defaults: defaults).disabledDictationFixes = disabledHexFixes
            }
        )
    }

    private func reload() {
        let settings = TyprSettings(defaults: defaults)
        usesTypr = settings[experiment: .typrDictationEditLearning]
        guard !usesTypr else {
            isOn = settings[experiment: .learnFromEdits]
            hasRecords = !store.records.isEmpty
            fixes = store.learnedFixes
            return
        }
        let journal = TypingJournalSettings(defaults: defaults)
        isOn = journal.isEnabled
        disabledHexFixes = journal.disabledDictationFixes
        let snapshot = TypingJournal.load(from: journalDirectory?.appendingPathComponent(TypingJournal.fileName))
        let learned = journal.learnsPerLanguage ? snapshot.learnedDictationFixesByLanguage() : snapshot.learnedDictationFixes
        hexFixes = Array(learned
            .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
            .prefix(Self.hexListLimit))
    }
}
