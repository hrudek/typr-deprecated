import Darwin
import XCTest
@testable import Typr

@MainActor
final class SharedKeyboardLearningTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "SharedKeyboardLearningTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession() -> KeyboardLearningSession {
        KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
                                defaults: defaults, debounce: .seconds(3600))
    }

    private func holdLock() -> Int32 {
        let lock = open(directory.appendingPathComponent("learning.lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        return lock
    }

    private func release(_ lock: Int32) {
        flock(lock, LOCK_UN)
        close(lock)
    }

    func testBothKeyboardsShareOneSessionUntilFullAccessChanges() {
        let shared = SharedKeyboardLearning { self.makeSession() }
        let typing = shared.session(fullAccess: true)
        XCTAssertTrue(shared.session(fullAccess: true) === typing, "Typr keyboard and a rebuild take the same session")
        XCTAssertFalse(shared.session(fullAccess: false) === typing, "a Full Access change starts a new session")
    }

    func testAContendedHandoverInBothDirectionsLosesNothing() {
        let shared = SharedKeyboardLearning { self.makeSession() }
        let typing = shared.session(fullAccess: true)
        typing.keep("teh")

        var lock = holdLock()
        shared.flush()
        let typrKeyboard = shared.session(fullAccess: true)
        XCTAssertTrue(typrKeyboard === typing, "the handover passes the session, never a second writer")
        typrKeyboard.keep("ina")
        release(lock)

        lock = holdLock()
        shared.flush()
        let typingAgain = shared.session(fullAccess: true)
        XCTAssertTrue(typingAgain === typing)
        typingAgain.keep("abc")
        release(lock)
        shared.flush()

        let disk = makeSession()
        for word in ["teh", "ina", "abc"] {
            XCTAssertTrue(disk.protections.isKept(word), word)
        }
    }
}
