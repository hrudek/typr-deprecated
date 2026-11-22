import XCTest
@testable import Typr

/// Hex's learning (Learn how I type, learned words, Adaptive touch) and Typr's keep separate
/// keys and files: neither reads, rewrites or deletes the other's records.
@MainActor
final class HexLearningStorageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "HexLearningStorageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hex-learning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private var storedKeys: Set<String> {
        Set(defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? [])
    }

    func testHexKeepsItsOwnKeysAndFiles() throws {
        let journal = TypingJournalSettings(defaults: defaults)
        journal.isEnabled = true
        journal.learnsPerLanguage = true
        journal.disabledDictationFixes = ["cloud → claude"]
        journal.erasedAt = 1
        let touch = AdaptiveTouchSettings(defaults: defaults)
        touch.isEnabled = true
        touch.summary = (12, false)
        touch.requestReset(now: 2)
        touch.summary = (12, false)
        let words = LearnedWordsStore(defaults: defaults)
        words.learn("teh")
        words.scoped(to: "de").learn("ok")

        XCTAssertEqual(storedKeys, [
            "experiments.typingJournal", "experiments.learnPerLanguage",
            "typingJournal.disabledDictationFixes", "typingJournal.erasedAt",
            "experiments.adaptiveTouch", "adaptiveTouch.resetAt", "adaptiveTouch.summary.taps",
            "adaptiveTouch.summary.active", "hex.keyboard.learnedWords", "hex.keyboard.learnedWords.de",
        ])
        XCTAssertEqual(TypingJournal.fileName, "typing-journal.json")
        XCTAssertEqual(AdaptiveTouch.fileName, "adaptive-touch.bin")
        let touchFile = try XCTUnwrap(AdaptiveTouch.defaultURL)
        XCTAssertEqual(touchFile.deletingLastPathComponent().lastPathComponent, "AdaptiveTouch")
        XCTAssertFalse(touchFile.path.contains(KeyboardBridge.appGroup), "touch averages stay in the keyboard's own container")
    }

    /// Typr's learning session deletes `keyboard.learnedWords`, an obsolete Typr record, on every
    /// start; Hex's learned words are elsewhere and survive it.
    func testTyprsLearningSessionLeavesHexsLearnedWordsAlone() {
        LearnedWordsStore(defaults: defaults).learn("teh")
        defaults.set(Data("obsolete".utf8), forKey: KeyboardLearningSession.legacyLearnedWordsKey)

        _ = KeyboardLearningSession(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: KeyboardLearningSession.legacyLearnedWordsKey))
        XCTAssertEqual(LearnedWordsStore(defaults: defaults).words, ["teh"])
    }

    func testHexNeverReadsTyprsObsoleteLearnedWords() throws {
        // In the very format Hex's list uses, so only the key keeps them apart.
        defaults.set(try JSONEncoder().encode(["teh"]), forKey: KeyboardLearningSession.legacyLearnedWordsKey)
        XCTAssertTrue(LearnedWordsStore(defaults: defaults).words.isEmpty)
    }

    /// Delete what Hex learned and Reset touch learning erase Hex's records only.
    func testHexsDeleteAndResetLeaveTyprsLearningAlone() throws {
        TyprSettings(defaults: defaults).personalLearning = false
        defaults.set(3, forKey: KeyboardLearningStore.learningResetKey)
        let typrFile = directory.appendingPathComponent("learning-v1.json")
        try Data("{}".utf8).write(to: typrFile)
        let journal = TypingJournal(directory: directory, settings: TypingJournalSettings(defaults: defaults))
        journal.record(.retyped, typed: "teh", final: "the")
        LearnedWordsStore(defaults: defaults).learn("teh")

        TypingJournal.delete(in: directory, settings: TypingJournalSettings(defaults: defaults))
        AdaptiveTouchSettings(defaults: defaults).requestReset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(TypingJournal.fileName).path))
        XCTAssertNil(defaults.object(forKey: LearnedWordsStore.defaultsKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: typrFile.path))
        XCTAssertFalse(TyprSettings(defaults: defaults).personalLearning)
        XCTAssertEqual(defaults.integer(forKey: KeyboardLearningStore.learningResetKey), 3)
    }
}
