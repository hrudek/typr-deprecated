import Foundation
import NaturalLanguage
@preconcurrency import Translation

/// Experiment (Translate what I say): speak one language, insert another. Translation
/// runs on the iPhone with Apple's Translation framework once the language pack is
/// downloaded in Typr. When it can't, the transcript goes in as spoken and the keyboard says
/// why (`TranslationFailure`).
struct DictationTranslationSettings {
    private enum Key {
        static let enabled = "experiments.translateDictation"
        static let target = "experiments.translateDictation.target"
        static let lastFailure = "experiments.translateDictation.lastFailure"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// Settings' Translate what I say. Only it changes it; nothing turns it off by itself.
    var isEnabled: Bool {
        get { defaults?.bool(forKey: Key.enabled) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.enabled) }
    }

    /// BCP 47 language code, `de` or `en`. English by default and for any other stored target:
    /// Typr offers German and English (Hex's default is Japanese).
    var targetLanguage: String {
        get {
            guard let stored = defaults?.string(forKey: Key.target),
                  Locale(identifier: stored).language.languageCode == .german else { return "en" }
            return stored
        }
        nonmutating set { defaults?.set(newValue, forKey: Key.target) }
    }

    /// Why the last dictation went in as spoken, until one translates: Settings shows it and
    /// offers the fix.
    var lastFailure: TranslationFailure? {
        get {
            defaults?.data(forKey: Key.lastFailure).flatMap { try? JSONDecoder().decode(TranslationFailure.self, from: $0) }
        }
        nonmutating set {
            defaults?.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.lastFailure)
        }
    }
}

/// Why a dictation went in as spoken while Translate what I say was on. The keyboard says so
/// as it pastes, with the fix, and Settings keeps it (`DictationTranslationSettings.lastFailure`).
nonisolated struct TranslationFailure: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        /// Apple's languages for the pair aren't on the iPhone: never downloaded, removed in
        /// iOS Settings, or still downloading.
        case notDownloaded
        /// Apple can't translate from the one into the other.
        case unsupported
        /// The translation failed twice, each time in a new session.
        case failed
        /// Before iOS 26 Apple's translation runs in Typr's own window, which iOS didn't run in
        /// time (`TranslationSessionHost`): Typr was in the background.
        case needsTyprOpen
    }

    let reason: Reason
    /// Minimal identifiers (`zh`, `en`).
    let source: String
    let target: String
    /// Apple's error, for diagnosis; never the dictated text.
    var detail: String?

    init(_ reason: Reason, source: Locale.Language, target: Locale.Language, detail: String? = nil) {
        self.reason = reason
        self.source = source.minimalIdentifier
        self.target = target.minimalIdentifier
        self.detail = detail
    }

    /// "Spanish", "Chinese, Traditional"; Norwegian without "Bokmål".
    static func name(of identifier: String) -> String {
        if ["nb", "nn", "no"].contains(code(of: identifier)) {
            return Locale.typrInterface.localizedString(forLanguageCode: "no") ?? "Norwegian"
        }
        return Locale.typrInterface.localizedString(forIdentifier: identifier) ?? identifier
    }

    private static func code(of identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
    }

    /// What the keyboard says after pasting as spoken.
    static var note: String { String(localized: "Couldn't translate, pasted as spoken") }

    /// The language Settings downloads: the one that isn't English, which Apple pairs with
    /// most languages.
    var language: String {
        Locale.Language(identifier: target).languageCode == .english ? source : target
    }

    /// The fix, short enough for the keyboard's second line: "Download Chinese in Settings".
    var fix: String {
        let name = Self.name(of: language)
        return switch reason {
        case .notDownloaded: String(localized: "Download \(name) in Settings")
        case .unsupported: String(localized: "Pick another language in Settings")
        case .failed: String(localized: "Download \(name) again in Settings")
        case .needsTyprOpen: String(localized: "iOS 18 translates only with Typr open")
        }
    }
}

/// What a dictation's translation came to.
nonisolated enum TranslationOutcome: Equatable, Sendable {
    /// Off, nothing to translate, or already in the target language.
    case skipped
    case translated(String)
    /// Pasted as spoken, and why.
    case failed(TranslationFailure)

    var text: String? {
        if case .translated(let text) = self { text } else { nil }
    }

    var failure: TranslationFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }
}

/// Apple's Translation framework behind a seam tests stand in for: whether a pair's languages
/// are on the iPhone, and one translation.
nonisolated struct TranslationEngine: Sendable {
    var status: @MainActor @Sendable (Locale.Language, Locale.Language) async -> LanguageAvailability.Status
    var translate: @MainActor @Sendable (String, Locale.Language, Locale.Language) async throws -> String

    /// Before iOS 26, the session Typr's window hosts (`TranslationSessionHost`), while it does;
    /// nil in the keyboard, which doesn't translate before iOS 26.
    @MainActor static var hosted: TranslationEngine?

    /// Thrown by `hosted` when no session came in time.
    struct NoSession: Error {}

    @available(iOS 26.0, *)
    static var apple: TranslationEngine {
        TranslationEngine(
            status: { source, target in await LanguageAvailability().status(from: source, to: target) },
            translate: { text, source, target in
                // A new session for every translation, never one kept: a session whose
                // translation service went away (the keyboard or Typr suspended, the service
                // restarted) can't be used again.
                try await TranslationSession(installedSource: source, target: target).translate(text).targetText
            }
        )
    }
}

enum DictationTranslator {
    /// The translation into `target` (BCP 47), or why it went in as spoken. Skipped when the
    /// text is empty or already in the target language, or before iOS 26 without Typr's window
    /// (`TranslationEngine.hosted`: the keyboard, a test). `source` is the
    /// dictation language; without one the text's language is guessed. A failed translation
    /// is tried once more in a new session; a missing language pack isn't retried. The last
    /// failure is kept for Settings until a translation works; a cancelled dictation keeps none.
    @MainActor
    static func translate(
        _ text: String,
        source: Locale.Language? = nil,
        target: String,
        settings: DictationTranslationSettings = DictationTranslationSettings(),
        engine: TranslationEngine? = nil
    ) async -> TranslationOutcome {
        let engine: TranslationEngine? = if #available(iOS 26.0, *) { engine ?? .apple } else { engine ?? .hosted }
        guard let engine else { return .skipped }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let source = source ?? detectedLanguage(of: trimmed) else { return .skipped }
        let target = Locale.Language(identifier: target)
        guard source.languageCode != target.languageCode else { return .skipped }
        let outcome = await attempt(trimmed, from: source, to: target, engine: engine)
        guard !Task.isCancelled else { return outcome }
        switch outcome {
        case .translated: if settings.lastFailure != nil { settings.lastFailure = nil }
        case .failed(let failure): settings.lastFailure = failure
        case .skipped: break
        }
        return outcome
    }

    @MainActor
    private static func attempt(
        _ text: String,
        from source: Locale.Language,
        to target: Locale.Language,
        engine: TranslationEngine
    ) async -> TranslationOutcome {
        switch await engine.status(source, target) {
        case .unsupported: return .failed(TranslationFailure(.unsupported, source: source, target: target))
        case .supported: return .failed(TranslationFailure(.notDownloaded, source: source, target: target))
        default: break
        }
        var failure = TranslationFailure(.failed, source: source, target: target)
        for _ in 0..<2 {
            do {
                let translated = try await engine.translate(text, source, target)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty { return .translated(translated) }
            } catch {
                failure = TranslationFailure(reason(for: error), source: source, target: target, detail: describe(error))
                // Another session can't download a language or pair two Apple can't.
                if failure.reason != .failed || Task.isCancelled { break }
            }
        }
        return .failed(failure)
    }

    static func reason(for error: any Error) -> TranslationFailure.Reason {
        if error is TranslationEngine.NoSession { return .needsTyprOpen }
        if #available(iOS 26.0, *), TranslationError.notInstalled ~= error { return .notDownloaded }
        if TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error
            || TranslationError.unsupportedLanguagePairing ~= error {
            return .unsupported
        }
        return .failed
    }

    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        let reason = error.localizedFailureReason.map { ": \($0)" } ?? ""
        return "\(error.domain) \(error.code)\(reason)"
    }

    static func detectedLanguage(of text: String) -> Locale.Language? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}

/// Translate what I say for one dictation, read when it starts: a change of the switch or
/// the target applies to the next dictation.
nonisolated struct DictationTranslationPlan: Equatable, Sendable {
    /// BCP 47; German or English under the Typr translation policy.
    let target: String
    /// Typr translation policy: Typr's German and English translator (`TyprDictationTranslator`).
    let typrPolicy: Bool

    init?(settings: DictationTranslationSettings, typrPolicy: Bool) {
        guard settings.isEnabled else { return nil }
        self.typrPolicy = typrPolicy
        target = typrPolicy ? TyprDictationTranslator.target(for: settings.targetLanguage).rawValue : settings.targetLanguage
    }

    /// `source` is the dictation's language; Automatic reads it from the text. `engine` nil is
    /// Apple's (`DictationTranslator`, `TyprDictationTranslator.system`).
    @MainActor
    func translate(
        _ text: String,
        source: DictationLanguage,
        settings: DictationTranslationSettings,
        engine: TranslationEngine? = nil
    ) async -> TranslationOutcome {
        guard typrPolicy else {
            let language = source.whisperLanguageCode.map { Locale.Language(identifier: $0) }
            return await DictationTranslator.translate(text, source: language, target: target, settings: settings, engine: engine)
        }
        guard let translator = engine.map({ TyprDictationTranslator(engine: $0) }) ?? .system,
              let outcome = await translator.translate(text, from: source, to: TyprDictationTranslator.target(for: target))
        else { return .skipped }
        switch outcome {
        case .translated: if settings.lastFailure != nil { settings.lastFailure = nil }
        case .failed(let failure): settings.lastFailure = failure
        case .skipped: break
        }
        return outcome
    }
}
