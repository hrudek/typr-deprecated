import Combine
import UIKit

/// The full keyboard: a 3-slot suggestion strip (Typr: optional), QWERTY keys with
/// the Typr key right of space, long-press accents, the recording panel that replaces the suggestion bar while
/// Typr records, and the feedback panel that replaces them after a dictation.
/// Dictation state comes from the same `KeyboardViewModel` the dictation bar uses.
@MainActor
final class FullKeyboardView: UIView, UIInputViewAudioFeedback {
    /// The app's settings preview: these values instead of the stored ones, no typing settings and no suggestions.
    struct Preview: Equatable {
        var design: KeyboardDesign
        var showsSuggestionBar: Bool
    }

    let model: KeyboardViewModel
    let engine: FullKeyboardEngine
    weak var hostController: UIInputViewController? {
        didSet { configureGlobe() }
    }

    /// Fixtures force light or dark and portrait or landscape; the keyboard follows its field.
    var appearanceOverride: Bool? { didSet { applyAppearance() } }
    var orientationOverride: KeyboardOrientation? { didSet { setNeedsLayout() } }
    /// The size of the display the keyboard is on (the settings preview: its page), which picks the geometry.
    var containerSize: CGSize? { didSet { if containerSize != oldValue { setNeedsLayout() } } }
    /// Haptics need Full Access.
    var allowsHaptics: () -> Bool = { false }
    /// Draws a stand-in backdrop where there is no system keyboard behind the view.
    var drawsBackdrop = false { didSet { applyAppearance() } }
    /// Typr: sliding down on the Typr key shows the compact dictation bar.
    var allowsCompactBar: Bool {
        get { typrKey.allowsCompactBar }
        set { typrKey.allowsCompactBar = newValue }
    }
    /// Typr: the Typr key was slid down.
    var onShowCompactBar: (() -> Void)?
    /// Fixtures force the suggestion bar on or off; the keyboard follows Typr's switch.
    var suggestionBarOverride: Bool? { didSet { applySuggestionBarSetting() } }
    var designOverride: KeyboardDesign?
    /// Model next words: the cloud provider while a key is stored, otherwise the on-device model.
    var cloudPredictions: (any ModelPredictionProvider)? { didSet { replaceModelPredictions() } }
    /// Checked when the keyboard appears or a provider is set.
    var hasCloudKey: () -> Bool = { false }
    private var cloudKeyStored = false
    var onDeviceModel: (any OnDeviceNextWordModel)? { didSet { replaceModelPredictions() } }
    private var modelSource: ModelPredictionSource?
    /// How long Fix in Typr stays after Problem before the panel closes itself.
    var problemPanelDuration: TimeInterval {
        get { model.problemPanelDuration }
        set { model.problemPanelDuration = newValue }
    }

    private let stripView = KeyboardStripView()
    private let plane: KeyboardKeyPlaneView
    private let callout = KeyCalloutView()
    private let accentCallout = AccentCalloutView()
    private let typrKey = TyprKeyControl()
    private let globeButton = UIButton(type: .custom)
    private var recordingPanel: TyprKeyRecordingPanel?
    /// Loaded on the first emoji key press or finished word; dropped on a memory warning while the panel is closed.
    private var emojiIndex: EmojiIndex?
    private(set) var emojiPanel: EmojiPanelView?
    /// Whether Apple's keyboard is among the user's keyboards; tests give their own.
    var hasAppleKeyboard: () -> Bool = { KeyboardInputModes.hasAppleKeyboard() }
    /// Where emoji use is kept; tests give their own.
    var makeEmojiUsage: () -> EmojiUsageStore = { EmojiUsageStore() }
    private var feedbackPanel: TyprFeedbackPanel?
    /// What the feedback panel shows; `nil` while the keys are up.
    private var panelContent: TyprFeedbackPanel.Content?
    /// A failure message closed with ✕ stays closed until it changes.
    private var dismissedNotice: String?
    private var styleMenu: TyprStyleMenuView?
    private var palette = FullKeyboardPalette(isDark: false)
    private var didApplyPalette = false
    private(set) var design = KeyboardDesign.standard
    private var subscriptions: Set<AnyCancellable> = []
    private var showsRecording = false
    private var stripPressTouch: UITouch?
    private var stripPressStart: CGPoint?
    private var stripHoldWork: DispatchWorkItem?
    private var stripHoldDictates = false
    private var lastDictation: DictationUndo?
    /// Follows inserted dictations for Learn from my edits; the controller stores its results.
    var dictationEdits = DictationEditTracker()
    private var undoHideWork: DispatchWorkItem?
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let selectionHaptics = UISelectionFeedbackGenerator()

    /// Exposed so unit tests can verify lazy allocation and teardown of the Metal recording panel.
    var hasAllocatedRecordingPanel: Bool { recordingPanel != nil }
    /// What the feedback panel shows, for tests; `nil` while the keys are up.
    var shownPanelContent: TyprFeedbackPanel.Content? { panelContent }
    var shownSuggestions: [KeyboardSuggestion] { stripView.currentSuggestions }
    var showsCodeFromMessages: Bool { stripView.showsCodeChip }
    var shownReturnKey: (style: ReturnKeyStyle, isEnabled: Bool) { (plane.returnStyle, plane.returnIsEnabled) }

    init(model: KeyboardViewModel, target: KeyboardTextTarget, autocorrect: AutocorrectEngine? = nil,
         statistics: UsageStatisticsSession? = nil, typingLog: TypingLogRecorder? = nil, preview: Preview? = nil) {
        self.model = model
        engine = FullKeyboardEngine(target: target, autocorrect: autocorrect, statistics: statistics, typingLog: typingLog)
        engine.autocorrect.learning.onValidatedLabel = { [weak statistics] label, layout in
            statistics?.validatedLabel(label, layout: layout)
        }
        engine.autocorrect.learning.onLabelsInvalidated = { [weak statistics] in
            statistics?.clearRecentLabels()
        }
        plane = KeyboardKeyPlaneView(engine: engine)
        super.init(frame: .zero)
        backgroundColor = .clear

        addSubview(stripView)
        addSubview(plane)
        addSubview(typrKey)
        addSubview(globeButton)
        addSubview(callout)
        addSubview(accentCallout)
        accentCallout.isHidden = true

        stripView.onSelectSuggestion = { [weak self] suggestion in
            guard let self else { return }
            self.keyFeedback()
            if suggestion.isEmoji {
                self.insertEmoji(suggestion.replacement, typed: suggestion.replacement + " ")
            } else {
                self.engine.acceptSuggestion(suggestion)
            }
        }
        stripView.onUndoDictation = { [weak self] in
            self?.keyFeedback()
            self?.undoDictation()
        }

        stripView.onCodeFromMessages = { [weak self] in
            self?.keyFeedback()
            self?.model.onNextKeyboard?()
        }

        globeButton.accessibilityLabel = "Next keyboard"
        globeButton.isAccessibilityElement = true

        typrKey.onHighlightChanged = { [weak self] highlighted in self?.plane.typrPressed = highlighted }
        typrKey.onArm = { [weak self] in
            guard let self, self.typrKey.isWarm || self.model.armsWhenCold, !self.showsRecording else { return }
            self.model.onArmDictation?()
        }
        typrKey.onDisarm = { [weak self] in self?.model.onDisarmDictation?() }
        typrKey.onHold = { [weak self] in self?.typrKeyHeld() }
        typrKey.onTap = { [weak self] in self?.typrKeyTapped() }
        typrKey.onShowCompactBar = { [weak self] in self?.typrKeySlidDown() }
        typrKey.onMenuOpen = { [weak self] point in
            guard let self else { return }
            self.showStyleMenu()
            self.forwardMenuPoint(point, release: false)
        }
        typrKey.onMenuDrag = { [weak self] point in self?.forwardMenuPoint(point, release: false) }
        typrKey.onMenuRelease = { [weak self] point in self?.forwardMenuPoint(point, release: true) }

        plane.onKeyDown = { [weak self] kind in if kind != .globeSpacer { self?.keyFeedback() } }
        plane.onNextKeyboard = { [weak self] in self?.model.onNextKeyboard?() }
        plane.onAccentMenuOpened = { [weak self] in self?.selectionFeedback() }
        engine.onSelectionStep = { [weak self] in self?.selectionFeedback() }
        engine.onEmojiKey = { [weak self] in self?.openEmojiPanel() }
        engine.onCursorMove = { [weak self] in self?.revalidateUndo() }
        engine.onChange = { [weak self] in self?.engineChanged() }
        engine.onEdit = { [weak self] in
            self?.observeDictationEdits(fromKeys: true)
            self?.hideUndo()
            self?.model.dismissFeedback()
            self?.refreshReturnKey()
            self?.refreshStrip()
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshFromModel() }
            .store(in: &subscriptions)

        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitVerticalSizeClass.self]) { (view: FullKeyboardView, _) in
            view.applyAppearance()
            view.setNeedsLayout()
        }

        if let preview {
            engine.suspendSuggestions()
            engine.refreshAutoCapitalization()
            applyPreview(preview)
        } else {
            engine.autocorrect.isEnabled = FullKeyboardSettings().autocorrect
            engine.autocorrect.allowsSwearing = FullKeyboardSettings().suggestSwearWords
            engine.autocorrect.choosesWordsFromContext = TyprSettings()[experiment: .wordsFromContext]
            engine.swipeTypingEnabled = FullKeyboardSettings().swipeTyping
            engine.autocorrect.englishEnabled = TyprSettings().autocorrectEnglish
            engine.autocorrect.preferredLanguage = TyprSettings().autocorrectLanguageOrder[0]
            if TyprSettings().autocorrectGerman {
                let instance = GermanAutocorrect.system()
                cachedGerman = instance
                engine.autocorrect.german = instance
            }
            applySuggestionBarSetting()
            engine.configureForField()
        }
        applyAppearance()
        refreshFromModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Size

    static func orientation(for traits: UITraitCollection) -> KeyboardOrientation {
        traits.verticalSizeClass == .compact ? .landscape : .portrait
    }

    var orientation: KeyboardOrientation {
        if let orientationOverride { return orientationOverride }
        guard let containerSize else { return Self.orientation(for: traitCollection) }
        return KeyboardOrientation(container: containerSize, split: model.splitKeyboard)
    }

    var preferredHeight: CGFloat {
        KeyboardLayout.height(for: orientation, showsStrip: engine.showsStrip, numberRow: engine.numberRow)
    }

    // MARK: - Host events

    var enableInputClicksWhenVisible: Bool { true }

    private var cachedGerman: GermanAutocorrect? // Typr
    private var trackpadFont: UIFont?

    /// Most fields show the body font (17 pt, larger with Dynamic Type).
    private func applyTrackpadFont() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        guard font != trackpadFont else { return }
        trackpadFont = font
        var widths: [Character: CGFloat] = [:]
        engine.trackpadLineHeight = font.lineHeight
        engine.trackpadCharacterWidth = { character in
            if let width = widths[character] { return width }
            let width = character.isNewline ? 0 : (String(character) as NSString).size(withAttributes: [.font: font]).width
            widths[character] = width
            return width
        }
    }

    func warmUpTextCheckerAsync() {
        if engine.autocorrect.isEnabled { engine.autocorrect.spatialDecoder?.prepareResources() }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.engine.suggestionsAreActive else { return }
            self.engine.autocorrect.german?.warmUp() // Typr
            guard let checker = self.engine.autocorrect.checker as? SystemTextChecker else { return }
            checker.warmUp()
            self.engine.refreshSuggestions()
        }
    }

    func loadLexicon(_ lexicon: UILexicon) {
        engine.autocorrect.loadLexicon(lexicon)
        engine.refreshSuggestions()
    }

    func loadLexiconEntries(_ entries: [LexiconEntry]) {
        engine.autocorrect.loadLexiconEntries(entries)
        engine.refreshSuggestions()
    }

    func syncSettings() {
        // Learning switch and app reset epochs; never per keystroke.
        engine.autocorrect.syncLearning()
        engine.refreshDeleteUndo()
        applySuggestionBarSetting()
        let wantsDesign = designOverride ?? FullKeyboardSettings().design
        if wantsDesign != design {
            design = wantsDesign
            applyAppearance()
        }
        let wantsAutocorrect = FullKeyboardSettings().autocorrect
        if engine.autocorrect.isEnabled != wantsAutocorrect {
            engine.autocorrect.isEnabled = wantsAutocorrect
            engine.refreshSuggestions()
        }
        let wantsSwearing = FullKeyboardSettings().suggestSwearWords
        if engine.autocorrect.allowsSwearing != wantsSwearing {
            engine.autocorrect.allowsSwearing = wantsSwearing
            engine.refreshSuggestions()
        }
        let wantsContextWords = TyprSettings()[experiment: .wordsFromContext]
        if engine.autocorrect.choosesWordsFromContext != wantsContextWords {
            engine.autocorrect.choosesWordsFromContext = wantsContextWords
            engine.refreshSuggestions()
        }
        if wantsAutocorrect { engine.autocorrect.spatialDecoder?.prepareResources() }
        let wantsLanguagesSeparately = TyprSettings()[experiment: .learnEachLanguage]
        if engine.autocorrect.learnsLanguagesSeparately != wantsLanguagesSeparately {
            engine.autocorrect.learnsLanguagesSeparately = wantsLanguagesSeparately
            engine.refreshSuggestions()
        }
        if engine.autocorrect.loadCustomWords(CustomVocabularySettings().terms) { engine.refreshSuggestions() }
        engine.swipeTypingEnabled = FullKeyboardSettings().swipeTyping
        engine.followsTextOnTrackpad = TyprSettings()[experiment: .spaceTrackpad]
        engine.slidesDeleteByWord = TyprSettings()[experiment: .deleteSlide]
        applyTrackpadFont()
        let wantsEnglish = TyprSettings().autocorrectEnglish
        if engine.autocorrect.englishEnabled != wantsEnglish {
            engine.autocorrect.englishEnabled = wantsEnglish
            engine.refreshSuggestions()
        }
        let wantsPreferred = TyprSettings().autocorrectLanguageOrder[0]
        if engine.autocorrect.preferredLanguage != wantsPreferred {
            engine.autocorrect.preferredLanguage = wantsPreferred
            engine.refreshSuggestions()
        }
        // Cache the German dictionary across language selection changes.
        let wantsGerman = TyprSettings().autocorrectGerman
        if wantsGerman != (engine.autocorrect.german != nil) {
            if wantsGerman {
                let instance = cachedGerman ?? GermanAutocorrect.system()
                cachedGerman = instance
                engine.autocorrect.german = instance
            } else {
                engine.autocorrect.german = nil
            }
            engine.refreshSuggestions()
        }
        applyModelPredictions()
        // Learning loads/resets (also when consumed by a chip tap), installed spatial resources
        // or an unreported host context change: republish chips that could no longer be accepted.
        engine.refreshSuggestionsIfStale()
    }

    /// The field or its contents changed outside these keys.
    func textDidChange() {
        applyAppearance()
        let field = engine.field
        let route = KeyboardFieldRouting.route(for: engine.target.keyboardType)
        let routeField: KeyboardFieldKind = if case .keys(let kind, _) = route { kind } else { .text }
        if routeField != field {
            plane.cancelAllTouches()
            engine.configureForField()
        } else {
            engine.textDidChange()
        }
        observeDictationEdits(fromKeys: false)
        revalidateUndo()
        refreshReturnKey()
        refreshStrip()
    }

    /// The keyboard came on screen for a (possibly new) field.
    func prepareForField() {
        dictationEdits.finish(nil)
        hideUndo()
        cloudKeyStored = hasCloudKey()
        syncSettings()
        closeEmojiPanel()
        plane.cancelAllTouches()
        engine.configureForField()
        if modelSource == .onDevice { onDeviceModel?.prewarm() }
        refreshReturnKey()
        applyAppearance()
        refreshStrip()
        dismissStyleMenu()
        if allowsHaptics() {
            haptics.prepare()
            selectionHaptics.prepare()
        }
    }

    /// Writes pending learning and diagnostics now (dismissal, memory warning, remount).
    func flushLearning() {
        engine.autocorrect.learning.flush()
        engine.endStatisticsSession()
        engine.statistics?.flush()
    }

    /// A late worker or warmup completion must not read a hidden host's document proxy.
    func suspendSuggestions() {
        engine.suspendSuggestions()
    }

    /// Host became active again: only re-enable and refresh the strip. Layer, shift, undo,
    /// touches and the style menu are kept (unlike `prepareForField`).
    func resumeSuggestions() {
        engine.resumeSuggestions()
    }

    /// The cursor or selection moved outside these keys.
    func selectionDidChange() {
        discardTouchEvidence()
        observeDictationEdits(fromKeys: false)
        revalidateUndo()
    }

    /// Selection changes and keyboard dismissal must not retain current-word taps.
    func discardTouchEvidence() {
        engine.endTypingLogWord("external")
        engine.endStatisticsSession()
        engine.discardTouchEvidenceAndHeldSpace()
    }

    /// Frees non-essential UI and Metal drawables when the extension approaches its memory ceiling.
    func handleMemoryWarning() {
        flushLearning()
        discardTouchEvidence()
        dismissStyleMenu()
        // The folded swipe tries rebuild on the next swipe; the mapped model weights cost no dirty memory.
        Task { await SwipeRecognizer.shared.releaseLexicons() }
        if emojiPanel == nil { emojiIndex = nil }
        if !showsRecording, let panel = recordingPanel {
            panel.tearDown()
            panel.removeFromSuperview()
            recordingPanel = nil
        }
    }

    /// Typr inserted a dictation between `before` and `after`; offer to take it back until the
    /// next edit, for 12 seconds, or until it can't be found from the cursor. With `learns`,
    /// follow what you do with it for Learn from my edits.
    func didInsertDictation(_ text: String, before: String, after: String, learns: Bool = false) {
        let context = DictationEditTracker.Context(before: before, after: after, hasText: !(before + after).isEmpty)
        if learns {
            dictationEdits.willInsert(text, context: context)
        } else {
            dictationEdits.finish(context)
        }
        lastDictation = DictationUndo(text: text, before: before, after: after)
        undoHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideUndo() }
        undoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        engine.textDidChange()
        refreshStrip()
        refreshReturnKey()
    }

    func applyPreview(_ preview: Preview) {
        suggestionBarOverride = preview.showsSuggestionBar
        design = preview.design
        applyAppearance()
    }

    /// Typr: the suggestion bar follows its switch; the keyboard's height changes with it.
    private func applySuggestionBarSetting() {
        let shows = suggestionBarOverride ?? !TyprSettings().hideSuggestionBar
        guard shows != engine.showsStrip else { return }
        engine.showsStrip = shows
        let visible = shows && !showsRecording && panelContent == nil && emojiPanel == nil
        stripView.isHidden = !visible
        stripView.alpha = visible ? 1 : 0
        refreshStrip()
        refreshFeedbackPanel()
        setNeedsLayout()
        hostController?.view.setNeedsLayout()
    }

    private func replaceModelPredictions() {
        modelSource = nil
        cloudKeyStored = hasCloudKey()
        engine.modelPredictions?.cancel()
        engine.modelPredictions = nil
        applyModelPredictions()
    }

    private func applyModelPredictions() {
        let source = ModelPredictionSource.choose(hasCloud: cloudPredictions != nil && cloudKeyStored, onDevice: onDeviceModel,
                                                  languages: engine.autocorrect.suggestionLanguages)
        guard source != modelSource else { return }
        modelSource = source
        engine.modelPredictions?.cancel()
        engine.modelPredictions = switch source {
        case .cloud: cloudPredictions.map { ModelPredictionSession(provider: $0) }
        case .onDevice: onDeviceModel.map {
            ModelPredictionSession(provider: OnDeviceModelPredictions(model: $0), timeout: OnDeviceModelPredictions.timeout)
        }
        case nil: nil
        }
    }

    /// Fixtures: show a key held down.
    func debugPress(_ character: String) {
        guard let key = engine.layout.key(.character(character)) else { return }
        engine.touchBegan(id: -1, at: CGPoint(x: key.frame.midX, y: key.frame.midY))
    }

    /// Fixtures: show a key's long-press accent callout.
    func debugHoldAccent(_ character: String, selectIndex: Int? = nil) {
        guard let key = engine.layout.key(.character(character)) else { return }
        let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: -2, at: center)
        _ = engine.openAccentMenuIfEligible(forTouch: -2)
        if let selectIndex,
           let menu = engine.activeAccentMenu,
           selectIndex >= 0, selectIndex < menu.cellFrames.count {
            let cell = menu.cellFrames[selectIndex]
            engine.touchMoved(id: -2, to: CGPoint(x: cell.midX, y: center.y))
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        engine.orientation = orientation
        engine.horizontalInset = orientation.isLandscape ? max(safeAreaInsets.left, safeAreaInsets.right) : 0
        engine.width = bounds.width
        let layout = engine.layout

        plane.frame = bounds
        callout.frame = bounds
        accentCallout.frame = bounds
        stripView.frame = layout.stripFrame
        stripView.slotsFrame = layout.suggestionSlotsFrame

        typrKey.joinsSpace = JoinedSpaceKeycap(layout: layout) != nil
        typrKey.cornerRadius = layout.metrics.cornerRadius
        if let key = layout.key(.typr) {
            typrKey.frame = key.hitFrame
            typrKey.keycapFrame = key.frame.offsetBy(dx: -key.hitFrame.minX, dy: -key.hitFrame.minY)
        }
        if let globe = layout.key(.globe) {
            globeButton.isHidden = emojiPanel != nil
            globeButton.frame = globe.hitFrame
        } else {
            globeButton.isHidden = true
        }

        if let panel = recordingPanel {
            panel.frame = recordingPanelFrame
            panel.horizontalInset = layout.horizontalInset
            panel.metrics = layout.metrics
        }
        if let panel = emojiPanel {
            panel.frame = bounds
            panel.horizontalInset = layout.horizontalInset
            panel.metrics = layout.metrics
        }
        if let panel = feedbackPanel {
            panel.frame = bounds
            panel.horizontalInset = layout.horizontalInset
            panel.metrics = layout.metrics
        }
        if let menu = styleMenu, let key = layout.key(.typr) {
            menu.frame = bounds
            menu.anchor = key.frame
        }
        plane.setNeedsDisplay()
        updateCallout()
    }

    // MARK: - State

    private func applyAppearance() {
        let isDark = appearanceOverride
            ?? FullKeyboardPalette.isDark(appearance: engine.target.keyboardAppearance, traits: traitCollection)
        let next = FullKeyboardPalette(isDark: isDark, design: design)
        backgroundColor = drawsBackdrop ? next.backdrop : .clear
        stripView.inSystemPlatter = !drawsBackdrop
        guard next != palette || !didApplyPalette else { return }
        didApplyPalette = true
        palette = next
        stripView.palette = next
        plane.palette = next
        callout.palette = next
        callout.setNeedsDisplay()
        accentCallout.palette = next
        typrKey.palette = next
        recordingPanel?.palette = next
        feedbackPanel?.palette = next
        styleMenu?.palette = next
    }

    private func refreshReturnKey() {
        plane.returnStyle = ReturnKeyStyle(engine.target.returnKeyType)
        plane.returnIsEnabled = ReturnKeyStyle.isEnabled(
            automatically: engine.target.enablesReturnKeyAutomatically,
            hasText: engine.target.hasText
        )
    }

    private func refreshFromModel() {
        typrKey.isWarm = model.hasFullAccess && model.isWarmAvailable
        if engine.showsGlobe != model.needsGlobeKey || engine.globeKey != model.globeKey
            || engine.bottomRow != model.bottomRow || engine.numberRow != model.numberRow
            || engine.splitColumns != model.splitColumns || engine.letters != model.letters {
            engine.showsGlobe = model.needsGlobeKey
            engine.globeKey = model.globeKey
            engine.bottomRow = model.bottomRow
            if !model.bottomRow.emojiKey { closeEmojiPanel() }
            engine.numberRow = model.numberRow
            engine.splitColumns = model.splitColumns
            engine.letters = model.letters
            setNeedsLayout()
            hostController?.view.setNeedsLayout()
        }
        if orientation != engine.orientation { setNeedsLayout() }
        let recording = model.stagePhase == .recording || model.stagePhase == .transcribing
        if recording != showsRecording {
            setRecording(recording)
        }
        refreshRecordingPanel()
        if let menu = styleMenu {
            menu.style = model.style
        }
        refreshStrip()
        refreshFeedbackPanel()
    }

    private func refreshStrip() {
        let status: String? = if !model.hasFullAccess {
            "Allow Full Access to dictate with Typr"
        } else if model.stagePhase == .failed {
            model.statusMessage
        } else if let note = model.resultNote {
            note
        } else if !model.isWarmAvailable, let notice = model.hostNotice {
            notice
        } else {
            nil
        }
        let code = KeyboardInputModes.offersCodeFromMessages(
            textContentType: engine.target.textContentType,
            hasAppleKeyboard: hasAppleKeyboard
        )
        stripView.update(
            suggestions: status == nil && !code ? withEmoji(engine.suggestions) : engine.suggestions,
            statusText: status,
            showsCodeChip: code,
            showsUndo: offersUndo
        )
    }

    /// The finished word's emoji beside the next-word predictions, so every slot fills; a lone emoji takes the centre.
    private func withEmoji(_ suggestions: [KeyboardSuggestion]) -> [KeyboardSuggestion] {
        guard engine.bottomRow.emojiKey, engine.showsStrip, engine.field == .text, emojiPanel == nil,
              engine.target.autocorrectionType != .no,
              let before = engine.target.documentContextBeforeInput,
              AutocorrectEngine.currentToken(in: before) == nil else { return suggestions }
        if emojiIndex == nil { emojiIndex = EmojiIndex.load(bundle: Bundle(for: FullKeyboardView.self)) }
        return Self.merging(emoji: emojiIndex?.suggestions(before: before) ?? [], into: suggestions)
    }

    /// Up to three chips: a revert offer keeps the left slot, then the emoji, then the words.
    static func merging(emoji: [String], into suggestions: [KeyboardSuggestion]) -> [KeyboardSuggestion] {
        let revert = suggestions.prefix(1).filter { $0.kind == .revert }
        let emoji = emoji.prefix(3 - revert.count).map {
            var chip = KeyboardSuggestion(displayText: $0, replacement: $0, kind: .secondary)
            chip.isEmoji = true
            return chip
        }
        guard !emoji.isEmpty else { return suggestions }
        let words = Array(suggestions.dropFirst(revert.count).prefix(3 - revert.count - emoji.count))
        if revert.isEmpty, emoji.count == 1, words.count == 2 { return [words[0], emoji[0], words[1]] }
        return revert + emoji + words
    }

    func openEmojiPanel() {
        guard emojiPanel == nil, !showsRecording, panelContent == nil else { return }
        if emojiIndex == nil { emojiIndex = EmojiIndex.load(bundle: Bundle(for: FullKeyboardView.self)) }
        guard let index = emojiIndex else { return }
        dismissStyleMenu()
        plane.cancelAllTouches()
        let layout = engine.layout
        let capacity = EmojiPanelView.gridRows(for: layout.metrics) * 8
        let frequent = EmojiPanelView.frequent(used: makeEmojiUsage().ranked(limit: capacity), index: index, capacity: capacity)
        let panel = EmojiPanelView(index: index, frequent: frequent)
        panel.palette = palette
        panel.onKeyDown = { [weak self] in self?.keyFeedback() }
        panel.onSelectionStep = { [weak self] in self?.selectionFeedback() }
        panel.onInsert = { [weak self] emoji in self?.insertEmoji(emoji, typed: emoji) }
        panel.onDelete = { [weak self] in self?.engine.deleteBackward() }
        panel.onDeleteRepeat = { [weak self] held in self?.engine.repeatDelete(heldFor: held) }
        panel.onLetters = { [weak self] in self?.closeEmojiPanel() }
        insertSubview(panel, belowSubview: callout)
        emojiPanel = panel
        for view in [plane, stripView, typrKey, globeButton, accentCallout] as [UIView] { view.isHidden = true }
        callout.show(nil, label: "")
        setNeedsLayout()
        layoutIfNeeded()
    }

    func closeEmojiPanel() {
        guard let panel = emojiPanel else { return }
        panel.tearDown()
        panel.removeFromSuperview()
        emojiPanel = nil
        plane.isHidden = false
        typrKey.isHidden = false
        stripView.isHidden = !engine.showsStrip
        engine.textDidChange()
        refreshReturnKey()
        refreshStrip()
        setNeedsLayout()
    }

    /// `emoji` is what Frequently used counts; `typed` what goes into the field.
    private func insertEmoji(_ emoji: String, typed: String) {
        engine.insertEmoji(typed)
        makeEmojiUsage().record(emoji)
    }

    private func undoPlan(_ undo: DictationUndo) -> DictationUndo.Plan? {
        let target = engine.target
        return undo.plan(before: target.documentContextBeforeInput ?? "",
                         after: target.documentContextAfterInput ?? "",
                         selected: target.selectedText)
    }

    private func undoDictation() {
        guard let undo = lastDictation else { return }
        if let plan = undoPlan(undo) {
            // Moves stay inside the text the host showed, so it doesn't drop them.
            if plan.toEnd != 0 { engine.target.adjustTextPosition(byCharacterOffset: plan.toEnd) }
            for _ in 0..<plan.delete {
                engine.target.deleteBackward()
            }
            if plan.back != 0 { engine.target.adjustTextPosition(byCharacterOffset: plan.back) }
            dictationEdits.didUndo()
        }
        hideUndo()
        engine.textDidChange()
        refreshReturnKey()
    }

    /// The keyboard is going away: report what became of the dictation it followed.
    func finishDictationEdits() {
        guard dictationEdits.isTracking else { return }
        dictationEdits.finish(dictationEditContext)
    }

    /// On the controller's poll: closes the edit window a minute after the dictation.
    func tickDictationEdits() {
        guard dictationEdits.isTracking else { return }
        dictationEdits.tick { dictationEditContext }
    }

    private func observeDictationEdits(fromKeys: Bool) {
        guard dictationEdits.isTracking else { return }
        dictationEdits.observe(dictationEditContext, fromKeys: fromKeys)
    }

    private var dictationEditContext: DictationEditTracker.Context {
        let target = engine.target
        return DictationEditTracker.Context(before: target.documentContextBeforeInput,
                                            after: target.documentContextAfterInput, hasText: target.hasText)
    }

    private var offersUndo: Bool {
        lastDictation.map { undoPlan($0) != nil } ?? false
    }

    private func revalidateUndo() {
        if let undo = lastDictation, undoPlan(undo) == nil {
            hideUndo()
        }
    }

    private func hideUndo() {
        undoHideWork?.cancel()
        undoHideWork = nil
        if lastDictation != nil {
            lastDictation = nil
            refreshStrip()
        }
    }

    // MARK: - Feedback panel

    /// The Typr message the hidden suggestion bar would show. Without Full Access there is none:
    /// holding the Typr key opens Typr instead.
    private var hiddenBarNotice: String? {
        guard !engine.showsStrip, model.hasFullAccess else { return nil }
        if model.stagePhase == .failed { return model.statusMessage }
        if let note = model.resultNote { return note }
        return model.isWarmAvailable ? nil : model.hostNotice
    }

    private var wantedPanelContent: TyprFeedbackPanel.Content? {
        guard !showsRecording else { return nil }
        if model.hasFullAccess, let feedback = model.feedback {
            return feedback.panelContent
        }
        guard let notice = hiddenBarNotice, notice != dismissedNotice else { return nil }
        return .notice(notice)
    }

    /// Shows, updates or hides the panel over the keys.
    private func refreshFeedbackPanel() {
        if hiddenBarNotice == nil { dismissedNotice = nil }
        let next = wantedPanelContent
        guard next != panelContent else { return }
        let wasShown = panelContent != nil
        panelContent = next
        if let next {
            closeEmojiPanel()
            let panel = feedbackPanel ?? makeFeedbackPanel()
            panel.palette = palette
            panel.content = next
            guard !wasShown else { return }
            plane.cancelAllTouches()
            dismissStyleMenu()
            panel.frame = bounds
            panel.isHidden = false
            var covered = keyViews
            covered.append(accentCallout)
            fade(in: [panel], out: covered)
        } else if let panel = feedbackPanel, wasShown {
            fade(in: showsRecording ? [] : keyViews, out: [panel])
        }
    }

    private func makeFeedbackPanel() -> TyprFeedbackPanel {
        let panel = TyprFeedbackPanel()
        panel.alpha = 0
        panel.isHidden = true
        panel.onGood = { [weak self] in self?.rate("good") }
        panel.onProblem = { [weak self] in self?.rate("bad") }
        panel.onRetry = { [weak self] in
            guard let self, let feedback = self.model.feedback else { return }
            self.rate(feedback.retryRating ?? feedback.rating ?? "bad", issues: feedback.retryIssues)
        }
        panel.onOpen = { [weak self] in
            guard let self, let entryID = self.model.feedback?.offer.entryID else { return }
            self.keyFeedback()
            self.model.dismissFeedback()
            self.model.onOpenURL?(TyprFeedbackLink.url(entryID: entryID))
        }
        panel.onDismiss = { [weak self] in self?.dismissPanel() }
        insertSubview(panel, belowSubview: callout)
        feedbackPanel = panel
        setNeedsLayout()
        return panel
    }

    /// Good closes the panel at once; Problem leaves Fix in Typr and ✕ for a moment.
    private func rate(_ rating: String, issues: [String]? = nil) {
        keyFeedback()
        model.rateFeedback(rating, issues: issues)
    }

    private func dismissPanel() {
        keyFeedback()
        if model.feedback != nil {
            model.dismissFeedback()
        } else if case .notice(let notice)? = panelContent {
            if model.hostNotice == notice {
                model.hostNotice = nil
            } else if model.resultNote == notice {
                model.resultNote = nil
            } else {
                dismissedNotice = notice
            }
            refreshFeedbackPanel()
        }
    }

    /// The views a panel covers; the suggestion bar only when it is on.
    private var keyViews: [UIView] {
        var views: [UIView] = [plane, typrKey, globeButton, callout]
        if engine.showsStrip { views.insert(stripView, at: 0) }
        return views
    }

    private func refreshRecordingPanel() {
        guard let panel = recordingPanel, showsRecording else { return }
        panel.update(phase: model.stagePhase == .transcribing ? .processing : .recording)
    }

    private func setRecording(_ recording: Bool) {
        if recording { closeEmojiPanel() }
        showsRecording = recording
        dismissStyleMenu()
        if recording {
            plane.cancelAllTouches()
            hideUndo()
            let panel = recordingPanel ?? makeRecordingPanel()
            panel.palette = palette
            panel.frame = recordingPanelFrame
            refreshRecordingPanel()
            panel.isHidden = false
            var covered: [UIView] = engine.showsStrip ? [stripView] : keyViews + [accentCallout]
            if let feedbackPanel { covered.append(feedbackPanel) }
            let keys: [UIView] = engine.showsStrip ? [plane, typrKey, globeButton, callout] : []
            fade(in: [panel] + keys, out: covered)
        } else if let panel = recordingPanel {
            panel.scope.phase = .hidden
            fade(in: engine.showsStrip ? [stripView] : keyViews, out: [panel]) { [weak self, weak panel] in
                guard let self, !self.showsRecording, let panel, panel === self.recordingPanel else { return }
                panel.tearDown()
                panel.removeFromSuperview()
                self.recordingPanel = nil
            }
        }
    }

    /// The suggestion strip's frame, so the keys neither move nor hide. Without the suggestion bar
    /// there is no strip: the panel takes a row over the top of the keys, which fade out.
    private var recordingPanelFrame: CGRect {
        CGRect(x: 0, y: engine.layout.metrics.stripTop, width: bounds.width, height: KeyboardMetrics.headerHeight)
    }

    private func fade(in shown: [UIView], out hidden: [UIView], after: (() -> Void)? = nil) {
        shown.forEach { $0.isHidden = false }
        let globeHidden = engine.layout.key(.globe) == nil
        let accentHidden = engine.activeAccentMenu == nil
        let duration = window == nil ? 0 : 0.18
        if duration == 0 {
            shown.forEach { $0.alpha = 1 }
            hidden.forEach {
                $0.alpha = 0
                $0.isHidden = true
            }
            if globeHidden { globeButton.isHidden = true }
            if accentHidden { accentCallout.isHidden = true }
            after?()
            return
        }
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            shown.forEach { $0.alpha = 1 }
            hidden.forEach { $0.alpha = 0 }
        } completion: { _ in
            for view in hidden where view.alpha == 0 {
                view.isHidden = true
            }
            if globeHidden { self.globeButton.isHidden = true }
            if accentHidden { self.accentCallout.isHidden = true }
            after?()
        }
    }

    private func makeRecordingPanel() -> TyprKeyRecordingPanel {
        let panel = TyprKeyRecordingPanel(loudness: { [weak model] in model?.liveLoudnessDB ?? -62 })
        panel.alpha = 0
        panel.onDone = { [weak self] in self?.model.onStopTap?() }
        panel.onCancel = { [weak self] in self?.model.onCancelTap?() }
        insertSubview(panel, belowSubview: callout)
        recordingPanel = panel
        setNeedsLayout()
        return panel
    }

    private func engineChanged() {
        plane.setNeedsDisplay()
        plane.updateTrail()
        updateCallout()
        refreshStrip()
        if globeButton.isHidden != (engine.layout.key(.globe) == nil) || typrKey.frame != engine.layout.key(.typr)?.hitFrame {
            setNeedsLayout()
        }
    }

    private func updateCallout() {
        if let menu = engine.activeAccentMenu {
            callout.show(nil, label: "")
            accentCallout.show(menu)
            return
        }
        accentCallout.show(nil)
        let layout = engine.layout
        if let key = engine.previewKey, let balloon = layout.balloon(for: key) {
            callout.fontSize = layout.orientation.glyphs.balloonLetter
            callout.show(balloon, label: engine.displayLabel(for: key))
        } else {
            callout.show(nil, label: "")
        }
    }

    // MARK: - Actions

    private func keyFeedback() {
        UIDevice.current.playInputClick()
        if allowsHaptics() {
            haptics.impactOccurred(intensity: 0.65)
            haptics.prepare()
        }
    }

    private func selectionFeedback() {
        if allowsHaptics() {
            selectionHaptics.selectionChanged()
            selectionHaptics.prepare()
        }
    }

    /// A still hold on the Typr key: dictate, or open Typr.
    private func typrKeyHeld() {
        guard !showsRecording else { return }
        if allowsHaptics() { haptics.impactOccurred() }
        dismissStyleMenu()
        if typrKey.isWarm {
            model.onDictateTap?()
        } else {
            model.onColdStart?()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard stripPressTouch == nil, let touch = touches.first, beginStripPress(at: touch.location(in: self)) else {
            super.touchesBegan(touches, with: event)
            return
        }
        stripPressTouch = touch
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = stripPressTouch, touches.contains(touch) else {
            super.touchesMoved(touches, with: event)
            return
        }
        moveStripPress(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = stripPressTouch, touches.contains(touch) else {
            super.touchesEnded(touches, with: event)
            return
        }
        endStripPress()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = stripPressTouch, touches.contains(touch) else {
            super.touchesCancelled(touches, with: event)
            return
        }
        endStripPress()
    }

    /// A finger on the strip where no word or chip is (`KeyboardStripView.hitTest`): touch-down
    /// arms like the Typr key, a still hold dictates like holding it, and the end stops that
    /// dictation (push to talk). A tap, or a slide past 10 pt before the hold, does nothing.
    @discardableResult
    func beginStripPress(at point: CGPoint) -> Bool {
        guard !stripView.isHidden, stripView.frame.contains(point), !showsRecording, styleMenu == nil else { return false }
        endStripPress()
        stripPressStart = point
        let work = DispatchWorkItem { [weak self] in self?.stripHoldElapsed() }
        stripHoldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TyprKeyGesture.holdDuration, execute: work)
        if typrKey.isWarm { model.onArmDictation?() }
        return true
    }

    func moveStripPress(to point: CGPoint) {
        guard let start = stripPressStart, stripHoldWork != nil, hypot(point.x - start.x, point.y - start.y) > 10 else { return }
        endStripPress()
    }

    func endStripPress() {
        stripPressTouch = nil
        guard stripPressStart != nil else { return }
        stripPressStart = nil
        stripHoldWork?.cancel()
        stripHoldWork = nil
        model.onDisarmDictation?()
        if stripHoldDictates { model.onStopTap?() }
        stripHoldDictates = false
    }

    private func stripHoldElapsed() {
        stripHoldWork = nil
        guard !showsRecording, styleMenu == nil else { return }
        stripHoldDictates = typrKey.isWarm
        typrKeyHeld()
    }

    /// Typr: a quick tap on the Typr key types a space, like the space bar.
    private func typrKeyTapped() {
        guard !showsRecording else { return }
        keyFeedback()
        dismissStyleMenu()
        engine.typeSpaceFromTyprKey()
    }

    /// Typr: sliding down on the Typr key shows the compact dictation bar.
    private func typrKeySlidDown() {
        guard !showsRecording, allowsCompactBar else { return }
        if allowsHaptics() { haptics.impactOccurred() }
        dismissStyleMenu()
        plane.cancelAllTouches()
        onShowCompactBar?()
    }

    /// Hold and slide: light the row under the finger, and pick it on release.
    private func forwardMenuPoint(_ point: CGPoint, release: Bool) {
        guard let menu = styleMenu else { return }
        let local = typrKey.convert(point, to: menu)
        if release {
            menu.finishDrag(at: local)
        } else {
            menu.updateDrag(at: local)
        }
    }

    private func showStyleMenu() {
        guard styleMenu == nil, !showsRecording else { return }
        if allowsHaptics() {
            haptics.impactOccurred()
            haptics.prepare()
        }
        plane.cancelAllTouches()
        let menu = TyprStyleMenuView()
        menu.palette = palette
        menu.style = model.style
        menu.onHoverChanged = { [weak self] in self?.selectionFeedback() }
        menu.onStyle = { [weak self] style in
            self?.model.onStyleSelected?(style)
            self?.dismissStyleMenu()
        }
        menu.onDismiss = { [weak self] in self?.dismissStyleMenu() }
        addSubview(menu)
        styleMenu = menu
        setNeedsLayout()
        layoutIfNeeded()
    }

    func dismissStyleMenu() {
        styleMenu?.removeFromSuperview()
        styleMenu = nil
    }

    /// Tests: tap a suggestion in the strip.
    func debugPick(_ suggestion: KeyboardSuggestion) {
        stripView.onSelectSuggestion?(suggestion)
    }

    /// Tests: tap Code from Messages.
    func debugTapCodeFromMessages() {
        stripView.onCodeFromMessages?()
    }

    /// Fixtures: open the menu without a long press.
    func debugShowStyleMenu() {
        showStyleMenu()
    }

    private func configureGlobe() {
        globeButton.removeTarget(nil, action: nil, for: .allEvents)
        if let controller = hostController {
            globeButton.addTarget(
                controller,
                action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                for: .allTouchEvents
            )
        }
    }
}
