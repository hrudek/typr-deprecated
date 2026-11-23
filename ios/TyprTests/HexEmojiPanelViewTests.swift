import UIKit
import XCTest
@testable import Typr

@MainActor
final class HexEmojiPanelViewTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var library: EmojiLibrary!

    override func setUp() async throws {
        suiteName = "HexEmojiPanelViewTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        library = try XCTUnwrap(EmojiLibrary.load(language: "en"))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makePanel(width: CGFloat = 402, before: String? = "pizza ") -> (EmojiPanelView, EmojiUsageStore) {
        let usage = EmojiUsageStore(defaults: defaults)
        let panel = EmojiPanelView(library: library, usage: usage)
        panel.frame = CGRect(x: 0, y: 0, width: width, height: 306)
        panel.fill(before: before)
        panel.layoutIfNeeded()
        return (panel, usage)
    }

    private func grid(of panel: EmojiPanelView) throws -> UICollectionView {
        let grid = try XCTUnwrap(panel.subviews.compactMap { $0 as? UICollectionView }.first)
        grid.layoutIfNeeded()
        return grid
    }

    private func subview<T: UIView>(_ type: T.Type, of panel: EmojiPanelView) throws -> T {
        try XCTUnwrap(panel.subviews.compactMap { $0 as? T }.first)
    }

    private func key(_ label: String, of panel: EmojiPanelView) throws -> PanelKeyButton {
        try XCTUnwrap(panel.subviews.compactMap { $0 as? PanelKeyButton }.first { $0.accessibilityLabel == label })
    }

    func testStandalonePanelKeepsLettersKeyAtTheLeadingEnd() throws {
        let (panel, _) = makePanel()
        let letters = try key("Letters", of: panel)
        let keyWidth = min(44, KeyboardLayout.letterWidth(
            innerWidth: panel.bounds.width - 2 * panel.horizontalInset,
            metrics: panel.metrics
        ) * KeyboardLayout.bottomSwitchWidthRatio)
        XCTAssertEqual(letters.frame.minX, panel.horizontalInset + panel.metrics.side, accuracy: 0.5)
        XCTAssertEqual(letters.frame.width, keyWidth, accuracy: 0.5)
        XCTAssertEqual(letters.title, "ABC")

        panel.returnsToBar = true
        XCTAssertNil(letters.title)
        XCTAssertEqual(letters.symbol, "chevron.left")
        XCTAssertEqual(letters.accessibilityLabel, String(localized: "Back"))
    }

    func testEmojiKeyFrameMovesLettersKeyAndCategoriesStayBetweenKeys() throws {
        let (panel, _) = makePanel()
        panel.emojiKeyFrame = CGRect(x: 60, y: 0, width: 40, height: 40)
        panel.layoutIfNeeded()
        let letters = try key("Letters", of: panel)
        let delete = try key("Delete", of: panel)
        let categories = try subview(EmojiCategoryBar.self, of: panel)
        XCTAssertEqual(letters.frame.minX, 60, accuracy: 0.5)
        XCTAssertEqual(letters.frame.width, 40, accuracy: 0.5)
        XCTAssertGreaterThan(categories.frame.width, 0)
        XCTAssertGreaterThan(categories.frame.minX, letters.frame.maxX)
        XCTAssertLessThan(categories.frame.maxX, delete.frame.minX)
    }

    func testBandUnderTheGridRoutesTouchesToBarKeys() throws {
        let (panel, _) = makePanel()
        let letters = try key("Letters", of: panel)
        let delete = try key("Delete", of: panel)
        let categories = try subview(EmojiCategoryBar.self, of: panel)
        let bottom = panel.bounds.height - 1
        XCTAssertTrue(panel.hitTest(CGPoint(x: 1, y: bottom), with: nil) === letters)
        XCTAssertTrue(panel.hitTest(CGPoint(x: panel.bounds.width - 1, y: bottom), with: nil) === delete)
        XCTAssertTrue(panel.hitTest(CGPoint(x: categories.frame.midX, y: bottom), with: nil) === categories)
        XCTAssertTrue(letters.point(inside: letters.convert(CGPoint(x: 1, y: bottom), from: panel), with: nil))
    }

    func testGridHoldsFrequentlyUsedThenEveryCategoryAndInsertsTappedEmoji() throws {
        let (panel, usage) = makePanel()
        usage.record("🦄")
        panel.fill(before: nil)
        panel.layoutIfNeeded()

        XCTAssertEqual(panel.sections.count, 1 + EmojiCategory.allCases.count)
        XCTAssertEqual(panel.sections[0].title, "Frequently used")
        XCTAssertEqual(panel.sections[0].entries.count, panel.frequentCapacity)
        XCTAssertEqual(panel.sections[0].entries.first.map { library.entries[$0].emoji }, "🦄")
        XCTAssertEqual(panel.sections.dropFirst().map(\.entries.count).reduce(0, +), library.entries.count)

        let grid = try grid(of: panel)
        XCTAssertEqual(grid.numberOfSections, panel.sections.count)
        let cells = grid.visibleCells.compactMap { $0 as? EmojiCell }
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { $0.emoji != nil })

        var inserted: [(String, Int, String)] = []
        panel.onInsert = { inserted.append(($0, $1, $2)) }
        panel.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
        XCTAssertEqual(inserted.first?.0, "🦄")
        XCTAssertEqual(inserted.first?.2, "grid")
    }

    func testSuggestionRowFollowsTheTextBeforeTheCursor() throws {
        let (panel, _) = makePanel(before: "pizza ")
        let pizza = try XCTUnwrap(library.entryByEmoji["🍕"])
        XCTAssertTrue(panel.suggestions.contains(pizza))
        XCTAssertEqual(panel.suggestionRow.items.count, panel.suggestions.count)

        var inserted: [(String, Int, String)] = []
        panel.onInsert = { inserted.append(($0, $1, $2)) }
        panel.suggestionRow.onPick?(0)
        XCTAssertEqual(inserted.first?.1, panel.suggestions[0])
        XCTAssertEqual(inserted.first?.2, "suggestion")
    }

    func testCategoryTapJumpsAndSlideScrubsTheGrid() throws {
        let (panel, _) = makePanel()
        let grid = try grid(of: panel)
        let bar = try subview(EmojiCategoryBar.self, of: panel)
        let slot = bar.bounds.width / CGFloat(panel.sections.count)

        bar.touchBegan(atX: slot * 3.5)
        bar.touchEnded(atX: slot * 3.5)
        XCTAssertEqual(bar.selected, 3)
        let afterTap = grid.contentOffset.x
        XCTAssertGreaterThan(afterTap, 0)

        var steps = 0
        panel.onSelectionStep = { steps += 1 }
        bar.touchBegan(atX: slot * 3.1)
        bar.touchMoved(toX: slot * 3.1 + EmojiCategoryBar.scrubThreshold / 2)
        XCTAssertFalse(bar.isScrubbing)
        bar.touchMoved(toX: slot * 5.5)
        XCTAssertTrue(bar.isScrubbing)
        XCTAssertEqual(bar.selected, 5)
        XCTAssertEqual(steps, 1)
        XCTAssertGreaterThan(grid.contentOffset.x, afterTap)
        bar.touchEnded(atX: slot * 5.5)
        XCTAssertFalse(bar.isScrubbing)
        XCTAssertEqual(bar.selected, 5)
    }

    func testSkinTonePickerShowsAndRemembersTheTone() throws {
        let (panel, usage) = makePanel()
        let wave = try XCTUnwrap(library.entryByEmoji["👋"])
        let tones = library.entries[wave].tones
        XCTAssertEqual(tones.count, 5)
        XCTAssertEqual(panel.display(for: wave), "👋")

        panel.debugShowTones(for: "👋", selecting: 3)
        let picker = try subview(AccentCalloutView.self, of: panel)
        let menu = try XCTUnwrap(picker.menu)
        XCTAssertEqual(Set(menu.options), Set(["👋"] + tones))
        XCTAssertEqual(menu.options[menu.selectedIndex], tones[2])
        XCTAssertEqual(picker.separatedOption, "👋")

        panel.tearDown()
        XCTAssertNil(picker.menu)

        usage.setTone(2, for: "👋")
        XCTAssertEqual(panel.display(for: wave), tones[1])
    }

    func testDeleteFiresOnTouchDownAndRepeatsWhileHeld() throws {
        let (panel, _) = makePanel()
        let delete = try key("Delete", of: panel)
        var deletes = 0
        var keyDowns = 0
        panel.onDelete = { deletes += 1 }
        panel.onKeyDown = { keyDowns += 1 }
        let repeated = expectation(description: "repeat while held")
        repeated.assertForOverFulfill = false
        panel.onDeleteRepeat = { held in
            XCTAssertGreaterThanOrEqual(held, FullKeyboardEngine.repeatDelay)
            repeated.fulfill()
        }

        delete.sendActions(for: .touchDown)
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(keyDowns, 1)
        wait(for: [repeated], timeout: 3)
        delete.sendActions(for: .touchUpInside)
        XCTAssertEqual(deletes, 1)
    }

    func testLettersKeyLeavesThePanel() throws {
        let (panel, _) = makePanel()
        var letters = 0
        panel.onLetters = { letters += 1 }
        try key("Letters", of: panel).sendActions(for: .touchUpInside)
        XCTAssertEqual(letters, 1)
    }

    func testRoutedTargetTypesIntoTheQueryWhileSearching() {
        let document = HexFixtureTextTarget(text: "Hi ")
        let target = EmojiRoutedTarget(document: document)
        var returns = 0
        target.onSearchReturn = { returns += 1 }

        target.insertText("x")
        XCTAssertEqual(document.documentContextBeforeInput, "Hi x")
        target.deleteBackward()

        target.query = ""
        XCTAssertTrue(target.isSearching)
        XCTAssertFalse(target.hasText)
        for letter in ["p", "i", "z"] { target.insertText(letter) }
        target.deleteBackward()
        target.adjustTextPosition(byCharacterOffset: -1)
        XCTAssertEqual(target.query, "pi")
        XCTAssertEqual(target.documentContextBeforeInput, "pi")
        XCTAssertNil(target.documentContextAfterInput)
        XCTAssertEqual(target.returnKeyType, .done)
        XCTAssertEqual(target.autocorrectionType, .no)
        XCTAssertEqual(target.autocapitalizationType, UITextAutocapitalizationType.none)
        target.insertText("\n")
        XCTAssertEqual(returns, 1)
        XCTAssertEqual(target.query, "pi")
        XCTAssertEqual(document.documentContextBeforeInput, "Hi ")
        XCTAssertEqual(document.documentContextAfterInput, "")

        target.query = nil
        XCTAssertEqual(target.documentContextBeforeInput, "Hi ")
        XCTAssertEqual(target.returnKeyType, document.returnKeyType)
    }

    func testSearchFieldAndResultRowShowQueryAndEmptyState() throws {
        let field = EmojiSearchField(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        let label = try XCTUnwrap(field.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, "Search emoji")
        field.query = "piz"
        XCTAssertEqual(label.text, "piz")
        XCTAssertEqual(label.accessibilityValue, "piz")

        let row = EmojiRowView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        row.emptyText = "No emoji found"
        row.layoutIfNeeded()
        let empty = try XCTUnwrap(row.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertFalse(empty.isHidden)
        row.setItems([(emoji: "🍕", name: "pizza")])
        XCTAssertTrue(empty.isHidden)
        XCTAssertEqual(row.cellWidth, 300 / 7, accuracy: 0.01)
    }

    func testGlyphRendererCachesWithinItsByteLimitAndReleasesTheFont() throws {
        let renderer = EmojiGlyphRenderer(byteLimit: 64 << 10, rendersPerFont: 4)
        XCTAssertTrue(renderer.hasPrivateFont)
        let first = try XCTUnwrap(renderer.glyph(for: "😀", size: 32, scale: 3))
        XCTAssertFalse(first.rect.isEmpty)
        XCTAssertGreaterThan(first.image.width, 0)
        XCTAssertTrue(renderer.glyph(for: "😀", size: 32, scale: 3) === first)
        XCTAssertEqual(renderer.renders, 1)

        for emoji in ["🍕", "🦄", "🎉", "🔥", "😭", "🥰", "🙏", "👍"] {
            _ = renderer.glyph(for: emoji, size: 32, scale: 3)
        }
        XCTAssertLessThanOrEqual(renderer.cachedBytes, renderer.byteLimit)
        XCTAssertLessThan(renderer.cachedCount, 9)
        XCTAssertGreaterThanOrEqual(renderer.fontsMade, 2)

        _ = renderer.glyph(for: "🐻", size: 26, scale: 3)
        XCTAssertTrue(renderer.holdsFont)
        let single = EmojiGlyphRenderer(rendersPerFont: 1)
        XCTAssertNotNil(single.glyph(for: "🐻", size: 26, scale: 3))
        XCTAssertFalse(single.holdsFont)

        renderer.purge()
        XCTAssertEqual(renderer.cachedCount, 0)
        XCTAssertEqual(renderer.cachedBytes, 0)
    }

    func testCellsDropTheirBitmapOffScreen() throws {
        let (panel, _) = makePanel()
        let grid = try grid(of: panel)
        let cell = try XCTUnwrap(grid.visibleCells.compactMap { $0 as? EmojiCell }.first)
        XCTAssertNotNil(cell.emoji)
        panel.collectionView(grid, didEndDisplaying: cell, forItemAt: IndexPath(item: 0, section: 0))
        XCTAssertNil(cell.emoji)
        XCTAssertGreaterThan(panel.glyphs.cachedCount, 0)
    }
}
