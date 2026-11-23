import XCTest
@testable import Typr

@MainActor
final class TyprDictationEditTrackerTests: XCTestCase {
    private struct Field {
        var text: String
        var cursor: Int

        var context: TyprDictationEditTracker.Context {
            TyprDictationEditTracker.Context(before: String(text.prefix(cursor)), after: String(text.dropFirst(cursor)),
                                             hasText: !text.isEmpty)
        }

        mutating func insert(_ inserted: String) {
            text.insert(contentsOf: inserted, at: text.index(text.startIndex, offsetBy: cursor))
            cursor += inserted.count
        }

        mutating func replace(_ old: String, with new: String) {
            let range = text.range(of: old)!
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            text.replaceSubrange(range, with: new)
            cursor = start + new.count
        }
    }

    private var time: TimeInterval = 1_000
    private var results: [TyprDictationEditResult] = []
    private var field = Field(text: "Hallo Jörg.", cursor: 11)

    private func makeTracker() -> TyprDictationEditTracker {
        let tracker = TyprDictationEditTracker(now: { [unowned self] in self.time })
        tracker.onResult = { [unowned self] in self.results.append($0) }
        return tracker
    }

    private func dictate(_ text: String, with tracker: TyprDictationEditTracker) {
        tracker.willInsert(text, context: field.context)
        field.insert(text)
        tracker.observe(field.context, fromKeys: false)
    }

    private func edit(_ old: String, to new: String, with tracker: TyprDictationEditTracker) {
        time += 5
        field.replace(old, with: new)
        tracker.observe(field.context, fromKeys: true)
    }

    func testKeptWhenSentAsInserted() throws {
        let tracker = makeTracker()
        dictate(" Ich habe die Wahl getroffen.", with: tracker)
        time += 61
        tracker.tick { field.context }
        XCTAssertEqual(results.map(\.outcome), [.kept])
        XCTAssertTrue(try XCTUnwrap(results.first).pairs.isEmpty)
    }

    func testEditedPairsAGermanWordWithTheSimilarWordYouTyped() throws {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen und bin zufrieden.", with: tracker)
        edit("Wal", to: "Wahl", with: tracker)
        tracker.finish(field.context)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.outcome, .edited)
        XCTAssertEqual(result.pairs, [TyprDictationEditPair(inserted: "Wal", meant: "Wahl", caseIsKnown: true)])
        XCTAssertTrue(result.keptWords.contains { $0.containsRun(["ich", "habe", "die"]) })
    }

    func testEditsAfterTheMinuteAreNotSeen() {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen und bin zufrieden.", with: tracker)
        time += 61
        tracker.tick { field.context }
        edit("Wal", to: "Wahl", with: tracker)
        tracker.finish(field.context)
        XCTAssertEqual(results.map(\.outcome), [.kept])
    }

    func testRewrittenWhenMostWordsChanged() throws {
        let tracker = makeTracker()
        dictate(" Wir treffen uns morgen.", with: tracker)
        edit(" Wir treffen uns morgen.", to: " Das passt mir leider gar nicht.", with: tracker)
        tracker.finish(field.context)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.outcome, .rewritten)
        XCTAssertTrue(result.pairs.isEmpty)
    }

    func testUndoneIsNeverPairedWithTheNextDictation() throws {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen.", with: tracker)
        field.replace(" Ich habe die Wal getroffen.", with: "")
        tracker.didUndo()
        tracker.observe(field.context, fromKeys: false)
        time += 3
        dictate(" Ich habe die Wahl getroffen.", with: tracker)
        tracker.finish(field.context)
        XCTAssertEqual(results.map(\.outcome), [.undone, .kept])
        XCTAssertTrue(results.allSatisfy { $0.pairs.isEmpty })
    }

    func testRetypingAnUndoneDictationTeachesNothing() {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen.", with: tracker)
        field.replace(" Ich habe die Wal getroffen.", with: "")
        tracker.didUndo()
        tracker.observe(field.context, fromKeys: false)
        field.insert(" Ich habe die Wahl getroffen.")
        tracker.observe(field.context, fromKeys: true)
        tracker.finish(field.context)
        XCTAssertEqual(results.map(\.outcome), [.undone])
        XCTAssertTrue(results.allSatisfy { $0.pairs.isEmpty })
    }

    func testDeletedWhenRemovedAndNotDictatedAgain() {
        let tracker = makeTracker()
        dictate(" Bis später.", with: tracker)
        field.replace(" Bis später.", with: "")
        tracker.observe(field.context, fromKeys: true)
        time += 21
        tracker.tick { field.context }
        XCTAssertEqual(results.map(\.outcome), [.deleted])
    }

    func testRedictatedPairsTheWordsThatCameOutDifferently() throws {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen.", with: tracker)
        field.replace(" Ich habe die Wal getroffen.", with: "")
        tracker.observe(field.context, fromKeys: true)
        time += 8
        dictate(" Ich habe die Wahl getroffen.", with: tracker)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.outcome, .redictated)
        XCTAssertEqual(result.pairs, [TyprDictationEditPair(inserted: "Wal", meant: "Wahl", caseIsKnown: true)])
    }

    func testDifferentWordsAreNoFix() throws {
        let tracker = makeTracker()
        dictate(" Ich habe die Wal getroffen und bin zufrieden.", with: tracker)
        edit("Wal", to: "Entscheidung", with: tracker)
        tracker.finish(field.context)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.outcome, .edited)
        XCTAssertTrue(result.pairs.isEmpty)
    }

    func testCapitalAtASentenceStartIsNotTakenAsTheSpelling() throws {
        let tracker = makeTracker()
        dictate(" Wal ist wichtig für uns alle.", with: tracker)
        edit("Wal", to: "Wahl", with: tracker)
        tracker.finish(field.context)
        XCTAssertEqual(try XCTUnwrap(results.first).pairs,
                       [TyprDictationEditPair(inserted: "Wal", meant: "wahl", caseIsKnown: false)])
    }
}

final class DictationLearningTests: XCTestCase {
    private func edited(_ inserted: String, _ meant: String, caseIsKnown: Bool = true,
                        kept: [[String]] = []) -> TyprDictationEditResult {
        TyprDictationEditResult(outcome: .edited, pairs: [TyprDictationEditPair(inserted: inserted, meant: meant, caseIsKnown: caseIsKnown)],
                            keptWords: kept)
    }

    private func store() -> DictationLearningStore {
        let suite = "dictation.learning.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return DictationLearningStore(defaults: defaults)
    }

    func testAFixIsLearnedOnlyOnceMadeTwice() {
        let store = store()
        store.record(edited("Wal", "Wahl"))
        XCTAssertTrue(store.corrections.isEmpty)
        store.record(edited("Wal", "Wahl"))
        XCTAssertEqual(store.corrections, [TyprDictationCorrection(heard: "wal", meant: "Wahl", caseIsKnown: true)])
    }

    func testNothingIsLearnedWhenTheSameWordsWereFixedTwoWays() {
        let store = store()
        for meant in ["Wahl", "Wahl", "weil"] { store.record(edited("Wal", meant)) }
        XCTAssertTrue(store.corrections.isEmpty)
        XCTAssertFalse(store.records.isEmpty)
    }

    func testKeepingTheWordsInAnEditedDictationContradictsTheFix() {
        let store = store()
        store.record(edited("Wal", "Wahl"))
        store.record(edited("Wal", "Wahl"))
        store.record(edited("Haus", "Hause", kept: [["der", "wal", "schwimmt"]]))
        XCTAssertTrue(store.corrections.isEmpty)
    }

    func testChangingAnAppliedFixBackContradictsIt() {
        let store = store()
        store.record(edited("Wal", "Wahl"))
        store.record(edited("Wal", "Wahl"))
        store.record(edited("Wahl", "Wal"))
        XCTAssertTrue(store.learnedFixes.allSatisfy { $0.heard != "wal" })
    }

    func testCapitalOnlyFixesAreLearned() {
        let store = store()
        for _ in 0..<2 {
            store.record(edited("typr", "Typr"))
            store.record(edited("haus", "Haus"))
        }
        XCTAssertEqual(Set(store.corrections.map(\.meant)), ["Typr", "Haus"])
    }

    func testLoweringALearnedCapitalContradictsIt() {
        let store = store()
        store.record(edited("typr", "Typr"))
        store.record(edited("typr", "Typr"))
        store.record(edited("Typr", "typr"))
        XCTAssertTrue(store.corrections.isEmpty)
    }

    func testUndoneAndKeptDictationsStoreNothing() {
        let store = store()
        store.record(TyprDictationEditResult(outcome: .undone))
        store.record(TyprDictationEditResult(outcome: .kept))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testDeleteForgetsOneFixAndDeleteAllForgetsEverything() throws {
        let store = store()
        for _ in 0..<2 {
            store.record(edited("Wal", "Wahl"))
            store.record(edited("Gitub", "GitHub"))
        }
        XCTAssertEqual(store.learnedFixes.count, 2)
        store.delete(try XCTUnwrap(store.learnedFixes.first { $0.heard == "wal" }))
        XCTAssertEqual(store.learnedFixes.map(\.meant), ["GitHub"])
        store.deleteAll()
        XCTAssertTrue(store.records.isEmpty)
    }

    func testAppliedFixesFollowGermanCase() {
        let weil = TyprDictationCorrection(heard: "wal", meant: "weil", caseIsKnown: true)
        XCTAssertEqual(TyprDictationCorrections.apply([weil], to: "Ich komme nicht, Wal es regnet."),
                       "Ich komme nicht, weil es regnet.")
        XCTAssertEqual(TyprDictationCorrections.apply([weil], to: "Wal es regnet, komme ich nicht."),
                       "Weil es regnet, komme ich nicht.")
        let wahl = TyprDictationCorrection(heard: "wal", meant: "wahl", caseIsKnown: false)
        XCTAssertEqual(TyprDictationCorrections.apply([wahl], to: "Die Wal ist frei."), "Die Wahl ist frei.")
        XCTAssertEqual(TyprDictationCorrections.apply([wahl], to: "Der Blauwal und der Wal-Fang."),
                       "Der Blauwal und der Wal-Fang.")
    }

    func testLearnedFixGoesIntoTheNextDictationsSpelling() {
        let store = store()
        store.record(edited("Wal", "Wahl"))
        store.record(edited("Wal", "Wahl"))
        let vocabulary = DictationVocabulary(userTerms: [], learnedFixes: store.corrections)
        XCTAssertEqual(vocabulary.beforeCleanup("Ich habe die Wal getroffen").text, "Ich habe die Wahl getroffen")
        XCTAssertEqual(DictationVocabulary(userTerms: []).beforeCleanup("Ich habe die Wal getroffen").text,
                       "Ich habe die Wal getroffen")
    }

    func testLearnedInnerCapitalsSurviveAStyleThatLowercases() {
        let vocabulary = DictationVocabulary(userTerms: [], learnedFixes: [
            TyprDictationCorrection(heard: "gitub", meant: "GitHub", caseIsKnown: true),
            TyprDictationCorrection(heard: "wal", meant: "Wahl", caseIsKnown: true),
        ])
        XCTAssertEqual(vocabulary.afterFormatting("auf github die wahl"), "auf GitHub die wahl")
    }
}
