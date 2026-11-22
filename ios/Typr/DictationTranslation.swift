import Foundation
import NaturalLanguage
@preconcurrency import Translation

/// What Translate what I say made of a dictation.
nonisolated enum TranslationOutcome: Equatable, Sendable {
    /// Nothing to translate, or already in the target language.
    case skipped
    case translated(String)
    /// Goes in as spoken.
    case failed(TranslationFailure)
}

/// Apple's Translation framework behind a seam tests stand in for. Adapted from Hex
/// (anomalyco/hex #2015, #2176, `DictationTranslation.swift`).
struct DictationTranslator {
    var status: @MainActor @Sendable (Locale.Language, Locale.Language) async -> LanguageAvailability.Status
    var translate: @MainActor @Sendable (String, Locale.Language, Locale.Language) async throws -> String
    var sleep: @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Covers both attempts; a dictation never waits longer for its translation.
    var deadline: Duration = .seconds(5)

    /// iOS 26's sessions on installed languages, usable without a SwiftUI host; nil before.
    static var system: DictationTranslator? {
        guard #available(iOS 26.0, *) else { return nil }
        return DictationTranslator(
            status: { source, target in await LanguageAvailability().status(from: source, to: target) },
            translate: { text, source, target in
                // A session whose translation service went away (Typr suspended, the service
                // restarted) can't be used again, so every attempt gets a new one.
                try await TranslationSession(installedSource: source, target: target).translate(text).targetText
            }
        )
    }

    /// `source` is the captured dictation language; Automatic guesses German or English from
    /// the text. A failed translation is tried once more; a missing pack is not. nil when the
    /// calling task was cancelled.
    @MainActor
    func translate(_ text: String, from source: DictationLanguage, to target: DictationLanguage) async -> TranslationOutcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let source = source == .automatic ? Self.detectedLanguage(of: trimmed) : source,
              source != target else { return .skipped }
        let from = Locale.Language(identifier: source.rawValue)
        let to = Locale.Language(identifier: target.rawValue)
        let settle = Settle()
        let work = Task { @MainActor in settle.resume(await attempt(trimmed, from: from, to: to)) }
        let timer = Task { @MainActor in
            guard (try? await sleep(deadline)) != nil else { return }
            settle.resume(.failed(.failed))
        }
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { settle.wait($0) }
        } onCancel: {
            settle.resume(nil)
        }
        work.cancel()
        timer.cancel()
        return outcome
    }

    @MainActor
    private func attempt(_ text: String, from source: Locale.Language, to target: Locale.Language) async -> TranslationOutcome {
        switch await status(source, target) {
        case .installed: break
        case .supported: return .failed(.notDownloaded)
        default: return .failed(.failed)
        }
        for _ in 0..<2 {
            do {
                let translated = try await translate(text, source, target).trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty { return .translated(translated) }
            } catch {
                if Task.isCancelled { return .failed(.failed) }
                if #available(iOS 26.0, *), TranslationError.notInstalled ~= error { return .failed(.notDownloaded) }
            }
        }
        return .failed(.failed)
    }

    static func detectedLanguage(of text: String) -> DictationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        return switch recognizer.dominantLanguage {
        case .german?: .german
        case .english?: .english
        default: nil
        }
    }
}

/// The first of translation, deadline and cancellation wins.
private final class Settle: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TranslationOutcome?, Never>?
    private var result: TranslationOutcome??

    func wait(_ continuation: CheckedContinuation<TranslationOutcome?, Never>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(_ outcome: TranslationOutcome?) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = .some(outcome)
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: outcome)
    }
}
