import UIKit
import XCTest
@testable import Typr

@MainActor
final class EmojiPanelTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "EmojiPanelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private var index: EmojiIndex {
        get throws { try XCTUnwrap(EmojiIndex.load(bundle: Bundle(for: FullKeyboardView.self))) }
    }

    // MARK: - Suggestions for the finished word

    func testGermanWordsSuggestTheirEmojiFirst() throws {
        let index = try index
        XCTAssertEqual(index.suggestions(before: "Ich schicke dir ein Herz ").first, "❤️")
        XCTAssertEqual(index.suggestions(before: "Viele Herzen ").first, "❤️")
        XCTAssertEqual(index.suggestions(before: "Herzlichen Glückwunsch ").first, "🎉")
        XCTAssertEqual(index.suggestions(before: "Heute gibt es Pizza ").first, "🍕")
        XCTAssertEqual(index.suggestions(before: "Deutschland "), ["🇩🇪"])
        XCTAssertEqual(index.suggestions(before: "I love you heart ").first, "❤️")
        XCTAssertLessThanOrEqual(index.suggestions(before: "Liebe ").count, 3)
    }

    func testNoEmojiMidWordAfterPunctuationOrForCommonWords() throws {
        let index = try index
        XCTAssertEqual(index.suggestions(before: "Herz"), [])
        XCTAssertEqual(index.suggestions(before: "Herz  "), [])
        XCTAssertEqual(index.suggestions(before: "Herz. "), [])
        XCTAssertEqual(index.suggestions(before: "und "), [])
        XCTAssertEqual(index.suggestions(before: nil), [])
    }

    func testCatalogCoversEveryCategoryWithoutSkinToneVariants() throws {
        let index = try index
        XCTAssertGreaterThan(index.emoji.count, 1_800)
        XCTAssertEqual(Set(index.categories), Set(EmojiCategory.allCases))
        XCTAssertFalse(index.emoji.contains { $0.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) } })
    }

    // MARK: - Frequently used

    func testFrequentlyUsedOrdersByUseAndPersists() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let store = EmojiUsageStore(defaults: defaults, now: { now })
        store.record("❤️")
        store.record("😂")
        store.record("😂")
        XCTAssertEqual(store.ranked(limit: 10), ["😂", "❤️"])
        XCTAssertEqual(EmojiUsageStore(defaults: defaults, now: { now }).ranked(limit: 10), ["😂", "❤️"])

        // Three uses a month ago fade below one use today.
        now = now.addingTimeInterval(30 * 86_400)
        store.record("👍")
        XCTAssertEqual(store.ranked(limit: 1), ["👍"])
    }

    func testFrequentlyUsedForgetsTheFaintestBeyondItsCapacity() {
        var now = Date(timeIntervalSince1970: 0)
        let store = EmojiUsageStore(defaults: defaults, now: { now })
        let index = try? index
        let emoji = Array((index?.emoji ?? []).prefix(EmojiUsageStore.capacity + 1))
        XCTAssertEqual(emoji.count, EmojiUsageStore.capacity + 1)
        for item in emoji {
            store.record(item)
            now = now.addingTimeInterval(60)
        }
        let ranked = store.ranked(limit: 1_000)
        XCTAssertEqual(ranked.count, EmojiUsageStore.capacity)
        XCTAssertFalse(ranked.contains(emoji[0]))
        XCTAssertEqual(ranked.first, emoji.last)
    }

    func testFrequentSectionPutsYourEmojiFirstThenEverydayOnes() throws {
        let frequent = EmojiPanelView.frequent(used: ["🍕", "🍕", "🚀"], index: try index, capacity: 5)
        XCTAssertEqual(frequent, ["🍕", "🚀", "😂", "❤️", "👍"])
    }

    // MARK: - Keyboard

    private func keyboard(emojiKey: Bool, text: String = "") -> (FullKeyboardView, FixtureTextTarget) {
        let target = FixtureTextTarget(text: text)
        let model = KeyboardViewModel()
        model.bottomRow = BottomRow(emojiKey: emojiKey)
        let view = FullKeyboardView(model: model, target: target, autocorrect: AutocorrectEngine(spatialDecoder: nil))
        let defaults = defaults
        view.makeEmojiUsage = { EmojiUsageStore(defaults: defaults) }
        view.suggestionBarOverride = true
        view.orientationOverride = .portrait
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return (view, target)
    }

    private func tapEmojiKey(_ view: FullKeyboardView) throws {
        let key = try XCTUnwrap(view.engine.layout.key(.emoji))
        let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
        view.engine.touchBegan(id: 1, at: point)
        view.engine.touchEnded(id: 1, at: point)
    }

    func testEmojiKeyOnlyWhenTurnedOn() {
        XCTAssertNil(keyboard(emojiKey: false).0.engine.layout.key(.emoji))
        XCTAssertNotNil(keyboard(emojiKey: true).0.engine.layout.key(.emoji))
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).bottomRow.emojiKey)
        FullKeyboardSettings(defaults: defaults).bottomRow = BottomRow(emojiKey: true)
        XCTAssertTrue(FullKeyboardSettings(defaults: defaults).bottomRow.emojiKey)
    }

    func testPanelOpensInsertsDeletesAndClosesWithABC() throws {
        EmojiUsageStore(defaults: defaults).record("🚀")
        let (view, target) = keyboard(emojiKey: true, text: "Los ")
        try tapEmojiKey(view)
        let panel = try XCTUnwrap(view.emojiPanel)
        XCTAssertEqual(panel.sections.first?.title, "Frequently used")
        XCTAssertEqual(panel.sections.first?.entries.first, "🚀")
        XCTAssertEqual(panel.sections.count, 1 + EmojiCategory.allCases.count)

        panel.debugTap(section: 0, item: 0)
        XCTAssertEqual(target.text, "Los 🚀")
        panel.debugTap(section: 1, item: 0)
        XCTAssertEqual(target.text, "Los 🚀😀")
        XCTAssertEqual(EmojiUsageStore(defaults: defaults).ranked(limit: 1), ["🚀"])

        panel.debugTapDelete()
        XCTAssertEqual(target.text, "Los 🚀")

        panel.debugTapLetters()
        XCTAssertNil(view.emojiPanel)
        XCTAssertNil(panel.superview)
    }

    func testSlidingAlongTheCategoryBarScrubsTheGrid() throws {
        let (view, _) = keyboard(emojiKey: true)
        try tapEmojiKey(view)
        let panel = try XCTUnwrap(view.emojiPanel)
        panel.layoutIfNeeded()
        let bar = panel.categoryBar
        XCTAssertEqual(panel.visibleSection, 0)
        bar.touchBegan(atX: 2)
        bar.touchMoved(toX: bar.bounds.width - 2)
        XCTAssertEqual(bar.selected, EmojiCategory.allCases.count)
        XCTAssertEqual(panel.visibleSection, EmojiCategory.allCases.count)
        bar.touchEnded(atX: bar.bounds.width - 2)

        // A tap jumps to the section's start.
        let food = EmojiCategory.foodDrink.rawValue + 1
        let x = (CGFloat(food) + 0.5) * bar.bounds.width / CGFloat(EmojiCategory.allCases.count + 1)
        bar.touchBegan(atX: x)
        bar.touchEnded(atX: x)
        XCTAssertEqual(panel.visibleSection, food)
    }

    func testStripOffersTheFinishedWordsEmojiAndTypesIt() throws {
        let (view, target) = keyboard(emojiKey: true, text: "Ich schicke dir ein Herz ")
        view.textDidChange()
        let chip = try XCTUnwrap(view.shownSuggestions.first { $0.isEmoji })
        XCTAssertEqual(chip.replacement, "❤️")

        view.debugPick(chip)
        XCTAssertEqual(target.text, "Ich schicke dir ein Herz ❤️ ")
        XCTAssertEqual(EmojiUsageStore(defaults: defaults).ranked(limit: 1), ["❤️"])
    }

    func testStripShowsNoEmojiWithTheKeyOff() {
        let (view, _) = keyboard(emojiKey: false, text: "Ein Herz ")
        view.textDidChange()
        XCTAssertFalse(view.shownSuggestions.contains { $0.isEmoji })
    }
}
