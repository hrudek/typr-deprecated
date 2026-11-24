import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private let bridge = KeyboardBridge()
    private let feedbackBridge = DictationFeedbackBridge.shared
    private var ownedFeedbackJobs = Set<String>()
    private var lastFeedbackEventID: UUID?
    private var confirmedFeedback: DictationFeedbackPresentation?
    private var confirmedFeedbackOrder: DictationFeedbackOrder?
    private let viewModel = KeyboardViewModel()
    private var pollTimer: Timer?
    private var coldStartJobID = UUID().uuidString
    private var armedJobID: String?
    private let localDictation = KeyboardLocalDictation()
    private var lastRemountBucket: Int = 0
    private var lastFullAccessNote: TimeInterval = 0
    private var surface: UIView?
    private var fullKeyboard: TyprFullKeyboardView?
    private var hexKeyboard: FullKeyboardView?
    private var hasFullKeyboard: Bool { fullKeyboard != nil || hexKeyboard != nil }
    private var heightConstraint: NSLayoutConstraint?
    private var pollInterval: TimeInterval = 0
    private var didHandOffCurrentField = false
    private var didWarmLexicon = false
    private var handOffWaitsForPosture = false
    private var offeredDictation: KeyboardSnapshot?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        NotificationCenter.default.addObserver(self, selector: #selector(hostWillResignActive),
                                               name: .NSExtensionHostWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostDidBecomeActive),
                                               name: .NSExtensionHostDidBecomeActive, object: nil)
        syncFromBridge(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ownedFeedbackJobs.insert(coldStartJobID)
        if ownedFeedbackJobs.count > 32 { ownedFeedbackJobs = [coldStartJobID] }
        coldStartJobID = UUID().uuidString
        didHandOffCurrentField = false
        KeyboardHost.appeared()
        viewModel.hostNotice = nil
        viewModel.globeKey = TyprFullKeyboardSettings().globeKey
        viewModel.bottomRow = TyprFullKeyboardSettings().bottomRow
        viewModel.numberRow = TyprFullKeyboardSettings().numberRow
        viewModel.splitKeyboard = TyprFullKeyboardSettings().splitKeyboard
        viewModel.splitColumns = TyprFullKeyboardSettings().splitColumns
        viewModel.letters = TyprFullKeyboardSettings().letters
        mountSurface()
        refreshProtectedLexicon()
        fullKeyboard?.prepareForField()
        hexKeyboard?.prepareForField()
        hexTypr?.syncPredictions()
        handOffNumericPadIfNeeded()
        syncFromBridge(animated: false)
        schedulePoll(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        warmFullKeyboardLexiconIfNeeded()
        if keyboardDictationEnabled { localDictation.prepare(in: view) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fullKeyboard?.suspendSuggestions()
        fullKeyboard?.engine.endTypingLogWord("dismiss")
        fullKeyboard?.discardTouchEvidence()
        fullKeyboard?.flushLearning()
        fullKeyboard?.finishDictationEdits()
        learning.flush()
        hexTypr?.predictions?.cancel()
        releaseTyprSwipe()
        hexKeyboard?.engine.commitHangulComposition()
        pollTimer?.invalidate()
        pollTimer = nil
        disarmWarmDictation()
        localDictation.keyboardWillHide()
        viewModel.dismissFeedback()
    }

    /// Control Center, Notification Center, Siri or an alert: stop late suggestion work only.
    /// Current-word taps, undo and rejected pairs stay; host edits still arrive as textDidChange.
    @objc private func hostWillResignActive() {
        fullKeyboard?.suspendSuggestions()
    }

    /// Not `prepareForField()`: returning to the host must not reset layer, shift or undo.
    /// A keyboard touch also resumes suggestions if this notice is missed.
    @objc private func hostDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        refreshProtectedLexicon()
        fullKeyboard?.resumeSuggestions()
    }

    private func releaseTyprSwipe() {
        guard let hexTypr else { return }
        Task { await hexTypr.releaseSwipeResources() }
    }

    private func refreshProtectedLexicon() {
        let lexicon = hasFullAccess
            ? ProtectedPersonalLexicon.load(directory: KeyboardLearningStore.sharedDirectory) : .empty
        protectedLexicon = lexicon
        fullKeyboard?.engine.autocorrect.loadProtectedLexicon(lexicon)
        fullKeyboard?.engine.refreshSuggestions()
        if let hexTypr {
            hexTypr.engine.loadProtectedLexicon(lexicon)
            hexKeyboard?.engine.refreshSuggestions()
        }
    }

    private var hexTypr: TyprAutocorrectAdapter? { hexKeyboard?.engine.autocorrect as? TyprAutocorrectAdapter }
    private var protectedLexicon = ProtectedPersonalLexicon.empty
    private lazy var learning = SharedKeyboardLearning { [unowned self] in self.learningSession() }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        fullKeyboard?.handleMemoryWarning()
        hexKeyboard?.handleMemoryWarning()
        releaseTyprSwipe()
        localDictation.releaseIfIdle()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // The keyboard's own window is only as tall as the keyboard; the scene's screen is the display it is on.
        fullKeyboard?.containerSize = view.window?.windowScene?.screen.bounds.size
        if let height = fullKeyboard?.preferredHeight ?? hexKeyboard?.preferredHeight,
           heightConstraint?.constant != height {
            heightConstraint?.constant = height
            preferredContentSize.height = height
        }
        if handOffWaitsForPosture { handOffNumericPadIfNeeded() }
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        KeyboardHost.harvest()
        if TyprKeyboardFieldRouting.route(for: textDocumentProxy.keyboardType) != .handOff {
            didHandOffCurrentField = false
        }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        fullKeyboard?.selectionDidChange()
        hexKeyboard?.engine.commitHangulIfHostMoved()
        KeyboardHost.harvest()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        KeyboardHost.harvest()
        updateKeyboardTraits()
        fullKeyboard?.textDidChange()
        hexKeyboard?.textDidChange()
        handOffNumericPadIfNeeded()
    }

    /// Like learning: files only with real Full Access on a device, never in the simulator.
    private func typingLog(persistent: Bool) -> TypingLogRecorder? {
        guard persistent, let directory = KeyboardLearningStore.sharedDirectory else { return nil }
        let store = TyprTypingLogStore(directory: directory)
        return TypingLogRecorder { [weak self] word in
            if self?.hasFullAccess == true { store.append(word) }
        }
    }

    private func handOffNumericPadIfNeeded() {
        if let hexKeyboard {
            handOffNumericPad(hexKeyboard)
            return
        }
        guard fullKeyboard != nil else { return }
        if TyprKeyboardFieldRouting.route(for: textDocumentProxy.keyboardType) == .handOff {
            guard !didHandOffCurrentField else { return }
            didHandOffCurrentField = true
            if needsInputModeSwitchKey {
                advanceToNextInputMode()
            }
        } else {
            didHandOffCurrentField = false
        }
    }

    private func handOffNumericPad(_ keyboard: FullKeyboardView) {
        guard KeyboardFieldRouting.route(for: textDocumentProxy.keyboardType) == .handOff else {
            didHandOffCurrentField = false
            return
        }
        guard !didHandOffCurrentField else { return }
        // The Duo's posture needs the keyboard's window: layout asks again once it has one.
        guard let posture = keyboard.currentPosture else {
            handOffWaitsForPosture = true
            return
        }
        handOffWaitsForPosture = false
        didHandOffCurrentField = true
        if KeyboardFieldRouting.handsOffNumberPad(needsInputModeSwitchKey: needsInputModeSwitchKey, posture: posture) {
            advanceToNextInputMode()
        }
    }

    private func warmFullKeyboardLexiconIfNeeded() {
        if let hexKeyboard {
            hexKeyboard.warmUpTextCheckerAsync()
            guard !didWarmLexicon else { return }
            didWarmLexicon = true
            // UIKit calls back on its lexicon-request queue: the callback is nonisolated and
            // hops to the main actor itself (Hex's TestFlight build 3 crash).
            requestSupplementaryLexicon { @Sendable [weak self] lexicon in
                Task { @MainActor in self?.hexKeyboard?.loadLexicon(lexicon) }
            }
            return
        }
        guard let fullKeyboard else { return }
        fullKeyboard.warmUpTextCheckerAsync()
        guard !didWarmLexicon else { return }
        didWarmLexicon = true
        // UIKit calls this completion on a background queue; it must not be MainActor-isolated.
        requestSupplementaryLexicon(completion: LexiconDelivery.handler { [weak self] entries in
            self?.fullKeyboard?.loadLexiconEntries(entries)
        })
    }

    private func configureView() {
        view.backgroundColor = .clear

        viewModel.inputViewController = self
        viewModel.onDictateTap = { [weak self] in self?.startWarmDictation() }
        viewModel.onArmDictation = { [weak self] in self?.armWarmDictation() }
        viewModel.onDisarmDictation = { [weak self] in self?.disarmWarmDictation() }
        viewModel.onStopTap = { [weak self] in self?.stopWarmDictation() }
        viewModel.onCancelTap = { [weak self] in self?.cancelWarmDictation() }
        viewModel.onStyleSelected = { [weak self] style in
            guard let self else { return }
            self.bridge.style = style
            if self.viewModel.style != style {
                self.viewModel.style = style
            }
        }
        viewModel.onColdStart = { [weak self] in self?.coldStart() }
        viewModel.onPasteDictation = { [weak self] in self?.pasteOfferedDictation() }
        viewModel.onLanguageSelected = { [weak self] identifier in
            LanguageSettings().chooseTyprDictationLanguage(DictationLanguage(identifier: identifier), typr: TyprSettings())
            self?.syncLanguageState()
        }
        viewModel.onTranslationToggled = { [weak self] on in
            DictationTranslationSettings().isEnabled = on
            self?.syncLanguageState()
        }
        viewModel.onTranslationTargetSelected = { [weak self] target in
            let settings = DictationTranslationSettings()
            settings.targetLanguage = target
            settings.isEnabled = true
            self?.syncLanguageState()
        }
        localDictation.onHandOff = { [weak self] in self?.coldStart() }
        viewModel.onFeedbackRating = { [weak self] rating, issues in self?.queueFeedback(rating: rating, issues: issues) }
        viewModel.onSpace = { [weak self] in self?.viewModel.dismissFeedback(); self?.textDocumentProxy.insertText(" ") }
        viewModel.onDelete = { [weak self] in self?.viewModel.dismissFeedback(); self?.textDocumentProxy.deleteBackward() }
        viewModel.onReturn = { [weak self] in self?.viewModel.dismissFeedback(); self?.textDocumentProxy.insertText("\n") }
        viewModel.onOpenURL = { [weak self] url in
            guard let self else { return }
            ContainingAppOpener.open(url, from: self)
        }
        viewModel.onShowFullKeyboard = { [weak self] in self?.switchSurface(toCompactBar: false) }
        viewModel.onHexKeyPress = { [weak self] _ in self?.armHexKeyDictation() }
        viewModel.onHexKeyAbandon = { [weak self] in self?.disarmWarmDictation() }
        viewModel.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 140)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
        mountSurface()
    }

    private func mountSurface() {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let wantsFull = KeyboardSurfaceChoice.wantsFullKeyboard(
            isPhone: isPhone,
            compactChosen: KeyboardSurfaceChoice().showsCompactBar
        )
        if viewModel.showsFullKeyboardSwitch != isPhone {
            viewModel.showsFullKeyboardSwitch = isPhone
        }
        fullKeyboard?.allowsCompactBar = isPhone
        let wantsTypr = wantsFull && TyprSettings()[experiment: .typrKeyboard]
        let wantsTyprTyping = wantsFull && !wantsTypr && TyprSettings()[experiment: .typrTyping]
        guard surface == nil || wantsFull != hasFullKeyboard || wantsTypr != (fullKeyboard != nil)
            || wantsTyprTyping != (hexTypr != nil) else { return }
        guard surface == nil || viewModel.stagePhase == .idle || viewModel.stagePhase == .failed else { return }

        children.forEach { child in
            child.willMove(toParent: nil)
            child.removeFromParent()
        }
        fullKeyboard?.suspendSuggestions()
        fullKeyboard?.discardTouchEvidence()
        hexKeyboard?.engine.commitHangulComposition()
        surface?.removeFromSuperview()
        fullKeyboard?.flushLearning()
        fullKeyboard?.finishDictationEdits()
        fullKeyboard = nil
        hexKeyboard = nil
        handOffWaitsForPosture = false
        didWarmLexicon = false

        let mounted: UIView
        if wantsFull, !wantsTypr {
            let keyboard = makeHexKeyboard()
            hexKeyboard = keyboard
            mounted = keyboard
            heightConstraint?.constant = keyboard.preferredHeight
        } else if wantsFull {
            let keyboard = TyprFullKeyboardView(
                model: viewModel,
                target: TyprDocumentProxyTextTarget { [unowned self] in self.textDocumentProxy },
                autocorrect: TyprAutocorrectEngine(learning: learning.session(fullAccess: hasFullAccess)),
                statistics: UsageStatisticsSession(
                    store: UsageStatisticsStore(directory: persistsLearning ? KeyboardLearningStore.sharedDirectory : nil),
                    allowsPersistence: { [weak self] in self?.hasFullAccess == true }
                ),
                typingLog: typingLog(persistent: persistsLearning)
            )
            keyboard.hostController = self
            keyboard.dictationEdits.onResult = { [weak self] result in
                guard self?.hasFullAccess == true else { return }
                DictationLearningStore().record(result)
            }
            if hasFullAccess {
                keyboard.hasCloudKey = Self.hasAnthropicKey
                keyboard.cloudPredictions = Self.anthropicPredictions()
            }
            keyboard.allowsHaptics = { [weak self] in self?.hasFullAccess ?? false }
            keyboard.allowsCompactBar = isPhone
            keyboard.onShowCompactBar = { [weak self] in self?.switchSurface(toCompactBar: true) }
            keyboard.onDeviceModel = OnDeviceModelPredictions.systemModel()
            fullKeyboard = keyboard
            // Surface switches can create a keyboard without another viewWillAppear callback.
            let imports = hasFullAccess
                ? ProtectedPersonalLexicon.load(directory: KeyboardLearningStore.sharedDirectory) : .empty
            keyboard.engine.autocorrect.loadProtectedLexicon(imports)
            mounted = keyboard
            heightConstraint?.constant = keyboard.preferredHeight
        } else {
            let hosting = UIHostingController(rootView: KeyboardSurfaceView(model: viewModel))
            hosting.view.backgroundColor = .clear
            addChild(hosting)
            hosting.didMove(toParent: self)
            mounted = hosting.view
            heightConstraint?.constant = 140
        }
        preferredContentSize.height = heightConstraint?.constant ?? 140
        mounted.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mounted)
        NSLayoutConstraint.activate([
            mounted.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mounted.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mounted.topAnchor.constraint(equalTo: view.topAnchor),
            mounted.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        surface = mounted
        schedulePoll(force: false)
    }

    /// Learning files are written only with real Full Access on a device; otherwise RAM while
    /// the keyboard runs.
    private var persistsLearning: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        hasFullAccess
        #endif
    }

    private func learningSession() -> KeyboardLearningSession {
        KeyboardLearningSession(
            store: persistsLearning ? KeyboardLearningStore() : nil,
            defaults: UserDefaults(suiteName: KeyboardBridge.appGroup),
            allowsPersistence: { [weak self] in self?.hasFullAccess == true }
        )
    }

    private static func hasAnthropicKey() -> Bool {
        KeychainSecret.keyboardAnthropicAPIKey.read()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func anthropicPredictions() -> AnthropicPredictionProvider {
        AnthropicPredictionProvider(key: { KeychainSecret.keyboardAnthropicAPIKey.read() })
    }

    private func makeHexKeyboard() -> FullKeyboardView {
        let typr = FullKeyboardView.typrTypingBackend {
            TyprAutocorrectEngine(learning: learning.session(fullAccess: hasFullAccess))
        }
        typr?.engine.loadProtectedLexicon(protectedLexicon)
        if let typr {
            if hasFullAccess {
                typr.hasCloudKey = Self.hasAnthropicKey
                typr.cloudPredictions = Self.anthropicPredictions()
            }
            typr.onDeviceModel = OnDeviceModelPredictions.systemModel()
            typr.syncPredictions()
        }
        let keyboard = FullKeyboardView(
            model: viewModel,
            target: DocumentProxyTextTarget { [weak self] in self?.textDocumentProxy },
            autocorrect: typr
        )
        keyboard.hostController = self
        keyboard.onPreferredHeightChange = { [weak self] in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
        keyboard.allowsHaptics = { [weak self] in
            self?.hasFullAccess == true && FullKeyboardSettings().haptics
        }
        return keyboard
    }

    /// Typr: the compact bar's keyboard key or a slide down on the Typr key picked a surface.
    /// Only while idle.
    private func switchSurface(toCompactBar compact: Bool) {
        guard viewModel.stagePhase == .idle || viewModel.stagePhase == .failed else { return }
        KeyboardSurfaceChoice().showsCompactBar = compact
        // Let the tapped key's touch handling finish before its view goes away.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.viewModel.activeTray != .none {
                self.viewModel.setActiveTray(.none, reduceMotion: true)
            }
            self.mountSurface()
            self.fullKeyboard?.prepareForField()
            self.hexKeyboard?.prepareForField()
            self.hexTypr?.syncPredictions()
            self.warmFullKeyboardLexiconIfNeeded()
            self.syncFromBridge(animated: false)
            self.schedulePoll(force: true)
        }
    }

    private func schedulePoll(force: Bool) {
        let busy = viewModel.stagePhase == .recording || viewModel.stagePhase == .transcribing
            || viewModel.pendingCommand != nil || armedJobID != nil || localDictation.isActive
        let interval: TimeInterval = !hasFullKeyboard ? 0.04 : (busy ? 1.0 / 30 : 0.25)
        guard force || (pollTimer != nil && interval != pollInterval) else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFromBridge(animated: true)
            }
        }
    }

    private func queueFeedback(rating: String, issues: [String]?) {
        guard hasFullAccess, feedbackBridge.switchesEnabled, let presentation = viewModel.feedback else { return }
        let offer = presentation.offer
        if confirmedFeedback?.offer != offer { confirmedFeedback = presentation; confirmedFeedbackOrder = nil }
        viewModel.feedback?.message = "Queuing…"
        viewModel.feedback?.rating = rating
        if let issues { viewModel.feedback?.issues = issues }
        let event = DictationFeedbackEvent(eventID: UUID(), offer: offer, rating: rating,
            issues: issues, createdAt: Date())
        lastFeedbackEventID = event.eventID
        feedbackBridge.enqueue(event) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, self.confirmedFeedback?.offer == offer else { return }
                let current = self.viewModel.feedback
                guard current == nil || current?.offer == offer else { return }
                if success, self.confirmedFeedbackOrder.map({ $0 < event.order }) ?? true {
                    self.confirmedFeedbackOrder = event.order
                    self.confirmedFeedback?.rating = event.rating
                    if let issues = event.issues { self.confirmedFeedback?.issues = issues }
                }
                guard self.lastFeedbackEventID == event.eventID else { return }
                // The full keyboard closes its panel on Good at once: only a failure brings it back.
                guard current != nil || !success else { return }
                self.viewModel.feedback = self.confirmedFeedback
                self.viewModel.feedback?.message = success ? "Noted on keyboard" : "Not queued: full, expired or unavailable"
                if !success {
                    self.viewModel.feedback?.retryRating = event.rating
                    self.viewModel.feedback?.retryIssues = event.issues
                }
            }
        }
    }

    private func syncFromBridge(animated: Bool) {
        let now = Date().timeIntervalSince1970
        updateKeyboardTraits()
        fullKeyboard?.syncSettings()
        hexKeyboard?.syncSettings()
        let keyDesign = TyprFullKeyboardSettings().design
        if viewModel.keyDesign != keyDesign { viewModel.keyDesign = keyDesign }

        #if targetEnvironment(simulator)
        let simSnap = bridge.snapshot()
        let effectiveFullAccess = hasFullAccess || simSnap.isAvailable(at: now)
        #else
        let effectiveFullAccess = hasFullAccess
        #endif

        guard effectiveFullAccess else {
            viewModel.dismissFeedback()
            viewModel.applyBridgeState(
                hasFullAccess: false,
                snapshot: .offline,
                isModelInstalled: false,
                style: viewModel.style,
                now: now,
                clearPending: true,
                animated: animated
            )
            return
        }

        if now - lastFullAccessNote >= 5 {
            lastFullAccessNote = now
            bridge.fullAccessSeenAt = now
        }

        let local = localDictation.snapshot(now: now)
        var snap = local ?? bridge.snapshot()
        let permission = feedbackBridge.permission
        if !feedbackBridge.switchesEnabled || permission?.enabled != true || snap.state == .recording || snap.state == .transcribing
            || (viewModel.feedback.map { $0.offer.expiresAt < Date() || $0.offer.generation != permission?.generation } ?? false) {
            viewModel.dismissFeedback()
        }
        var insertedResult = false

        if snap.hasDeliverableResult(at: now),
           let resultID = snap.resultID,
           let rawTranscript = snap.transcript,
           bridge.lastInsertedResultID != resultID,
           local != nil || bridge.lastInsertedAppResultID != resultID {
            insertDictation(rawTranscript, resultID: resultID, translated: snap.translated == true, fromApp: local == nil)
            viewModel.translationNote = snap.translationFailure
            insertedResult = true
            if feedbackBridge.switchesEnabled, snap.state != .recording, snap.state != .transcribing {
                viewModel.feedback = DictationFeedbackPresentation.inserted(offer: snap.feedbackOffer,
                    resultID: resultID, ownedJobs: ownedFeedbackJobs.union(bridge.feedbackJobs).union([coldStartJobID]),
                    permission: permission, now: Date(timeIntervalSince1970: now))
            }
            coldStartJobID = UUID().uuidString
            localDictation.delivered(resultID: resultID)
            snap = localDictation.snapshot(now: now) ?? bridge.snapshot()
        }
        refreshOfferedDictation(now: now)
        syncLanguageState()
        if keyboardDictationEnabled { localDictation.checkLanguage() }
        viewModel.armsWhenCold = localDictationRoute == .keyboard

        viewModel.applyBridgeState(
            hasFullAccess: true,
            snapshot: snap,
            isModelInstalled: bridge.isModelInstalled,
            style: bridge.style,
            now: now,
            clearPending: insertedResult,
            animated: animated
        )

        fullKeyboard?.tickDictationEdits()
        remountIfNeeded(now: now)
        schedulePoll(force: false)
    }

    private func insertDictation(_ rawTranscript: String, resultID: String, translated: Bool, fromApp: Bool) {
        let before = textDocumentProxy.documentContextBeforeInput
        let after = textDocumentProxy.documentContextAfterInput
        let insertion = TranscriptFormatter.insertionText(
            for: rawTranscript,
            beforeContext: before,
            afterContext: after
        )
        textDocumentProxy.insertText(insertion)
        fullKeyboard?.didInsertDictation(insertion, before: before ?? "", after: after ?? "",
                                         learns: TyprSettings()[experiment: .learnFromEdits] && !translated)
        hexKeyboard?.didInsertDictation(insertion, before: before ?? "", after: after ?? "")
        bridge.markInserted(resultID: resultID, fromApp: fromApp)
    }

    private func syncLanguageState() {
        let settings = LanguageSettings()
        let typr = TyprSettings()
        let explicit = settings.typrDictationChoice(typr: typr).speechLocaleIdentifier
        let automatic = settings.typrDictationLanguage(typr: typr).speechLocaleIdentifier
        let translation = DictationTranslationSettings()
        let target = translation.isEnabled ? translation.targetLanguage : nil
        let translationLanguage: String? = if #available(iOS 26.0, *) { translation.targetLanguage } else { nil }
        let choices = LanguageSettings.typrDictationLanguages
        let targets = translationLanguage == nil ? [] : choices.map { Locale.Language(identifier: $0).minimalIdentifier }
        if viewModel.dictationLanguage != explicit { viewModel.dictationLanguage = explicit }
        if viewModel.automaticLanguage != automatic { viewModel.automaticLanguage = automatic }
        if viewModel.languageChoices != choices { viewModel.languageChoices = choices }
        if viewModel.translationTarget != target { viewModel.translationTarget = target }
        if viewModel.translationLanguage != translationLanguage { viewModel.translationLanguage = translationLanguage }
        if viewModel.translationTargetChoices != targets { viewModel.translationTargetChoices = targets }
    }

    private func refreshOfferedDictation(now: TimeInterval) {
        let offer = bridge.offeredAppResult(at: now)
        offeredDictation = offer
        if viewModel.offeredDictation != offer?.transcript {
            viewModel.offeredDictation = offer?.transcript
        }
    }

    private func pasteOfferedDictation() {
        guard let offer = offeredDictation, let resultID = offer.resultID, let transcript = offer.transcript else { return }
        insertDictation(transcript, resultID: resultID, translated: offer.translated == true, fromApp: true)
        offeredDictation = nil
        viewModel.offeredDictation = nil
    }

    /// Picks up a changed keyboard setting (full keyboard) every 2 s.
    private func remountIfNeeded(now: TimeInterval) {
        let bucket = Int(now / 2.0)
        guard bucket != lastRemountBucket else { return }
        lastRemountBucket = bucket
        mountSurface()
    }

    /// A share sheet, a notification's reply or Spotlight closes once left, taking its text
    /// with it, so with Typr automatic host return Typr is not opened from there.
    private func coldStart() {
        if localDictation.isArmed || localDictationRoute == .keyboard, localDictation.start(in: view) {
            viewModel.hostNotice = nil
            schedulePoll(force: false)
            return
        }
        let host = KeyboardHost.app(of: self)
        guard !TyprSettings()[experiment: .typrAutomaticHostReturn] || KeyboardHost.canReturn(to: host) else {
            viewModel.hostNotice = "Turn on Keep mic warm in Typr first"
            return
        }
        viewModel.hostNotice = nil
        let now = Date().timeIntervalSince1970
        let request: KeyboardLaunchRequest = if bridge.isModelInstalled {
            .startRecording(jobID: coldStartJobID, requestedAt: now, style: bridge.style, host: host)
        } else {
            .startSession(requestedAt: now, host: host)
        }
        bridge.ownFeedbackJob(coldStartJobID)
        ContainingAppOpener.open(request.url, from: self)
    }

    private var keyboardDictationEnabled: Bool {
        KeyboardDictationRoute.keyboardAllowed(fullAccess: hasFullAccess)
    }

    private var localDictationRoute: KeyboardDictationRoute {
        let app = bridge.snapshot()
        return localDictation.route(
            enabled: keyboardDictationEnabled,
            warm: app.state == .ready && app.isAvailable(at: Date().timeIntervalSince1970)
        )
    }

    private func updateKeyboardTraits() {
        let globe = needsInputModeSwitchKey
        if viewModel.needsGlobeKey != globe {
            viewModel.needsGlobeKey = globe
        }
        // Fields that ask for a dark keyboard get one even in light mode, like the system keyboard.
        overrideUserInterfaceStyle = textDocumentProxy.keyboardAppearance == .dark ? .dark : .unspecified
        let nextReturn = TyprReturnKeyStyle(textDocumentProxy.returnKeyType)
        if viewModel.returnKey != nextReturn {
            viewModel.returnKey = nextReturn
        }
        let returnOn = TyprReturnKeyStyle.isEnabled(
            automatically: textDocumentProxy.enablesReturnKeyAutomatically,
            hasText: textDocumentProxy.hasText
        )
        if viewModel.returnKeyEnabled != returnOn {
            viewModel.returnKeyEnabled = returnOn
        }
    }

    private func armWarmDictation() {
        disarmWarmDictation()
        let now = Date().timeIntervalSince1970
        let snapshot = viewModel.currentSnapshot
        guard viewModel.hasFullAccess, viewModel.stagePhase == .idle, viewModel.pendingCommand == nil else { return }
        guard snapshot.state == .ready, snapshot.isAvailable(at: now) else {
            if localDictationRoute == .keyboard {
                localDictation.arm(in: view)
                schedulePoll(force: false)
            }
            return
        }
        let jobID = UUID().uuidString
        armedJobID = jobID
        bridge.send(.arm, jobID: jobID, style: viewModel.style, sentAt: now)
        schedulePoll(force: false)
    }

    private func armHexKeyDictation() {
        guard viewModel.isWarmAvailable || viewModel.armsWhenCold else { return }
        armWarmDictation()
    }

    private func disarmWarmDictation() {
        localDictation.discard()
        guard let jobID = armedJobID else { return }
        armedJobID = nil
        bridge.send(.cancel, jobID: jobID, style: viewModel.style, sentAt: Date().timeIntervalSince1970)
        schedulePoll(force: false)
    }

    private func startWarmDictation() {
        let now = Date().timeIntervalSince1970
        guard viewModel.hasFullAccess, viewModel.currentSnapshot.isAvailable(at: now) else {
            disarmWarmDictation()
            return
        }
        let jobID = armedJobID ?? UUID().uuidString
        armedJobID = nil
        ownedFeedbackJobs.insert(jobID)
        bridge.ownFeedbackJob(jobID)
        viewModel.dismissFeedback()
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .start, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        // The text around the cursor and the host app, capped, as context for AI cleanup (Hex's
        // caret text). Only in the start command; cold starts open a URL and send no text.
        bridge.send(.start, jobID: jobID, style: viewModel.style, sentAt: now,
                    context: textDocumentProxy.documentContextBeforeInput,
                    selected: textDocumentProxy.selectedText,
                    after: textDocumentProxy.documentContextAfterInput,
                    host: KeyboardHost.app(of: self))
    }

    private func stopWarmDictation() {
        if localDictation.isActive {
            localDictation.stop()
            return
        }
        let now = Date().timeIntervalSince1970
        guard let jobID = viewModel.currentSnapshot.jobID ?? viewModel.pendingCommand?.jobID else { return }
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .stop, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        bridge.send(.stop, jobID: jobID, style: viewModel.style, sentAt: now)
    }

    private func cancelWarmDictation() {
        if localDictation.isActive {
            localDictation.cancel()
            return
        }
        let now = Date().timeIntervalSince1970
        guard let jobID = viewModel.currentSnapshot.jobID ?? viewModel.pendingCommand?.jobID else { return }
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .cancel, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        bridge.send(.cancel, jobID: jobID, style: viewModel.style, sentAt: now)
    }
}
