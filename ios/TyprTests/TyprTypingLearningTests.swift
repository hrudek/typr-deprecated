import Darwin
import XCTest
@testable import Typr

@MainActor
final class TyprTypingLearningTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "TyprTypingLearningTests-\(UUID().uuidString)"
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

    func testARebuildWithTyprTypingKeepsItsSession() {
        let learning = TyprTypingLearning { self.makeSession() }
        let first = learning.session(fullAccess: true)
        XCTAssertTrue(learning.session(fullAccess: true) === first)
        XCTAssertFalse(learning.session(fullAccess: false) === first, "a Full Access change starts a new session")
    }

    func testLearningSurvivesASwitchToTyprKeyboardAndBack() {
        let learning = TyprTypingLearning { self.makeSession() }
        let typing = learning.session(fullAccess: true)
        typing.keep("teh")
        learning.retire()

        let typrKeyboard = makeSession()
        XCTAssertTrue(typrKeyboard.protections.isKept("teh"), "Typr keyboard loads what Typr typing kept")
        typrKeyboard.keep("ina")
        typrKeyboard.flush()

        let back = learning.session(fullAccess: true)
        XCTAssertFalse(back === typing, "switching back loads a fresh session")
        XCTAssertTrue(back.protections.isKept("teh"))
        XCTAssertTrue(back.protections.isKept("ina"), "nothing Typr keyboard learned is overwritten")
    }

    func testARetiredSessionIsHeldUntilItsSaveSucceeds() {
        let learning = TyprTypingLearning { self.makeSession() }
        learning.session(fullAccess: true).keep("teh")
        let lock = open(directory.appendingPathComponent("learning.lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        learning.retire()
        flock(lock, LOCK_UN)
        close(lock)
        learning.flush()
        XCTAssertTrue(makeSession().protections.isKept("teh"))
    }
}
