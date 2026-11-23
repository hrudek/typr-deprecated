/// The one learning session Typr keyboard and Typr typing on Hex's keyboard both use, so a
/// switch between them hands over the same session and the process never has two writers.
/// A Full Access change starts a new session; the old one can no longer write by then: without
/// Full Access its next save turns it RAM-only, and before Full Access it had no store.
@MainActor
final class SharedKeyboardLearning {
    private let makeSession: () -> KeyboardLearningSession
    private var current: (session: KeyboardLearningSession, fullAccess: Bool)?

    init(makeSession: @escaping () -> KeyboardLearningSession) {
        self.makeSession = makeSession
    }

    func session(fullAccess: Bool) -> KeyboardLearningSession {
        if let current, current.fullAccess == fullAccess { return current.session }
        current?.session.flush()
        let session = makeSession()
        current = (session, fullAccess)
        return session
    }

    func flush() {
        current?.session.flush()
    }
}
