import SwiftUI
import UIKit

struct HexKeyboardAppearancePage: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var design = TyprFullKeyboardSettings().design
    @State private var typrKeyOnLeft = FullKeyboardSettings().hexKeyOnLeft
    @State private var numberRow = FullKeyboardSettings().numberRow
    @State private var typrBottomRow = TyprSettings()[experiment: .typrBottomRow]
    @State private var bottomRow = TyprFullKeyboardSettings().bottomRow
    @State private var typrCompactStrip = TyprSettings()[experiment: .typrCompactStrip]
    @State private var hideSuggestionBar = TyprSettings().hideSuggestionBar
    @State private var typrSplitKeyboard = TyprSettings()[experiment: .typrSplitKeyboard]
    @State private var splitKeyboard = TyprFullKeyboardSettings().splitKeyboard
    @State private var splitColumns = TyprFullKeyboardSettings().splitColumns
    @State private var window: WindowReader.Window?

    static let typrKeyFooter = "The Typr key sits at this end of the suggestion bar."
    static let designFooter = "Mechanical replaces a keyboard theme."

    var body: some View {
        GeometryReader { page in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Layout preview below")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(TyprTheme.textMuted)
                    controls
                }
                .frame(maxWidth: 500)
                .padding(20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dockedPreview(in: page.size, container: window?.size ?? CGSize(
                    width: page.size.width + page.safeAreaInsets.leading + page.safeAreaInsets.trailing,
                    height: page.size.height + page.safeAreaInsets.top + page.safeAreaInsets.bottom
                ))
            }
            .background(WindowReader { window = $0 })
        }
        .background(TyprTheme.bgDeep.ignoresSafeArea())
        .navigationTitle(SettingsDestination.keyboardAppearance.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(TyprTheme.bgDeep, for: .navigationBar)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Design") {
                    if dynamicTypeSize.isAccessibilitySize {
                        ForEach(Array(KeyboardDesign.allCases.enumerated()), id: \.element) { index, choice in
                            if index > 0 { SettingsDivider() }
                            SettingsChoiceRow(title: choice.title, isSelected: design == choice) { design = choice }
                        }
                    } else {
                        Picker("Design", selection: $design) {
                            ForEach(KeyboardDesign.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(16)
                        .accessibilityIdentifier("keyboard-design")
                    }
                }
                .onChange(of: design) { _, choice in TyprFullKeyboardSettings().design = choice }
                SettingsFooter(Self.designFooter)
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Typr key") {
                    Picker("Typr key", selection: $typrKeyOnLeft) {
                        Text("Left").tag(true)
                        Text("Right").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(16)
                    .accessibilityIdentifier("typr-key-side")
                }
                .onChange(of: typrKeyOnLeft) { _, left in FullKeyboardSettings().hexKeyOnLeft = left }
                SettingsFooter(Self.typrKeyFooter)
            }

            SettingsSection(title: "Top row") {
                SettingsToggle(title: "Number row", detail: "1 to 0 above the letters. The keyboard grows taller.", isOn: $numberRow)
                    .onChange(of: numberRow) { _, shown in FullKeyboardSettings().numberRow = shown }
            }

            if typrCompactStrip {
                SettingsSection(title: "Suggestions") {
                    SettingsToggle(title: "Hide suggestion bar", detail: "Autocorrect still works on space.", isOn: $hideSuggestionBar)
                        .onChange(of: hideSuggestionBar) { _, hidden in TyprSettings().hideSuggestionBar = hidden }
                }
            }

            if typrSplitKeyboard {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSection(title: "Split") {
                        SettingsToggle(title: "Split keyboard", detail: "Half the keys under each thumb.", isOn: $splitKeyboard)
                            .onChange(of: splitKeyboard) { _, split in TyprFullKeyboardSettings().splitKeyboard = split }
                        if splitKeyboard {
                            SettingsDivider()
                            SettingsToggle(title: "Aligned columns", detail: "Letters straight above each other.", isOn: $splitColumns)
                                .onChange(of: splitColumns) { _, aligned in TyprFullKeyboardSettings().splitColumns = aligned }
                        }
                    }
                    SettingsFooter(KeyboardAppearancePage.splitKeyboardFooter)
                }
            }

            if typrBottomRow {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSection(title: "Bottom row") {
                        SettingsToggle(title: "Period key", detail: "A period beside the space bar.", isOn: $bottomRow.periodKey)
                        SettingsDivider()
                        SettingsToggle(title: "Emoji key", detail: KeyboardAppearancePage.emojiKeyDetail, isOn: $bottomRow.emojiKey)
                        SettingsDivider()
                        SettingsOrderRows(items: $bottomRow.order) { key in
                            HStack {
                                Text(key.title).font(.body).foregroundStyle(TyprTheme.textBase)
                                Spacer(minLength: 8)
                                if key == .period, !bottomRow.periodKey {
                                    Text("Hidden").font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onChange(of: bottomRow) { _, row in TyprFullKeyboardSettings().bottomRow = row }
                    SettingsFooter(KeyboardAppearancePage.bottomRowFooter)
                }
            }
        }
    }

    private func dockedPreview(in page: CGSize, container: CGSize) -> some View {
        let settings = HexKeyboardAppearancePreview.Settings(
            design: design,
            typrKeyOnLeft: typrKeyOnLeft,
            numberRow: numberRow,
            bottomRow: typrBottomRow ? bottomRow : nil,
            showsStrip: !(typrCompactStrip && hideSuggestionBar),
            isDark: KeyboardAppearancePage.snapshotIsDark() ?? window?.systemIsDark ?? true,
            container: container
        )
        let height = settings.height
        let scale = KeyboardAppearancePage.previewScale(keyboardHeight: height, page: page, foldBottom: nil)
        return HexKeyboardAppearancePreview(settings: settings)
            .frame(maxWidth: KeyboardAppearancePage.keyboardWidth(display: container), minHeight: height, maxHeight: height)
            .scaleEffect(scale, anchor: .bottom)
            .frame(maxWidth: .infinity, minHeight: height * scale, maxHeight: height * scale, alignment: .bottom)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(settings.accessibilityLabel)
            .background(Color(uiColor: FullKeyboardPalette(isDark: settings.isDark).backdrop).ignoresSafeArea(edges: .bottom))
            .ignoresSafeArea(edges: .horizontal)
    }

    private func refresh() {
        design = TyprFullKeyboardSettings().design
        typrKeyOnLeft = FullKeyboardSettings().hexKeyOnLeft
        numberRow = FullKeyboardSettings().numberRow
        typrBottomRow = TyprSettings()[experiment: .typrBottomRow]
        bottomRow = TyprFullKeyboardSettings().bottomRow
        typrCompactStrip = TyprSettings()[experiment: .typrCompactStrip]
        hideSuggestionBar = TyprSettings().hideSuggestionBar
        typrSplitKeyboard = TyprSettings()[experiment: .typrSplitKeyboard]
        splitKeyboard = TyprFullKeyboardSettings().splitKeyboard
        splitColumns = TyprFullKeyboardSettings().splitColumns
    }
}

struct HexKeyboardAppearancePreview: UIViewRepresentable {
    struct Settings: Equatable {
        var design = KeyboardDesign.standard
        var typrKeyOnLeft: Bool
        var numberRow: Bool
        var bottomRow: BottomRow?
        var showsStrip = true
        var isDark: Bool
        var container: CGSize

        var orientation: KeyboardOrientation { container.width > container.height ? .landscape : .portrait }

        var height: CGFloat { KeyboardLayout.height(for: orientation, numberRow: numberRow, showsStrip: showsStrip) }

        var accessibilityLabel: String {
            ["Full keyboard preview", design.title, "Typr key \(typrKeyOnLeft ? "left" : "right")",
             "number row \(numberRow ? "on" : "off")", "suggestions \(showsStrip ? "shown" : "hidden")"].joined(separator: ", ")
        }
    }

    let settings: Settings

    func makeUIView(context: Context) -> FullKeyboardView {
        Self.makeKeyboard(settings)
    }

    func updateUIView(_ view: FullKeyboardView, context: Context) {
        Self.apply(settings, to: view)
    }

    static func makeKeyboard(
        _ settings: Settings,
        defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)
    ) -> FullKeyboardView {
        let model = KeyboardViewModel()
        model.needsGlobeKey = true
        let view = FullKeyboardView(model: model, target: HexKeyboardPreviewTextTarget(), defaults: defaults)
        view.drawsBackdrop = true
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        apply(settings, to: view)
        return view
    }

    static func apply(_ settings: Settings, to view: FullKeyboardView) {
        view.syncSettings()
        view.designOverride = settings.design
        view.engine.typrBottomRow = settings.bottomRow
        view.engine.showsStrip = settings.showsStrip
        view.setNeedsLayout()
        view.appearanceOverride = settings.isDark
        view.orientationOverride = settings.orientation
    }
}

@MainActor
final class HexKeyboardPreviewTextTarget: KeyboardTextTarget {
    var documentContextBeforeInput: String? { nil }
    var documentContextAfterInput: String? { nil }
    var hasText: Bool { false }
    var autocapitalizationType: UITextAutocapitalizationType? { .sentences }
    var keyboardType: UIKeyboardType? { .default }
    var returnKeyType: UIReturnKeyType? { .default }
    var keyboardAppearance: UIKeyboardAppearance? { nil }
    var smartQuotesType: UITextSmartQuotesType? { nil }
    var smartDashesType: UITextSmartDashesType? { nil }
    func insertText(_ text: String) {}
    func deleteBackward() {}
}
