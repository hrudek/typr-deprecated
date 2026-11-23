import SwiftUI
import UIKit

/// Settings › Keyboard › Appearance for Hex's keyboard (Typr keyboard off): where the Typr key
/// sits and the number row, under Hex's keys, over a live preview of the Hex keyboard that
/// redraws from the App Group as each setting changes (theme and letter layouts included).
struct HexKeyboardAppearancePage: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var typrKeyOnLeft = FullKeyboardSettings().hexKeyOnLeft
    @State private var numberRow = FullKeyboardSettings().numberRow
    @State private var window: WindowReader.Window?

    static let typrKeyFooter = "The Typr key sits at this end of the suggestion bar."

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
        }
    }

    private func dockedPreview(in page: CGSize, container: CGSize) -> some View {
        let settings = HexKeyboardAppearancePreview.Settings(
            typrKeyOnLeft: typrKeyOnLeft,
            numberRow: numberRow,
            // The app is always dark; the keyboard follows the system like it does in most apps.
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
        typrKeyOnLeft = FullKeyboardSettings().hexKeyOnLeft
        numberRow = FullKeyboardSettings().numberRow
    }
}

/// Hex's real full keyboard, drawn only: no touches, text, learning or suggestions. It reads
/// its settings from the App Group, as the keyboard does; `Settings` only says when to redraw.
struct HexKeyboardAppearancePreview: UIViewRepresentable {
    struct Settings: Equatable {
        var typrKeyOnLeft: Bool
        var numberRow: Bool
        var isDark: Bool
        /// The window the page is in: the display the preview stands in for.
        var container: CGSize

        var orientation: KeyboardOrientation { container.width > container.height ? .landscape : .portrait }

        var height: CGFloat { KeyboardLayout.height(for: orientation, numberRow: numberRow) }

        var accessibilityLabel: String {
            ["Full keyboard preview", "Typr key \(typrKeyOnLeft ? "left" : "right")",
             "number row \(numberRow ? "on" : "off")"].joined(separator: ", ")
        }
    }

    let settings: Settings

    func makeUIView(context: Context) -> FullKeyboardView {
        Self.makeKeyboard(settings)
    }

    func updateUIView(_ view: FullKeyboardView, context: Context) {
        Self.apply(settings, to: view)
    }

    static func makeKeyboard(_ settings: Settings) -> FullKeyboardView {
        let model = KeyboardViewModel()
        // Shows the globe; the app cannot know whether the current iPhone needs one.
        model.needsGlobeKey = true
        let view = FullKeyboardView(model: model, target: HexKeyboardPreviewTextTarget())
        view.drawsBackdrop = true
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        apply(settings, to: view)
        return view
    }

    static func apply(_ settings: Settings, to view: FullKeyboardView) {
        view.syncSettings()
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
