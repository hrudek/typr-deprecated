import XCTest
@testable import Typr

@MainActor
final class HexEmojiLibraryTests: XCTestCase {
    func testLocalizedCatalogsAndLicenseFilesAreBundled() throws {
        let bundle = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
            .appendingPathComponent("TyprKeyboard.appex")
        let extensionBundle = try XCTUnwrap(Bundle(url: bundle))
        for target in [Bundle.main, extensionBundle] {
            for license in ["Unicode", "CLDR", "Hex"] {
                XCTAssertNotNil(target.url(forResource: "LICENSE-\(license)", withExtension: "txt", subdirectory: "EmojiData"))
            }
            for language in EmojiLibrary.languages {
                let url = try XCTUnwrap(target.url(forResource: "emoji-index-\(language)", withExtension: "txt", subdirectory: "EmojiData"))
                let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                XCTAssertLessThan(size, 640 * 1024)
            }
        }

        let queries = ["en": ("flag jap", "🇯🇵"), "de": ("eisbär", "🐻‍❄️"),
                       "es": ("cumpleaños", "🎂"), "nb": ("kaffe", "☕")]
        for language in EmojiLibrary.languages {
            let library = try XCTUnwrap(EmojiLibrary.load(language: language, isDrawable: { _ in false }))
            XCTAssertEqual(Set(library.entries.map(\.category)), Set(EmojiCategory.allCases))
            XCTAssertTrue((1_850...1_923).contains(library.entries.count))
            let (query, emoji) = try XCTUnwrap(queries[language])
            XCTAssertEqual(library.search(query, limit: 1).map { library.entries[$0].emoji }, [emoji], language)
            XCTAssertTrue(library.search("piz", limit: 1).map { library.entries[$0].emoji }.contains("🍕"))
            XCTAssertTrue(library.search("zzzzqq").isEmpty)
        }
    }

    func testCacheKeepsOneLanguageAndEvictionReleasesIt() throws {
        EmojiLibrary.evictCached()
        defer { EmojiLibrary.evictCached() }

        var english = try XCTUnwrap(EmojiLibrary.bundled(language: "en")) as EmojiLibrary?
        weak var previous = english
        XCTAssertTrue(english === EmojiLibrary.bundled(language: "fr"))
        english = nil
        XCTAssertNotNil(previous)
        weak var german = EmojiLibrary.bundled(language: "de")
        XCTAssertNil(previous)
        XCTAssertNotNil(german)

        EmojiLibrary.evictCached()
        XCTAssertNil(german)
        XCTAssertNotNil(EmojiLibrary.bundled(language: "de"))
    }

    func testCatalogRetainsSkinTonesAndFiltersUndrawableNewEmoji() throws {
        let limited = try XCTUnwrap(EmojiLibrary.load(language: "en", isDrawable: { _ in false }))
        let all = try XCTUnwrap(EmojiLibrary.load(language: "en", isDrawable: { _ in true }))
        XCTAssertEqual(all.entries.count, 1_923)
        XCTAssertLessThan(limited.entries.count, all.entries.count)
        XCTAssertNil(limited.entryByEmoji["\u{1FAEB}"])
        XCTAssertNotNil(all.entryByEmoji["\u{1FAEB}"])

        let wave = try XCTUnwrap(limited.entryByEmoji["👋"])
        XCTAssertEqual(limited.entryByEmoji["👋🏽"], wave)
        XCTAssertEqual(limited.entries[wave].tones.count, 5)
        XCTAssertEqual(limited.name(of: wave), "waving hand")
        XCTAssertTrue(EmojiLibrary.fontDraws("🍕"))
        XCTAssertFalse(EmojiLibrary.fontDraws("🍕🍕"))
    }

    func testSuggestionsRankAliasesAndFinishedPhrases() throws {
        let library = try XCTUnwrap(EmojiLibrary.load(language: "en"))
        let context = EmojiContext(before: "congrats on the launch ", stopwords: library.stopwords)
        let suggestions = EmojiSuggester.suggestions(context: context, library: library, usage: [:], limit: 5, fill: false)
            .map { library.entries[$0].emoji }
        XCTAssertTrue(suggestions.contains("🎉"))
        XCTAssertTrue(suggestions.contains("🚀"))
        XCTAssertEqual(EmojiSuggester.forFinishedWord("Happy birthday ", library: library)
            .map { library.entries[$0].emoji }, ["🎂", "🎉", "🥳"])
        XCTAssertTrue(EmojiSuggester.forFinishedWord("pizza", library: library).isEmpty)
    }

    func testUsageDecaysAndKeepsTonesInSeparateHistory() throws {
        let suite = "dev.rudek.typr.tests.hex-emoji.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy = TyprEmojiUsageStore(defaults: defaults)
        legacy.record("😀")
        var now = Date(timeIntervalSince1970: 1_000_000)
        let store = EmojiUsageStore(defaults: defaults, now: { now })
        XCTAssertTrue(store.isEmpty)
        store.record("🍕")
        store.record("🍕")
        now += 2 * EmojiUsageStore.halfLife
        store.record("☕")
        XCTAssertEqual(store.ranked().map(\.emoji), ["☕", "🍕"])
        XCTAssertEqual(try XCTUnwrap(store.ranked().last?.score), 0.5, accuracy: 0.001)

        store.setTone(3, for: "👍")
        XCTAssertEqual(EmojiUsageStore(defaults: defaults).tone(for: "👍"), 3)
        store.clear()
        XCTAssertTrue(EmojiUsageStore(defaults: defaults).isEmpty)
        XCTAssertEqual(TyprEmojiUsageStore(defaults: defaults).ranked(limit: 1), ["😀"])
    }

    func testUsageKeepsOnlyTheHighestScoresAtCapacity() throws {
        let library = try XCTUnwrap(EmojiLibrary.load(language: "en"))
        let store = EmojiUsageStore(defaults: nil)
        let favorite = try XCTUnwrap(library.entries.first).emoji
        store.record(favorite)
        store.record(favorite)
        for entry in library.entries.dropFirst().prefix(EmojiUsageStore.capacity * 2) {
            store.record(entry.emoji)
        }
        let ranked = store.ranked(limit: EmojiUsageStore.capacity * 2)
        XCTAssertEqual(ranked.count, EmojiUsageStore.capacity)
        XCTAssertEqual(ranked.first?.emoji, favorite)
    }

    func testSemanticIndexUsesOnlyItsSuppliedVocabulary() throws {
        XCTAssertNil(EmojiSemanticIndex(language: "en", vocabulary: []))
        let vocabulary = ["pizza", "coffee", "celebration"]
        guard let index = EmojiSemanticIndex(language: "en", vocabulary: vocabulary) else {
            throw XCTSkip("English word embeddings are unavailable on this simulator")
        }
        XCTAssertEqual(index.byteCount, index.vocabularySize * index.dimension * MemoryLayout<Float>.stride)
        XCTAssertLessThanOrEqual(index.vocabularySize, vocabulary.count)
        let result = try XCTUnwrap(index.neighbors(of: "pizza").first)
        XCTAssertEqual(result.word, "pizza")
        XCTAssertEqual(result.similarity, 1, accuracy: 0.0001)
    }
}
