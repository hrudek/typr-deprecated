import Darwin
import XCTest
@testable import Typr

@MainActor
final class KeyboardLearningLockTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "KeyboardLearningLockTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func session() -> KeyboardLearningSession {
        KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
                                defaults: defaults, debounce: .seconds(3600))
    }

    func testABusyLockKeepsUnsavedLearningUntilASaveSucceeds() throws {
        let learning = session()
        XCTAssertTrue(learning.isPersistent)
        learning.keep("teh")

        let lock = open(directory.appendingPathComponent("learning.lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(lock, 0)
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        learning.flush()
        XCTAssertTrue(learning.isPersistent, "a held lock is not a storage failure")

        flock(lock, LOCK_UN)
        close(lock)
        learning.flush()
        XCTAssertTrue(session().protections.isKept("teh"), "the next save writes what was kept")
    }
}
