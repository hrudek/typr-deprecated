import SwiftUI

/// What Learn from my edits learned, under AI & vocabulary settings, with a way to delete each
/// fix or all of them.
struct LearnedDictationFixesCard: View {
    static let emptyNotice = "Nothing learned yet. Replace a dictated word with a similar one twice, and Typr writes it that way."
    static let offNotice = "Turn on Learn from my edits in Experimental."
    static let about = "Typr keeps only the words you replaced, what you wrote instead (up to three words each) and how often, never the dictation. Fixes made once stay unlisted until you delete everything."

    var store = DictationLearningStore()

    @Environment(\.scenePhase) private var scenePhase
    @State private var fixes: [DictationLearnedFix] = []
    @State private var hasRecords = false
    @State private var isOn = false
    @State private var confirmingDelete = false

    var body: some View {
        SettingsSection(title: "Learned from your edits", subtitle: Self.about) {
            content
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

    private func reload() {
        isOn = TyprSettings()[experiment: .learnFromEdits]
        hasRecords = !store.records.isEmpty
        fixes = store.learnedFixes
    }
}
