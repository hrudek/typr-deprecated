import Foundation

@MainActor
protocol DictationEditHooks: AnyObject {
    var onTextEdit: (() -> Void)? { get set }
    var onUndoDictation: (() -> Void)? { get set }
    var onReturnKey: (() -> Void)? { get set }
}

extension FullKeyboardView: DictationEditHooks {}

@MainActor
final class KeyboardDictationLearning {
    private(set) var hexEdits: DictationEditTracker
    private(set) var typrEdits: TyprDictationEditTracker
    private let settings: TyprSettings
    private let journalSettings: TypingJournalSettings
    private let now: () -> TimeInterval
    private let context: () -> DictationEditTracker.Context
    private let returnKeyIsSend: () -> Bool
    private let record: (_ result: DictationEditResult, _ language: String?) -> Void
    private let recordTypr: (TyprDictationEditResult) -> Void
    private var language: String?

    init(
        settings: TyprSettings = TyprSettings(),
        journalSettings: TypingJournalSettings = TypingJournalSettings(),
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        context: @escaping () -> DictationEditTracker.Context,
        returnKeyIsSend: @escaping () -> Bool,
        record: @escaping (_ result: DictationEditResult, _ language: String?) -> Void,
        recordTypr: @escaping (TyprDictationEditResult) -> Void
    ) {
        self.settings = settings
        self.journalSettings = journalSettings
        self.now = now
        self.context = context
        self.returnKeyIsSend = returnKeyIsSend
        self.record = record
        self.recordTypr = recordTypr
        hexEdits = DictationEditTracker(now: now)
        typrEdits = TyprDictationEditTracker(now: now)
        connectTrackers()
    }

    var isTracking: Bool { hexEdits.isTracking || typrEdits.isTracking }

    /// Call right before `inserted` goes in. Returns whether Typr keyboard's own tracker follows it.
    func willInsert(_ inserted: String, translated: Bool, fieldAllowsLearning: Bool, onTyprKeyboard: Bool) -> Bool {
        let now = context()
        let allowed = !translated && fieldAllowsLearning && journalSettings.isEnabled
        guard settings[experiment: .typrDictationEditLearning] else {
            typrEdits.finish(typrContext(now))
            if allowed, !onTyprKeyboard {
                hexEdits.willInsert(heard: nil, inserted: inserted, context: now)
                language = settings.dictationLanguage.formattingIdentifier
            } else {
                hexEdits.finish(now)
            }
            return false
        }
        hexEdits.finish(now)
        let typrLearns = allowed && settings[experiment: .learnFromEdits]
        if typrLearns, !onTyprKeyboard {
            typrEdits.willInsert(inserted, context: typrContext(now))
        } else {
            typrEdits.finish(typrContext(now))
        }
        return typrLearns && onTyprKeyboard
    }

    func attach(to keyboard: DictationEditHooks) {
        keyboard.onTextEdit = { [weak self] in self?.observe(fromKeys: true) }
        keyboard.onUndoDictation = { [weak self] in self?.didUndoDictation() }
        keyboard.onReturnKey = { [weak self] in self?.returnKeyWillInsert() }
    }

    /// Undo dictation ends the dictation's tracking without reporting it, so nothing typed
    /// in its place afterwards is learned as a fix of it.
    func didUndoDictation() {
        hexEdits = DictationEditTracker(now: now)
        typrEdits = TyprDictationEditTracker(now: now)
        connectTrackers()
    }

    func observe(fromKeys: Bool) {
        guard isTracking else { return }
        let now = context()
        if hexEdits.isTracking { hexEdits.observe(now, fromKeys: fromKeys) }
        if typrEdits.isTracking { typrEdits.observe(typrContext(now), fromKeys: fromKeys) }
    }

    /// A return key labelled Send ends the dictation's edit window: what is there is sent.
    func returnKeyWillInsert() {
        guard isTracking, returnKeyIsSend() else { return }
        finish()
    }

    func tick() {
        if hexEdits.isTracking { hexEdits.tick(context) }
        if typrEdits.isTracking { typrEdits.tick { [context] in Self.typrContext(context()) } }
    }

    func finish() {
        guard isTracking else { return }
        let now = context()
        hexEdits.finish(now)
        typrEdits.finish(typrContext(now))
    }

    func fieldMayHaveChanged() {
        hexEdits.finish(nil)
        typrEdits.finish(nil)
    }

    private func connectTrackers() {
        hexEdits.onResult = { [unowned self] result in record(result, language) }
        typrEdits.onResult = { [unowned self] result in recordTypr(result) }
    }

    private func typrContext(_ context: DictationEditTracker.Context) -> TyprDictationEditTracker.Context {
        Self.typrContext(context)
    }

    private static func typrContext(_ context: DictationEditTracker.Context) -> TyprDictationEditTracker.Context {
        TyprDictationEditTracker.Context(before: context.before, after: context.after, hasText: context.hasText)
    }
}
