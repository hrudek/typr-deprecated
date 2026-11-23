import UIKit

/// The 3-slot top bar above the keys, matching Apple's iOS 26 suggestion strip:
/// two 1 pt vertical hairlines between the slots when idle or suggesting, replaced by the
/// centred `Undo dictation` chip or a status message when needed. Dictation feedback has its
/// own panel (`TyprFeedbackPanel`).
@MainActor
final class TyprKeyboardStripView: UIView {
    var palette = TyprFullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    /// Hosted extensions sit inside iOS 26's +17 pt Liquid Glass crown above `bounds.minY`,
    /// so nudge the strip's visual centre slightly upward within `bounds` to align with Apple's bar.
    var inSystemPlatter = true {
        didSet {
            guard inSystemPlatter != oldValue else { return }
            for button in slotButtons { button.inSystemPlatter = inSystemPlatter }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    var onSelectSuggestion: ((TyprKeyboardSuggestion) -> Void)?
    var onCodeFromMessages: (() -> Void)?
    var onUndoDictation: (() -> Void)?

    private let statusLabel = UILabel()
    private let undoChip = UIButton(type: .custom)
    private let slotButtons: [SlotButton] = [SlotButton(), SlotButton(), SlotButton()]
    private let codeChip = UIButton(type: .custom)
    private(set) var currentSuggestions: [TyprKeyboardSuggestion] = []
    private var statusText: String?
    private(set) var showsCodeChip = false
    private var showsUndo = false
    private var selection = KeyboardSuggestionSelection()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw

        statusLabel.font = .systemFont(ofSize: 13.5)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.8
        statusLabel.isHidden = true
        addSubview(statusLabel)

        var code = UIButton.Configuration.plain()
        code.image = UIImage(
            systemName: "keyboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        )
        code.imagePadding = 6
        code.title = "Code from Messages"
        code.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        code.background.cornerRadius = 15
        codeChip.configuration = code
        codeChip.accessibilityHint = "Switches to Apple's keyboard, where iOS offers codes from Messages and Mail"
        codeChip.isHidden = true
        codeChip.addTarget(self, action: #selector(handleCodeChip), for: .touchUpInside)
        addSubview(codeChip)

        var chip = UIButton.Configuration.plain()
        chip.image = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        )
        chip.imagePadding = 6
        chip.title = "Undo dictation"
        chip.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        chip.background.cornerRadius = 15
        undoChip.configuration = chip
        undoChip.isHidden = true
        undoChip.addTarget(self, action: #selector(handleUndo), for: .touchUpInside)
        addSubview(undoChip)

        for (index, button) in slotButtons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(handleSlotDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(handleSlotTap(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(handleSlotCancel(_:)), for: [.touchCancel, .touchUpOutside])
            button.onAccessibilityActivate = { [weak self] in self?.activateSlot(index) ?? false }
            button.isHidden = true
            addSubview(button)
        }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `showsUndo` puts the `Undo dictation` chip in place of the slots and any status. Otherwise
    /// the Code from Messages chip replaces the suggestions; a status message wins over it.
    func update(suggestions: [TyprKeyboardSuggestion], statusText: String?, showsCodeChip: Bool = false, showsUndo: Bool = false) {
        let showsCodeChip = showsCodeChip && statusText == nil && !showsUndo
        guard suggestions != currentSuggestions || statusText != self.statusText || showsCodeChip != self.showsCodeChip
            || showsUndo != self.showsUndo else { return }
        currentSuggestions = suggestions
        if suggestions.isEmpty { selection = KeyboardSuggestionSelection() }
        self.statusText = statusText
        self.showsCodeChip = showsCodeChip
        self.showsUndo = showsUndo
        codeChip.isHidden = !showsCodeChip
        undoChip.isHidden = !showsUndo

        if showsUndo || showsCodeChip {
            statusLabel.isHidden = true
            slotButtons.forEach { $0.isHidden = true }
        } else if let statusText, suggestions.isEmpty {
            statusLabel.text = statusText
            statusLabel.isHidden = false
            slotButtons.forEach { $0.isHidden = true }
        } else {
            statusLabel.isHidden = true
            for (idx, button) in slotButtons.enumerated() {
                if idx < suggestions.count {
                    button.configure(with: suggestions[idx], palette: palette)
                    button.isHidden = false
                } else {
                    button.isHidden = true
                }
            }
        }
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func applyPalette() {
        statusLabel.textColor = palette.textMuted
        var code = codeChip.configuration
        code?.baseForegroundColor = palette.textMuted
        code?.background.backgroundColor = palette.chipFill
        codeChip.configuration = code
        var chip = undoChip.configuration
        chip?.baseForegroundColor = palette.textMuted
        chip?.background.backgroundColor = palette.chipFill
        undoChip.configuration = chip
        for (idx, button) in slotButtons.enumerated() where idx < currentSuggestions.count {
            button.configure(with: currentSuggestions[idx], palette: palette)
        }
        setNeedsDisplay()
    }

    private var contentCenterY: CGFloat {
        inSystemPlatter ? bounds.height * 0.42 : bounds.height * 0.50
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let midY = contentCenterY
        statusLabel.frame = CGRect(x: 16, y: max(0, midY - 12), width: max(0, bounds.width - 32), height: 24)
        let undoH = min(30, max(18, bounds.height - 6))
        let undoW = min(bounds.width, undoChip.sizeThatFits(CGSize(width: bounds.width, height: undoH)).width)
        undoChip.frame = CGRect(x: (bounds.width - undoW) / 2, y: max(0, midY - undoH / 2), width: undoW, height: undoH)
        let widths = slotWidths
        var x: CGFloat = 0
        for (idx, button) in slotButtons.enumerated() {
            button.inSystemPlatter = inSystemPlatter
            button.frame = CGRect(x: x, y: 0, width: widths[idx], height: bounds.height)
            x += widths[idx]
        }
        let chipH = min(30, max(22, bounds.height - 6))
        let chipW = min(bounds.width, codeChip.sizeThatFits(CGSize(width: bounds.width, height: chipH)).width)
        codeChip.frame = CGRect(
            x: max(0, min(bounds.width - chipW, bounds.midX - chipW / 2)),
            y: max(0, midY - chipH / 2),
            width: chipW,
            height: chipH
        )
    }

    private var slotWidths: [CGFloat] {
        let wanted = (0..<3).map { idx in
            idx < currentSuggestions.count ? Self.wantedWidth(for: currentSuggestions[idx]) : 0
        }
        return SuggestionSlotLayout.widths(total: bounds.width, wanted: wanted)
    }

    static func wantedWidth(for suggestion: TyprKeyboardSuggestion) -> CGFloat { SlotButton.wantedWidth(for: suggestion) }

    override func draw(_ rect: CGRect) {
        guard !showsUndo, statusLabel.isHidden, !showsCodeChip, bounds.width > 60 else { return }
        let scale = max(1, traitCollection.displayScale)
        let hairline = 1 / scale
        // 18.5 pt dividers, as in the owner's 2026-11-11 reference.
        let lineH: CGFloat = min(18.5, bounds.height * 0.56)
        let y = max(1, contentCenterY - lineH / 2)
        let widths = slotWidths

        palette.separator.setFill()
        UIRectFill(CGRect(x: widths[0].rounded() - hairline / 2, y: y, width: hairline, height: lineH))
        UIRectFill(CGRect(x: (widths[0] + widths[1]).rounded() - hairline / 2, y: y, width: hairline, height: lineH))
    }

    /// Empty space passes through, so `TyprFullKeyboardView` (never hidden) owns a hold there even
    /// after the recording panel hides this strip; words and chips keep their touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    @objc private func handleCodeChip() {
        onCodeFromMessages?()
    }

    @objc private func handleUndo() {
        onUndoDictation?()
    }

    @objc private func handleSlotDown(_ sender: SlotButton) {
        selection.begin(slot: sender.tag, suggestions: currentSuggestions)
    }

    @objc private func handleSlotTap(_ sender: SlotButton) {
        guard let suggestion = selection.finish(slot: sender.tag) else { return }
        onSelectSuggestion?(suggestion) // Engine revalidates its original token/field ownership.
    }

    @objc private func handleSlotCancel(_ sender: SlotButton) {
        selection.cancel(slot: sender.tag)
    }

    private func activateSlot(_ slot: Int) -> Bool {
        guard currentSuggestions.indices.contains(slot) else { return false }
        selection.cancel(slot: slot)
        onSelectSuggestion?(currentSuggestions[slot])
        return true
    }

    private final class SlotButton: UIControl {
        var onAccessibilityActivate: (() -> Bool)?
        var inSystemPlatter = true { didSet { if inSystemPlatter != oldValue { setNeedsDisplay() } } }
        private var suggestion: TyprKeyboardSuggestion?
        private var palette = TyprFullKeyboardPalette(isDark: false)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            contentMode = .redraw
            isAccessibilityElement = true
            accessibilityTraits = .button
            addTarget(self, action: #selector(redraw), for: [.touchDown, .touchDragEnter, .touchDragExit, .touchCancel, .touchUpInside, .touchUpOutside])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var isHighlighted: Bool { didSet { if isHighlighted != oldValue { setNeedsDisplay() } } }

        func configure(with suggestion: TyprKeyboardSuggestion, palette: TyprFullKeyboardPalette) {
            self.suggestion = suggestion
            self.palette = palette
            accessibilityLabel = suggestion.kind == .revert ? "Revert to \(suggestion.displayText)" : suggestion.displayText
            setNeedsDisplay()
        }

        override func accessibilityActivate() -> Bool {
            onAccessibilityActivate?() ?? false
        }

        @objc private func redraw() { setNeedsDisplay() }

        static func font(for suggestion: TyprKeyboardSuggestion) -> UIFont {
            .systemFont(ofSize: 15.5, weight: suggestion.willAutoReplace || suggestion.kind == .revert ? .medium : .regular)
        }

        static func wantedWidth(for suggestion: TyprKeyboardSuggestion) -> CGFloat {
            let text = (suggestion.displayText as NSString).size(withAttributes: [.font: font(for: suggestion)]).width
            return ceil(text) + (suggestion.kind == .revert ? 15 : 0) + textMargin
        }

        private static let textMargin: CGFloat = 22

        override func draw(_ rect: CGRect) {
            guard let suggestion else { return }
            let midY = inSystemPlatter ? bounds.height * 0.42 : bounds.height * 0.50
            let pillH = min(26, max(22, bounds.height - 6))
            let pillInset = CGRect(
                x: 5,
                y: max(0.5, midY - pillH / 2),
                width: max(0, bounds.width - 10),
                height: pillH
            )
            let isLiteral = suggestion.kind == .keepLiteral
            let isRevert = suggestion.kind == .revert
            let font = Self.font(for: suggestion)
            let ink = isLiteral && !suggestion.willAutoReplace ? palette.textBase.withAlphaComponent(0.88) : palette.textBase
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ink,
            ]
            let arrow = isRevert ? UIImage(systemName: "arrow.uturn.backward",
                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))?
                .withTintColor(ink, renderingMode: .alwaysOriginal) : nil
            let arrowW = arrow.map { $0.size.width + 4 } ?? 0
            let textW = (suggestion.displayText as NSString).size(withAttributes: attributes).width
            let marked = suggestion.willAutoReplace || isRevert
            let chipH: CGFloat = 22
            let chip = marked ? CGRect(
                x: max(pillInset.minX, bounds.midX - (textW + arrowW + 20) / 2),
                y: max(0.5, midY - chipH / 2),
                width: min(pillInset.width, textW + arrowW + 20),
                height: chipH
            ) : pillInset
            if isHighlighted {
                palette.keyPressedFill.setFill()
                UIBezierPath(roundedRect: chip, cornerRadius: marked ? chipH / 2 : 8).fill()
            } else if marked {
                palette.selectFill.setFill()
                UIBezierPath(roundedRect: chip, cornerRadius: chipH / 2).fill()
            }
            if let arrow {
                let x = max(chip.minX + 6, bounds.midX - (textW + arrowW) / 2)
                arrow.draw(at: CGPoint(x: x, y: midY - arrow.size.height / 2))
            }

            let maxTextW = max(20, pillInset.width - 12 - arrowW)
            var drawString = suggestion.displayText
            var size = (drawString as NSString).size(withAttributes: attributes)
            if size.width > maxTextW {
                let smallAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: suggestion.willAutoReplace || isRevert ? .medium : .regular),
                    .foregroundColor: ink,
                ]
                size = (drawString as NSString).size(withAttributes: smallAttrs)
                let drawRect = CGRect(
                    x: bounds.midX + arrowW / 2 - min(maxTextW, size.width) / 2,
                    y: midY - size.height / 2,
                    width: min(maxTextW, size.width),
                    height: size.height
                )
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                style.alignment = .center
                var truncatedAttrs = smallAttrs
                truncatedAttrs[.paragraphStyle] = style
                (drawString as NSString).draw(in: drawRect, withAttributes: truncatedAttrs)
                return
            }
            drawString = suggestion.displayText
            (drawString as NSString).draw(
                at: CGPoint(x: bounds.midX + arrowW / 2 - size.width / 2, y: midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}
