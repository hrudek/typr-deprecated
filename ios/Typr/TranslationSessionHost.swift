import SwiftUI
@preconcurrency import Translation

/// Translate what I say before iOS 26. There a `TranslationSession` comes only from SwiftUI's
/// `translationTask` (iOS 26 makes one directly, `TranslationSession(installedSource:target:)`),
/// so Typr's root view hosts one (`TranslationSessionHostView`) and each translation asks it for
/// a session for its pair. iOS may not run the task, or the translation, while Typr is in the
/// background (a dictation finished from the keyboard): one that isn't done within `wait` goes
/// in as spoken, and Settings says why (`TranslationFailure.Reason.needsTyprOpen`). A session
/// translates only texts of its own pair; texts of another wait for a session of theirs.
@MainActor
@Observable
final class TranslationSessionHost {
    static let shared = TranslationSessionHost()

    static let wait: Duration = .seconds(10)

    private(set) var configuration: TranslationSession.Configuration?
    private struct Request {
        let id: UUID
        let text: String
        let source: Locale.Language
        let target: Locale.Language
        var pair: Pair { Pair(source, target) }
    }

    /// Minimal identifiers, as `de` and `de-DE` are one source.
    struct Pair: Equatable {
        let source: String?
        let target: String?

        init(_ source: Locale.Language?, _ target: Locale.Language?) {
            self.source = source?.minimalIdentifier
            self.target = target?.minimalIdentifier
        }
    }

    /// Texts waiting for a session, in order.
    @ObservationIgnored private var queue: [Request] = []
    /// Every translation not answered yet, queued or in a session.
    @ObservationIgnored private var waiting: [UUID: CheckedContinuation<String, Error>] = [:]

    var engine: TranslationEngine {
        TranslationEngine(
            status: { source, target in await LanguageAvailability().status(from: source, to: target) },
            translate: { text, source, target in
                try await TranslationSessionHost.shared.translate(text, from: source, to: target)
            }
        )
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            queue.append(Request(id: id, text: text, source: source, target: target))
            requestSession(source, target)
            Task { @MainActor in
                try? await Task.sleep(for: Self.wait)
                self.answer(id, with: .failure(TranslationEngine.NoSession()))
            }
        }
    }

    /// The view's task: translates what waits for its session's pair, then returns, as a session
    /// can't be used after its task ends.
    func serve(_ session: TranslationSession) async {
        await serve(Pair(session.sourceLanguage, session.targetLanguage)) { try await session.translate($0).targetText }
    }

    /// A replaced task (another pair asked meanwhile) stops after the text in hand; the session
    /// for the pair still waiting is asked for when this one is done.
    func serve(_ pair: Pair, translate: (String) async throws -> String) async {
        while !Task.isCancelled, let index = queue.firstIndex(where: { $0.pair == pair }) {
            let request = queue.remove(at: index)
            guard waiting[request.id] != nil else { continue }
            do {
                answer(request.id, with: .success(try await translate(request.text)))
            } catch {
                answer(request.id, with: .failure(error))
            }
        }
        queue.removeAll { waiting[$0.id] == nil }
        guard !Task.isCancelled, let next = queue.first else { return }
        requestSession(next.source, next.target)
    }

    /// Same pair: a new run of the task, with a new session.
    private func requestSession(_ source: Locale.Language, _ target: Locale.Language) {
        if let configuration, Pair(configuration.source, configuration.target) == Pair(source, target) {
            self.configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func answer(_ id: UUID, with result: Result<String, Error>) {
        waiting.removeValue(forKey: id)?.resume(with: result)
    }
}

/// Hosts `TranslationSessionHost`'s session in Typr's window, before iOS 26.
struct TranslationSessionHostView: View {
    private let host = TranslationSessionHost.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(host.configuration) { session in
                await host.serve(session)
            }
            .onAppear { TranslationEngine.hosted = host.engine }
    }
}
