import UIKit

// Adapted from anomalyco/hex ios/HEXShared/FullKeyboard/Emoji/EmojiPanelView.swift and
// EmojiViews.swift at d65b02d36efbaf1ff771420e89c0632dea4706cb (MIT).

/// The emoji panel in place of the strip and the keys: a grid that scrolls sideways through
/// Frequently used and every category, and a bar with ABC, the categories and delete. Sliding
/// along the categories scrubs the grid.
@MainActor
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    struct Section {
        let title: String
        let entries: [String]
    }

    /// Before you have used any: the emoji people send most, roughly.
    static let everyday = ["😂", "❤️", "👍", "😊", "🙏", "😍", "🎉", "🔥", "😭", "🥰", "😘", "😅"]

    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    var metrics = KeyboardMetrics.portrait { didSet { if metrics != oldValue { setNeedsLayout() } } }
    var horizontalInset: CGFloat = 0 { didSet { if horizontalInset != oldValue { setNeedsLayout() } } }
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?
    /// The delete key is still held: how long, for repeat and word delete.
    var onDeleteRepeat: ((TimeInterval) -> Void)?
    var onLetters: (() -> Void)?
    var onKeyDown: (() -> Void)?
    var onSelectionStep: (() -> Void)?

    private(set) var sections: [Section] = []
    private let grid: UICollectionView
    let categoryBar: EmojiCategoryBar
    private let lettersKey = PanelKeyButton()
    private let deleteKey = PanelKeyButton()
    private var geometry: GridGeometry?
    private var sectionStarts: [CGFloat] = []
    private var deleteTimer: Timer?
    private var deleteStartedAt: TimeInterval = 0

    private struct GridGeometry: Equatable {
        let rows: Int
        let rowHeight: CGFloat
        let columnWidth: CGFloat
        let headerHeight: CGFloat
        let fontSize: CGFloat
        let counts: [Int]
    }

    init(index: EmojiIndex, frequent: [String]) {
        grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        categoryBar = EmojiCategoryBar(items: [("clock", "Frequently used")] + EmojiCategory.allCases.map { ($0.symbol, $0.title) })
        super.init(frame: .zero)
        backgroundColor = .clear

        var byCategory = Array(repeating: [String](), count: EmojiCategory.allCases.count)
        for (emoji, category) in zip(index.emoji, index.categories) {
            byCategory[category.rawValue].append(emoji)
        }
        sections = [Section(title: "Frequently used", entries: frequent)]
            + EmojiCategory.allCases.map { Section(title: $0.title, entries: byCategory[$0.rawValue]) }

        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        grid.delaysContentTouches = false
        grid.isPrefetchingEnabled = false
        if #available(iOS 26.0, *) {
            // Nothing sits over the grid; iOS 26's edge blur would only soften its emoji.
            for edge in [grid.topEdgeEffect, grid.bottomEdgeEffect, grid.leftEdgeEffect, grid.rightEdgeEffect] {
                edge.isHidden = true
            }
        }
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        grid.register(EmojiSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: EmojiSectionHeader.reuseID)
        addSubview(grid)

        categoryBar.onSelect = { [weak self] section in self?.jump(toSection: section) }
        categoryBar.onScrub = { [weak self] section, fraction in self?.scrub(toSection: section, fraction: fraction) }
        categoryBar.onScrubStep = { [weak self] in self?.onSelectionStep?() }
        addSubview(categoryBar)

        lettersKey.title = "ABC"
        lettersKey.accessibilityLabel = "Letters"
        lettersKey.addTarget(self, action: #selector(lettersTapped), for: .touchUpInside)
        addSubview(lettersKey)
        deleteKey.symbol = "delete.left"
        deleteKey.accessibilityLabel = "Delete"
        deleteKey.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteKey.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addSubview(deleteKey)
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Your emoji first, then everyday ones and the first smileys, up to `capacity`.
    static func frequent(used: [String], index: EmojiIndex, capacity: Int) -> [String] {
        var out: [String] = []
        let smileys = zip(index.emoji, index.categories).lazy.filter { $0.1 == .smileysPeople }.map { $0.0 }.prefix(capacity)
        for emoji in used + everyday + smileys where out.count < capacity && !out.contains(emoji) && index.entry(for: emoji) != nil {
            out.append(emoji)
        }
        return out
    }

    /// Four rows on roomy keyboards, three on compact ones; Frequently used fills eight columns.
    static func gridRows(for metrics: KeyboardMetrics) -> Int { metrics.keyHeight >= 40 ? 4 : 3 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = metrics.side
        let barHeight = min(metrics.keyHeight, 38)
        let barY = bounds.height - metrics.keysBottom - barHeight
        let keyWidth = KeyboardLayout.letterWidth(innerWidth: bounds.width - 2 * horizontalInset, metrics: metrics)
            * KeyboardLayout.modifierWidthRatio
        lettersKey.frame = CGRect(x: horizontalInset + side, y: barY, width: keyWidth, height: barHeight)
        deleteKey.frame = CGRect(x: bounds.width - horizontalInset - side - keyWidth, y: barY, width: keyWidth, height: barHeight)
        lettersKey.cornerRadius = metrics.cornerRadius
        deleteKey.cornerRadius = metrics.cornerRadius
        categoryBar.frame = CGRect(x: lettersKey.frame.maxX + 4, y: barY,
                                   width: max(0, deleteKey.frame.minX - lettersKey.frame.maxX - 8), height: barHeight)
        let top = metrics.stripTop
        let gridFrame = CGRect(x: horizontalInset, y: top, width: bounds.width - 2 * horizontalInset, height: max(0, barY - 4 - top))
        grid.frame = gridFrame
        applyGridLayout(height: gridFrame.height)
    }

    /// The band under the grid belongs to the bar's keys, so a thumb that lands under a small icon still hits it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, self.point(inside: point, with: event) else { return nil }
        if point.y >= grid.frame.maxY {
            if point.x < categoryBar.frame.minX { return lettersKey }
            if point.x >= categoryBar.frame.maxX { return deleteKey }
            return categoryBar
        }
        return super.hitTest(point, with: event)
    }

    private func applyGridLayout(height: CGFloat) {
        let isRoomy = metrics.keyHeight >= 40
        let headerHeight: CGFloat = isRoomy ? 20 : 16
        let rows = Self.gridRows(for: metrics)
        let next = GridGeometry(
            rows: rows,
            rowHeight: max(20, (height - headerHeight) / CGFloat(rows)),
            columnWidth: isRoomy ? 46 : 42,
            headerHeight: headerHeight,
            fontSize: isRoomy ? 32 : 26,
            counts: sections.map(\.entries.count)
        )
        guard next != geometry, height > 0 else { return }
        geometry = next
        sectionStarts = []
        grid.setCollectionViewLayout(Self.makeLayout(next), animated: false)
        grid.reloadData()
    }

    private static func makeLayout(_ g: GridGeometry) -> UICollectionViewCompositionalLayout {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        config.interSectionSpacing = 10
        return UICollectionViewCompositionalLayout(sectionProvider: { index, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .absolute(g.rowHeight)))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(g.columnWidth),
                                                   heightDimension: .absolute(g.rowHeight * CGFloat(g.rows))),
                repeatingSubitem: item, count: g.rows)
            let section = NSCollectionLayoutSection(group: group)
            let count = index < g.counts.count ? g.counts[index] : 0
            let columns = max(1, (count + g.rows - 1) / g.rows)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(CGFloat(columns) * g.columnWidth),
                                                   heightDimension: .absolute(g.headerHeight)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            section.boundarySupplementaryItems = [header]
            // A horizontal layout doesn't move items below a top header; the inset does.
            section.contentInsets = NSDirectionalEdgeInsets(top: g.headerHeight, leading: 2, bottom: 0, trailing: 2)
            section.supplementaryContentInsetsReference = .none
            return section
        }, configuration: config)
    }

    private func applyPalette() {
        categoryBar.palette = palette
        lettersKey.palette = palette
        deleteKey.palette = palette
        grid.reloadData()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath)
        (cell as? EmojiCell)?.configure(emoji: sections[indexPath.section].entries[indexPath.item],
                                        fontSize: geometry?.fontSize ?? 32, palette: palette)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: EmojiSectionHeader.reuseID,
                                                                   for: indexPath)
        if let header = view as? EmojiSectionHeader {
            header.label.text = sections[indexPath.section].title
            header.label.textColor = palette.textMuted
        }
        return view
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onKeyDown?()
        onInsert?(sections[indexPath.section].entries[indexPath.item])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !categoryBar.isScrubbing else { return }
        if sectionStarts.isEmpty { measureSections() }
        let x = scrollView.contentOffset.x + 24
        categoryBar.selected = sectionStarts.lastIndex { $0 <= x } ?? 0
    }

    private func measureSections() {
        sectionStarts = sections.indices.map { section in
            guard !sections[section].entries.isEmpty,
                  let attributes = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) else {
                return .greatestFiniteMagnitude
            }
            return attributes.frame.minX
        }
    }

    /// Where a section's first emoji sits; an empty one starts where the next does.
    private func sectionStart(_ section: Int) -> CGFloat {
        sectionStarts[section...].first { $0 != .greatestFiniteMagnitude } ?? grid.contentSize.width
    }

    private func jump(toSection section: Int) {
        guard section < sections.count else { return }
        onKeyDown?()
        scrub(toSection: section, fraction: 0)
        categoryBar.selected = section
    }

    /// The grid shows `section` `fraction` of the way through, live.
    private func scrub(toSection section: Int, fraction: CGFloat) {
        guard section < sections.count else { return }
        grid.layoutIfNeeded()
        if sectionStarts.isEmpty { measureSections() }
        let start = sectionStart(section)
        let end = section + 1 < sections.count ? sectionStart(section + 1) : grid.contentSize.width
        let maxX = max(0, grid.contentSize.width - grid.bounds.width)
        let x = start + min(1, max(0, fraction)) * max(0, end - start)
        grid.setContentOffset(CGPoint(x: min(maxX, max(0, x - 2)), y: 0), animated: false)
    }

    /// The section the grid shows at its leading edge.
    var visibleSection: Int {
        if sectionStarts.isEmpty { measureSections() }
        return sectionStarts.lastIndex { $0 <= grid.contentOffset.x + 24 } ?? 0
    }

    @objc private func lettersTapped() {
        onKeyDown?()
        onLetters?()
    }

    @objc private func deleteDown() {
        onKeyDown?()
        onDelete?()
        deleteTimer?.invalidate()
        deleteStartedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: FullKeyboardEngine.repeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let held = CACurrentMediaTime() - self.deleteStartedAt
                guard held >= FullKeyboardEngine.repeatDelay else { return }
                self.onDeleteRepeat?(held)
                self.onKeyDown?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deleteTimer = timer
    }

    @objc private func deleteUp() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    func tearDown() {
        deleteUp()
    }

    /// Tests: tap an emoji in the grid.
    func debugTap(section: Int, item: Int) {
        collectionView(grid, didSelectItemAt: IndexPath(item: item, section: section))
    }

    /// Tests: tap ABC or delete.
    func debugTapLetters() { lettersTapped() }
    func debugTapDelete() {
        deleteDown()
        deleteUp()
    }
}

/// One emoji in the grid, with a pressed fill.
@MainActor
final class EmojiCell: UICollectionViewCell {
    static let reuseID = "emoji"
    private let label = UILabel()
    private var pressedFill: UIColor = .clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(emoji: String, fontSize: CGFloat, palette: FullKeyboardPalette) {
        label.text = emoji
        label.font = .systemFont(ofSize: fontSize)
        accessibilityLabel = emoji
        pressedFill = palette.keyPressedFill
        contentView.backgroundColor = isHighlighted ? pressedFill : .clear
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? pressedFill : .clear }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}

/// A section's name over the grid ("Frequently used", "Food and drink").
@MainActor
final class EmojiSectionHeader: UICollectionReusableView {
    static let reuseID = "header"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.isAccessibilityElement = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 10, y: 0, width: max(0, bounds.width - 10), height: bounds.height)
    }
}

/// The bar under the grid: one icon per section, the current one on a chip. A tap jumps to a
/// section when the finger lifts; a finger sliding along the bar scrubs the grid, each icon's
/// slot running through its own section from start to end.
@MainActor
final class EmojiCategoryBar: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { refresh() } } }
    var onSelect: ((Int) -> Void)?
    /// A slide is over the section, this far (0 to 1) across its slot.
    var onScrub: ((Int, CGFloat) -> Void)?
    /// A slide moved onto another section.
    var onScrubStep: (() -> Void)?
    var selected = 0 { didSet { if selected != oldValue { refresh() } } }

    private(set) var isScrubbing = false
    /// How far (points) a finger moves along the bar before a tap becomes a slide.
    static let scrubThreshold: CGFloat = 8
    private var touchStartX: CGFloat?

    private final class BarButton: UIButton {
        var activate: (() -> Void)?

        override func accessibilityActivate() -> Bool {
            activate?()
            return true
        }
    }

    private var buttons: [BarButton] = []
    private let chip = UIView()

    init(items: [(symbol: String, title: String)]) {
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        chip.isUserInteractionEnabled = false
        chip.layer.cornerCurve = .continuous
        addSubview(chip)
        for (index, item) in items.enumerated() {
            let button = BarButton(type: .custom)
            button.accessibilityLabel = item.title
            button.setImage(UIImage(systemName: item.symbol,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
            button.isUserInteractionEnabled = false
            button.activate = { [weak self] in self?.onSelect?(index) }
            addSubview(button)
            buttons.append(button)
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The slot under `x` (outside the bar, the nearest), and how far across it `x` is.
    func slot(atX x: CGFloat) -> (index: Int, fraction: CGFloat) {
        guard !buttons.isEmpty, bounds.width > 0 else { return (0, 0) }
        let width = bounds.width / CGFloat(buttons.count)
        let position = min(max(0, x), bounds.width - 0.001) / width
        let index = min(buttons.count - 1, Int(position))
        return (index, position - CGFloat(index))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { touchBegan(atX: touch.location(in: self).x) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { touchMoved(toX: touch.location(in: self).x) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { touchEnded(atX: touch.location(in: self).x) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchCancelled()
    }

    func touchBegan(atX x: CGFloat) {
        touchStartX = x
        isScrubbing = false
    }

    func touchMoved(toX x: CGFloat) {
        guard let start = touchStartX else { return }
        if !isScrubbing {
            guard abs(x - start) > Self.scrubThreshold else { return }
            isScrubbing = true
        }
        let (index, fraction) = slot(atX: x)
        if index != selected {
            selected = index
            onScrubStep?()
        }
        onScrub?(index, fraction)
    }

    func touchEnded(atX x: CGFloat) {
        defer { touchCancelled() }
        guard touchStartX != nil, !isScrubbing else { return }
        onSelect?(slot(atX: x).index)
    }

    func touchCancelled() {
        touchStartX = nil
        isScrubbing = false
    }

    private func refresh() {
        chip.backgroundColor = palette.chipFill
        for (index, button) in buttons.enumerated() {
            button.tintColor = palette.textMuted
            button.accessibilityTraits = index == selected ? [.button, .selected] : .button
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttons.isEmpty else { return }
        let width = bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        let side = max(0, min(30, bounds.height - 4, width - 2))
        let selectedFrame = buttons[min(selected, buttons.count - 1)].frame
        chip.frame = CGRect(x: selectedFrame.midX - side / 2, y: selectedFrame.midY - side / 2, width: side, height: side)
        chip.layer.cornerRadius = side / 2
    }
}
