import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardDictationLearningTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var journal: TypingJournal!
    private var now: TimeInterval = 1_000

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-learning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "KeyboardDictationLearningTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        journal = TypingJournal(directory: directory, settings: TypingJournalSettings(defaults: defaults))
        TyprSettings(defaults: defaults).dictationLanguage = .german
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var settings: TyprSettings { TyprSettings(defaults: defaults) }
    private var store: DictationLearningStore { DictationLearningStore(defaults: defaults) }

    private var journalFixes: [DictationCorrection] {
        TypingJournal.storedDictationCorrections(settings: TypingJournalSettings(defaults: defaults), directory: directory)
    }

    private var journalOutcomes: [DictationOutcome] {
        TypingJournal.load(from: directory.appendingPathComponent(TypingJournal.fileName)).dictationOutcomes.map(\.outcome)
    }

    private func makeSession(_ field: HexFixtureTextTarget = HexFixtureTextTarget(text: "Hallo Jörg."),
                             onTyprKeyboard: Bool = false) -> Session {
        let keyboard = Keys(field: field)
        let store = store
        let learning = KeyboardDictationLearning(
            settings: settings,
            journalSettings: TypingJournalSettings(defaults: defaults),
            now: { [unowned self] in self.now },
            context: { DictationEditTracker.Context(
                before: field.documentContextBeforeInput, after: field.documentContextAfterInput, hasText: field.hasText
            ) },
            returnKeyIsSend: { field.returnKeyType == .send },
            record: { [unowned self] result, language in self.journal.recordDictation(result, language: language) },
            recordTypr: { store.record($0) }
        )
        learning.attach(to: keyboard)
        return Session(field: field, keys: keyboard, learning: learning, onTyprKeyboard: onTyprKeyboard)
    }

    private func turnOnTyprLearning() {
        settings[experiment: .typrDictationEditLearning] = true
        settings[experiment: .learnFromEdits] = true
    }

    private func editWalToWahlTwice(onTyprKeyboard: Bool = false) -> [Bool] {
        (0..<2).map { _ in
            let session = makeSession(onTyprKeyboard: onTyprKeyboard)
            let typrKeyboardLearns = session.dictate(" Ich habe die Wal getroffen.")
            session.replaceWal()
            session.learning.finish()
            return typrKeyboardLearns
        }
    }

    func testHexKeyboardLearnsIntoTheJournalByDefault() {
        XCTAssertEqual(editWalToWahlTwice(), [false, false])
        XCTAssertEqual(journalFixes, [DictationCorrection(heard: "wal", meant: "Wahl")])
        XCTAssertTrue(store.records.isEmpty)
    }

    func testHexKeyboardLearnsIntoTyprsStoreWithTyprDictationEditLearning() {
        turnOnTyprLearning()
        XCTAssertEqual(editWalToWahlTwice(), [false, false])
        XCTAssertEqual(store.learnedFixes.map(\.meant), ["Wahl"])
        XCTAssertTrue(journalOutcomes.isEmpty)
    }

    func testTyprKeyboardLearnsNothingByDefault() {
        XCTAssertEqual(editWalToWahlTwice(onTyprKeyboard: true), [false, false])
        XCTAssertTrue(journalOutcomes.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testTyprKeyboardFollowsItsOwnDictationsWithTyprDictationEditLearning() {
        turnOnTyprLearning()
        XCTAssertEqual(editWalToWahlTwice(onTyprKeyboard: true), [true, true])
        XCTAssertTrue(journalOutcomes.isEmpty)
        XCTAssertTrue(store.records.isEmpty, "Typr keyboard's tracker records, not this one")
    }

    func testTyprDictationEditLearningHasHexsGates() {
        turnOnTyprLearning()
        for onTyprKeyboard in [false, true] {
            let learning = makeSession(onTyprKeyboard: onTyprKeyboard).learning
            func follows(translated: Bool = false, allowed: Bool = true) -> Bool {
                let typrKeyboardLearns = learning.willInsert(" Hallo.", translated: translated,
                                                             fieldAllowsLearning: allowed, onTyprKeyboard: onTyprKeyboard)
                return typrKeyboardLearns || learning.typrEdits.isTracking
            }
            XCTAssertTrue(follows())
            XCTAssertFalse(follows(translated: true))
            XCTAssertFalse(follows(allowed: false))
            TypingJournalSettings(defaults: defaults).isEnabled = false
            XCTAssertFalse(follows())
            TypingJournalSettings(defaults: defaults).isEnabled = true
            settings[experiment: .learnFromEdits] = false
            XCTAssertFalse(follows())
            settings[experiment: .learnFromEdits] = true
            XCTAssertFalse(learning.hexEdits.isTracking)
        }
    }

    func testHexLearningHasItsGates() {
        let learning = makeSession().learning
        _ = learning.willInsert(" Hallo.", translated: true, fieldAllowsLearning: true, onTyprKeyboard: false)
        XCTAssertFalse(learning.isTracking)
        _ = learning.willInsert(" Hallo.", translated: false, fieldAllowsLearning: false, onTyprKeyboard: false)
        XCTAssertFalse(learning.isTracking)
        TypingJournalSettings(defaults: defaults).isEnabled = false
        _ = learning.willInsert(" Hallo.", translated: false, fieldAllowsLearning: true, onTyprKeyboard: false)
        XCTAssertFalse(learning.isTracking)
    }

    func testSendSettlesBeforeTheLineBreakSoAReplyTypedAfterIsNeverLearned() {
        for _ in 0..<2 {
            let field = ClearingOnNewlineField()
            field.returnKeyType = .send
            let session = makeSession(field)
            _ = session.dictate("Ich habe die Wal getroffen.")
            session.keys.pressReturn()
            XCTAssertEqual(field.text, "", "the host sent it")
            XCTAssertFalse(session.learning.isTracking)
            session.keys.type("Ich habe die Wahl getroffen.")
            now += 61
            session.learning.tick()
            session.learning.finish()
        }
        XCTAssertEqual(journalOutcomes, [.kept, .kept])
        XCTAssertTrue(journalFixes.isEmpty)
    }

    func testNothingTypedAfterUndoDictationIsLearned() {
        for typrLearning in [false, true] {
            if typrLearning { turnOnTyprLearning() }
            for _ in 0..<2 {
                let field = HexFixtureTextTarget()
                field.returnKeyType = .send
                let session = makeSession(field)
                _ = session.dictate("Ich habe die Wal getroffen.")
                session.keys.undoDictation("Ich habe die Wal getroffen.")
                XCTAssertEqual(field.text, "")
                XCTAssertFalse(session.learning.isTracking)
                session.keys.type("Ich habe die Wahl getroffen.")
                session.keys.pressReturn()
                now += 61
                session.learning.tick()
                session.learning.finish()
            }
            XCTAssertTrue(journalOutcomes.isEmpty, "\(typrLearning)")
            XCTAssertTrue(store.records.isEmpty, "\(typrLearning)")
        }
    }
}

@MainActor
private final class Session {
    let field: HexFixtureTextTarget
    let keys: Keys
    let learning: KeyboardDictationLearning
    let onTyprKeyboard: Bool

    init(field: HexFixtureTextTarget, keys: Keys, learning: KeyboardDictationLearning, onTyprKeyboard: Bool) {
        self.field = field
        self.keys = keys
        self.learning = learning
        self.onTyprKeyboard = onTyprKeyboard
    }

    func dictate(_ text: String) -> Bool {
        let typrLearns = learning.willInsert(text, translated: false, fieldAllowsLearning: true, onTyprKeyboard: onTyprKeyboard)
        field.insertText(text)
        learning.observe(fromKeys: false)
        return typrLearns
    }

    func replaceWal() {
        field.adjustTextPosition(byCharacterOffset: -" getroffen.".count)
        for _ in 0..<3 { keys.delete() }
        keys.type("Wahl")
        field.adjustTextPosition(byCharacterOffset: " getroffen.".count)
        learning.observe(fromKeys: false)
    }
}

@MainActor
private final class Keys: DictationEditHooks {
    var onTextEdit: (() -> Void)?
    var onUndoDictation: (() -> Void)?
    var onReturnKey: (() -> Void)?
    let field: HexFixtureTextTarget

    init(field: HexFixtureTextTarget) { self.field = field }

    func type(_ text: String) {
        field.insertText(text)
        onTextEdit?()
    }

    func delete() {
        field.deleteBackward()
        onTextEdit?()
    }

    func pressReturn() {
        onReturnKey?()
        type("\n")
    }

    func undoDictation(_ text: String) {
        for _ in text { field.deleteBackward() }
        onUndoDictation?()
        onTextEdit?()
    }
}

@MainActor
private final class ClearingOnNewlineField: HexFixtureTextTarget {
    override func insertText(_ inserted: String) {
        guard inserted == "\n" else { return super.insertText(inserted) }
        adjustTextPosition(byCharacterOffset: text.count)
        while hasText { deleteBackward() }
    }
}
