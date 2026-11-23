/// Typr typing's learning session on the Hex keyboard: kept while Typr typing stays mounted,
/// saved and let go when another keyboard takes over, so that keyboard loads what it learned.
/// A session whose save could not happen yet is held until a later save succeeds.
@MainActor
final class TyprTypingLearning {
    private let makeSession: () -> KeyboardLearningSession
    private var current: (session: KeyboardLearningSession, fullAccess: Bool)?
    private var unsaved: [KeyboardLearningSession] = []

    init(makeSession: @escaping () -> KeyboardLearningSession) {
        self.makeSession = makeSession
    }

    func session(fullAccess: Bool) -> KeyboardLearningSession {
        if let current, current.fullAccess == fullAccess { return current.session }
        retire()
        let session = makeSession()
        current = (session, fullAccess)
        return session
    }

    func retire() {
        guard let session = current?.session else { return }
        current = nil
        unsaved.append(session)
        flush()
    }

    func flush() {
        current?.session.flush()
        unsaved.forEach { $0.flush() }
        unsaved.removeAll { !$0.hasUnsavedChanges }
    }
}
