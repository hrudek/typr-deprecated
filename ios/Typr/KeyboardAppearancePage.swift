import SwiftUI
import UIKit

struct KeyboardAppearancePage: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var design = TyprFullKeyboardSettings().design
    @State private var hideSuggestionBar = TyprSettings().hideSuggestionBar
    @State private var globeKey = TyprFullKeyboardSettings().globeKey
    @State private var bottomRow = TyprFullKeyboardSettings().bottomRow
    @State private var numberRow = TyprFullKeyboardSettings().numberRow
    @State private var splitKeyboard = TyprFullKeyboardSettings().splitKeyboard
    @State private var splitColumns = TyprFullKeyboardSettings().splitColumns
    @State private var letterLayouts = Self.storedLetterLayouts()
    @State private var languageOrder = TyprSettings().autocorrectLanguageOrder
    @State private var draggedOrder: [BottomKey]?
    @State private var window: WindowReader.Window?

    static let globeKeyFooter = "Only on iPhones with no globe under the keyboard. Spacer keeps 123 off the corner and does nothing when tapped."
    static let switchingKeyboardsHint = "With Spacer or Hidden, hold 123 in the full keyboard or space in the dictation bar to switch keyboards."
    static let emojiKeyDetail = "Opens the emoji panel. The suggestion bar also offers emoji for the word you just typed."
    static let bottomRowFooter = "Drag to change the order around the space bar."
    static let splitKeyboardFooter = "Only when iPhone Duo is open and sideways."
    static let letterLayoutFooter = "The keyboard uses the layout of the first selected autocorrect language."

    private static func storedLetterLayouts() -> [SpatialWordDecoder.Language: TyprKeyboardLetterLayout] {
        Dictionary(uniqueKeysWithValues: SpatialWordDecoder.Language.allCases.map { ($0, TyprFullKeyboardSettings().letters(for: $0)) })
    }

    /// `settings-keyboard-appearance-light` and `-dark` fix the preview's appearance for screenshots.
    static func snapshotIsDark(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool? {
        guard let index = arguments.firstIndex(of: "--snap-state"), index + 1 < arguments.count else { return nil }
        return switch arguments[index + 1] {
        case "settings-keyboard-appearance-light": false
        case "settings-keyboard-appearance-dark": true
        default: nil
        }
    }

    private func preview(container: CGSize) -> KeyboardAppearancePreview.Settings {
        KeyboardAppearancePreview.Settings(
            design: design,
            showsSuggestionBar: !hideSuggestionBar,
            globeKey: globeKey,
            bottomRow: BottomRow(order: draggedOrder ?? bottomRow.order, periodKey: bottomRow.periodKey,
                                 emojiKey: bottomRow.emojiKey),
            numberRow: numberRow,
            // The app is always dark; the keyboard follows the system like it does in most apps.
            isDark: Self.snapshotIsDark() ?? window?.systemIsDark ?? true,
            container: container,
            splitKeyboard: splitKeyboard,
            splitColumns: splitColumns,
            letters: TyprFullKeyboardSettings().letters
        )
    }

    var body: some View {
        if TyprSettings()[experiment: .typrKeyboard] {
            typrBody
        } else {
            HexKeyboardAppearancePage()
        }
    }

    private var typrBody: some View {
        GeometryReader { page in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Layout preview below")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(TyprTheme.textMuted)
                    controls
                    Text("Globe shown where iOS needs it.")
                        .font(.caption)
                        .foregroundStyle(TyprTheme.textFaint)
                }
                .frame(maxWidth: 500)
                .padding(20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dockedPreview(in: page.size, foldBottom: Self.horizontalFoldBottom(page), container: window?.size ?? CGSize(
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

    static func dockBackdrop(isDark: Bool) -> Color {
        Color(uiColor: TyprFullKeyboardPalette(isDark: isDark).backdrop)
    }

    /// The docked preview's scale: full size where the page has room, else leaving the controls 260 pt but taking at
    /// least 35% of the page, and never reaching above a fold across the page (`foldBottom`, in page coordinates).
    static func previewScale(keyboardHeight: CGFloat, page: CGSize, foldBottom: CGFloat?) -> CGFloat {
        var room = max(page.height - 260, page.height * 0.35)
        if let foldBottom { room = min(room, page.height - foldBottom) }
        return min(1, max(0, room) / keyboardHeight)
    }

    /// The width iOS gives a third-party keyboard, centred on the display: on the iPhone Duo narrower than the display
    /// (iikb's measurements in the iOS 27.1 simulator), elsewhere the whole width.
    static func keyboardWidth(display: CGSize) -> CGFloat {
        switch (display.width, display.height) {
        case (466, 678): 452
        case (678, 466): 528
        case (951, 669): 801
        default: display.width
        }
    }

    /// The bottom edge of an active fold running across the page: the iPhone Duo partly open and held upright.
    private static func horizontalFoldBottom(_ page: GeometryProxy) -> CGFloat? {
        guard #available(iOS 27.1, *) else { return nil }
        return page.reservedRegions(kind: .division)
            .map(\.frame)
            .filter { $0.width > $0.height && $0.maxY < page.size.height }
            .map(\.maxY)
            .max()
    }

    private func dockedPreview(in page: CGSize, foldBottom: CGFloat?, container: CGSize) -> some View {
        let settings = preview(container: container)
        let height = TyprKeyboardLayout.height(
            for: settings.orientation, showsStrip: settings.showsSuggestionBar, numberRow: settings.numberRow
        )
        let scale = Self.previewScale(keyboardHeight: height, page: page, foldBottom: foldBottom)
        return KeyboardAppearancePreview(settings: settings)
            .frame(maxWidth: Self.keyboardWidth(display: container), minHeight: height, maxHeight: height)
            .scaleEffect(scale, anchor: .bottom)
            .frame(maxWidth: .infinity, minHeight: height * scale, maxHeight: height * scale, alignment: .bottom)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(settings.accessibilityLabel)
            .background(Self.dockBackdrop(isDark: settings.isDark).ignoresSafeArea(edges: .bottom))
            .ignoresSafeArea(edges: .horizontal)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                }
            }
            .onChange(of: design) { _, choice in TyprFullKeyboardSettings().design = choice }

            SettingsSection(title: "Suggestions") {
                SettingsToggle(title: "Hide suggestion bar", detail: "Autocorrect still works on space.", isOn: $hideSuggestionBar)
                    .onChange(of: hideSuggestionBar) { _, hidden in TyprSettings().hideSuggestionBar = hidden }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Letter layout") {
                    ForEach(Array(languageOrder.enumerated()), id: \.element) { index, language in
                        if index > 0 { SettingsDivider() }
                        letterLayoutRow(language)
                    }
                }
                SettingsFooter(Self.letterLayoutFooter)
            }

            SettingsSection(title: "Top row") {
                SettingsToggle(title: "Number row", detail: "1 to 0 above the letters. The keyboard grows taller.", isOn: $numberRow)
                    .onChange(of: numberRow) { _, shown in TyprFullKeyboardSettings().numberRow = shown }
            }

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
                SettingsFooter(Self.splitKeyboardFooter)
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Globe key") {
                    ForEach(Array(GlobeKey.allCases.enumerated()), id: \.element) { index, choice in
                        if index > 0 { SettingsDivider() }
                        SettingsChoiceRow(title: choice.title, isSelected: globeKey == choice) {
                            globeKey = choice
                            TyprFullKeyboardSettings().globeKey = choice
                        }
                    }
                    SettingsDivider()
                    DisclosureGroup("Switching keyboards") {
                        Text(Self.switchingKeyboardsHint)
                            .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .disclosureGroupStyle(SettingsDisclosureStyle())
                    .padding(.horizontal, 16)
                }
                SettingsFooter(Self.globeKeyFooter)
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Bottom row") {
                    SettingsToggle(title: "Period key", detail: "Hold it for more punctuation.", isOn: $bottomRow.periodKey)
                    SettingsDivider()
                    SettingsToggle(title: "Emoji key", detail: Self.emojiKeyDetail, isOn: $bottomRow.emojiKey)
                    SettingsDivider()
                    SettingsOrderRows(items: $bottomRow.order, onShownOrder: { draggedOrder = $0 }) { key in
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
                SettingsFooter(Self.bottomRowFooter)
            }
        }
    }

    private func letterLayoutRow(_ language: SpatialWordDecoder.Language) -> some View {
        let selection = Binding(get: { letterLayouts[language] ?? .qwerty }, set: { letters in
            TyprFullKeyboardSettings().setLetters(letters, for: language)
            letterLayouts[language] = letters
        })
        return HStack {
            Text(language.title).font(.body).foregroundStyle(TyprTheme.textBase)
            Spacer(minLength: 8)
            Picker(language.title, selection: selection) {
                ForEach(TyprKeyboardLetterLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(TyprTheme.textMuted)
            .accessibilityIdentifier("letter-layout-\(language.rawValue)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    private func refresh() {
        letterLayouts = Self.storedLetterLayouts()
        languageOrder = TyprSettings().autocorrectLanguageOrder
        design = TyprFullKeyboardSettings().design
        hideSuggestionBar = TyprSettings().hideSuggestionBar
        globeKey = TyprFullKeyboardSettings().globeKey
        bottomRow = TyprFullKeyboardSettings().bottomRow
        numberRow = TyprFullKeyboardSettings().numberRow
        splitKeyboard = TyprFullKeyboardSettings().splitKeyboard
        splitColumns = TyprFullKeyboardSettings().splitColumns
    }
}

/// The window the page is in, which a page beside a sidebar does not fill, and whether the system is dark.
struct WindowReader: UIViewRepresentable {
    struct Window: Equatable {
        var size: CGSize
        var systemIsDark: Bool
    }

    let onChange: (Window) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.onChange = onChange
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
    }

    /// Laid out whenever the page resizes (rotating, folding, unfolding), which is when the window does.
    final class Probe: UIView {
        var onChange: ((Window) -> Void)?
        private var reported: Window?
        private weak var observedScene: UIWindowScene?
        private var styleRegistration: (any UITraitChangeRegistration)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let styleRegistration, let observedScene {
                observedScene.unregisterForTraitChanges(styleRegistration)
            }
            observedScene = window?.windowScene
            // The scene's style, not the window's: the app forces its windows dark.
            styleRegistration = observedScene?.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                [weak self] (_: UIWindowScene, _: UITraitCollection) in self?.report()
            }
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let window else { return }
            let current = Window(
                size: window.bounds.size,
                systemIsDark: window.windowScene?.traitCollection.userInterfaceStyle != .light
            )
            guard current != reported else { return }
            reported = current
            // Not during SwiftUI's own layout pass.
            DispatchQueue.main.async { [weak self] in self?.onChange?(current) }
        }
    }
}

/// The real full keyboard, drawn only: no touches, text, learning, suggestions or statistics.
struct KeyboardAppearancePreview: UIViewRepresentable {
    struct Settings {
        var design: KeyboardDesign
        var showsSuggestionBar: Bool
        var globeKey: GlobeKey
        var bottomRow: BottomRow
        var numberRow: Bool
        var isDark: Bool
        /// The window the page is in: the display the preview stands in for.
        var container: CGSize
        var splitKeyboard = false
        var splitColumns = false
        var letters = TyprKeyboardLetterLayout.qwerty

        var orientation: TyprKeyboardOrientation { TyprKeyboardOrientation(container: container, split: splitKeyboard) }

        var accessibilityLabel: String {
            let globe = switch globeKey {
            case .switches: "globe key"
            case .spacer: "globe spacer"
            case .hidden: "no globe key"
            }
            return ["Full keyboard preview", design.title, globe,
                    "period \(bottomRow.periodKey ? "on" : "off")",
                    bottomRow.emojiKey ? "emoji key" : nil,
                    "number row \(numberRow ? "on" : "off")",
                    orientation == .splitLandscape ? "split" : nil,
                    orientation == .splitLandscape && splitColumns ? "aligned columns" : nil,
                    letters.title,
                    "suggestions \(showsSuggestionBar ? "shown" : "hidden")"].compactMap { $0 }.joined(separator: ", ")
        }
    }

    let settings: Settings

    func makeUIView(context: Context) -> TyprFullKeyboardView {
        Self.makeKeyboard(settings)
    }

    func updateUIView(_ view: TyprFullKeyboardView, context: Context) {
        Self.apply(settings, to: view)
    }

    static func makeKeyboard(_ settings: Settings) -> TyprFullKeyboardView {
        let model = KeyboardViewModel()
        // Shows the globe choice; the app cannot know whether the current iPhone needs one.
        model.needsGlobeKey = true
        model.globeKey = settings.globeKey
        model.bottomRow = settings.bottomRow
        model.numberRow = settings.numberRow
        model.splitKeyboard = settings.splitKeyboard
        model.splitColumns = settings.splitColumns
        model.letters = settings.letters
        let learning = KeyboardLearningSession(store: nil, defaults: nil, allowsPersistence: { false })
        let view = TyprFullKeyboardView(
            model: model,
            target: KeyboardPreviewTextTarget(),
            autocorrect: TyprAutocorrectEngine(learning: learning, spatialDecoder: nil),
            preview: TyprFullKeyboardView.Preview(design: settings.design, showsSuggestionBar: settings.showsSuggestionBar)
        )
        view.drawsBackdrop = true
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        apply(settings, to: view)
        return view
    }

    static func apply(_ settings: Settings, to view: TyprFullKeyboardView) {
        view.model.globeKey = settings.globeKey
        view.model.bottomRow = settings.bottomRow
        view.model.numberRow = settings.numberRow
        view.model.splitKeyboard = settings.splitKeyboard
        view.model.splitColumns = settings.splitColumns
        view.model.letters = settings.letters
        view.applyPreview(TyprFullKeyboardView.Preview(design: settings.design, showsSuggestionBar: settings.showsSuggestionBar))
        view.appearanceOverride = settings.isDark
        view.containerSize = settings.container
    }
}

@MainActor
final class KeyboardPreviewTextTarget: TyprKeyboardTextTarget {
    var documentContextBeforeInput: String? { nil }
    var hasText: Bool { false }
    var autocapitalizationType: UITextAutocapitalizationType? { .sentences }
    var keyboardType: UIKeyboardType? { .default }
    var returnKeyType: UIReturnKeyType? { .default }
    var keyboardAppearance: UIKeyboardAppearance? { nil }
    func insertText(_ text: String) {}
    func deleteBackward() {}
}
