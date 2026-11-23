import Foundation
import NaturalLanguage
@preconcurrency import Translation

/// Typr translation policy: Translate what I say between German and English only, on iOS 26,
/// with `deadline` over both attempts (Hex #2015, #2176 as Typr adapted them before Hex's
/// multilingual translation, `DictationTranslator`).
struct TyprDictationTranslator {
    var engine: TranslationEngine
    var sleep: @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Covers both attempts; a dictation never waits longer for its translation.
    var deadline: Duration = .seconds(5)

    /// iOS 26's sessions on installed languages, usable without a SwiftUI host; nil before.
    static var system: TyprDictationTranslator? {
        guard #available(iOS 26.0, *) else { return nil }
        return TyprDictationTranslator(engine: .apple)
    }

    /// German for a German target (BCP 47), English for any other.
    static func target(for identifier: String) -> DictationLanguage {
        Locale(identifier: identifier).language.languageCode == .german ? .german : .english
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
            settle.resume(.failed(TranslationFailure(.failed, source: from, target: to)))
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
        let failed = TranslationOutcome.failed(TranslationFailure(.failed, source: source, target: target))
        let notDownloaded = TranslationOutcome.failed(TranslationFailure(.notDownloaded, source: source, target: target))
        switch await engine.status(source, target) {
        case .installed: break
        case .supported: return notDownloaded
        default: return failed
        }
        for _ in 0..<2 {
            do {
                let translated = try await engine.translate(text, source, target).trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty { return .translated(translated) }
            } catch {
                if Task.isCancelled { return failed }
                if #available(iOS 26.0, *), TranslationError.notInstalled ~= error { return notDownloaded }
            }
        }
        return failed
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
