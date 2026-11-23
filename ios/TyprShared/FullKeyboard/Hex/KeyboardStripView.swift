import UIKit

@MainActor
final class KeyboardStripView: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    var textCenterY: CGFloat? {
        didSet {
            guard textCenterY != oldValue else { return }
            for button in slotButtons { button.textCenterY = textCenterY }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    var chipHeight = KeyboardMetrics.typrStripPillHeight {
        didSet {
            guard chipHeight != oldValue else { return }
            for button in slotButtons { button.chipHeight = chipHeight }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    var onSelectSuggestion: ((KeyboardSuggestion) -> Void)?
    var onHoldSuggestion: ((KeyboardSuggestion) -> Void)?
    var onUndoDictation: (() -> Void)?
    var onPaste: (() -> Void)?
    var onNextKeyboard: (() -> Void)?
    var onOpenTyprFromHint: (() -> Void)?
    var onOpenNotice: (() -> Void)?

    private let statusLabel = UILabel()
    private let undoChip = UIButton(type: .custom)
    private let slotButtons: [SlotButton] = [SlotButton(), SlotButton(), SlotButton()]
    private var currentSuggestions: [KeyboardSuggestion] = []
    private var showsUndo = false
    private var statusText: String?
    private var clipboard: KeyboardClipboardOffer?
    private var showsFullAccessHint = false
    private var fullAccessHintView: FullAccessHintView?
    private var notice: KeyboardStripNotice?
    private var noticeView: FullAccessHintView?
    var hexOnLeading = false {
        didSet {
            guard hexOnLeading != oldValue else { return }
            fullAccessHintView?.chipLeads = hexOnLeading
            noticeView?.chipLeads = hexOnLeading
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    var showsLoggingMark = false {
        didSet {
            guard showsLoggingMark != oldValue else { return }
            if showsLoggingMark, loggingMark == nil {
                let mark = TypingLogMarkView()
                mark.textColor = palette.textMuted
                addSubview(mark)
                loggingMark = mark
            }
            loggingMark?.isHidden = !showsLoggingMark
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    private var loggingMark: TypingLogMarkView?
    var barMidX: CGFloat? { didSet { if barMidX != oldValue { setNeedsLayout() } } }
    // UIPasteControl renders blank inside a keyboard extension. The host reads on tap.
    private let pasteControl = UIButton(type: .custom)
    private let nextKeyboardChip = UIButton(type: .custom)

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

        var chip = UIButton.Configuration.plain()
        chip.image = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        )
        chip.imagePadding = 6
        chip.title = String(localized: "Undo dictation")
        chip.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        chip.background.cornerRadius = 15
        undoChip.configuration = chip
        undoChip.isHidden = true
        undoChip.addTarget(self, action: #selector(handleUndo), for: .touchUpInside)
        var paste = UIButton.Configuration.plain()
        paste.image = UIImage(
            systemName: "doc.on.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(font: Self.pasteFont, scale: .small)
        )
        paste.imagePadding = 5
        paste.title = String(localized: "Paste")
        paste.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Self.pasteFont
            return attributes
        }
        paste.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        paste.background.backgroundColor = .clear
        pasteControl.configuration = paste
        pasteControl.isHidden = true
        pasteControl.addTarget(self, action: #selector(handlePaste), for: .touchUpInside)
        addSubview(pasteControl)
        addSubview(undoChip)

        var next = UIButton.Configuration.plain()
        next.image = UIImage(
            systemName: "keyboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        )
        next.imagePadding = 6
        next.title = String(localized: "Code from Messages")
        next.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        next.background.cornerRadius = 15
        nextKeyboardChip.configuration = next
        nextKeyboardChip.accessibilityHint = String(localized: "Switches to the next keyboard, where iOS offers codes from Messages and Mail")
        nextKeyboardChip.isHidden = true
        nextKeyboardChip.addTarget(self, action: #selector(handleNextKeyboard), for: .touchUpInside)
        addSubview(nextKeyboardChip)

        for (index, button) in slotButtons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(handleSlotTap(_:)), for: .touchUpInside)
            button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleSlotHold(_:))))
            addSubview(button)
        }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let pasteFont = UIFont.systemFont(ofSize: 17, weight: .regular)

    func update(
        suggestions: [KeyboardSuggestion],
        showsUndo: Bool,
        statusText: String?,
        clipboard: KeyboardClipboardOffer? = nil,
        fullAccessHint: Bool = false,
        notice: KeyboardStripNotice? = nil,
        hidesWordSuggestions: Bool = false
    ) {
        let suggestions = hidesWordSuggestions ? suggestions.filter { $0.kind == .revert } : suggestions
        let changed = suggestions != currentSuggestions || showsUndo != self.showsUndo
            || statusText != self.statusText || clipboard != self.clipboard
            || fullAccessHint != showsFullAccessHint || notice != self.notice
        guard changed else { return }
        currentSuggestions = suggestions
        self.showsUndo = showsUndo
        self.statusText = statusText
        self.clipboard = clipboard
        showsFullAccessHint = fullAccessHint
        self.notice = notice

        if fullAccessHint, fullAccessHintView == nil { makeFullAccessHintView() }
        if let hint = fullAccessHintView { show(hint, fullAccessHint) }
        if notice != nil, noticeView == nil { makeNoticeView() }
        if let notice { noticeView?.show(notice) }
        if let noticeView { show(noticeView, notice != nil && !fullAccessHint) }
        let showsHint = fullAccessHint || notice != nil
        show(undoChip, showsUndo && !showsHint)
        let showsClipboard = showsClipboard
        var paste = pasteControl.configuration
        let pasteTitle = clipboard == .dictation ? String(localized: "Paste dictation") : String(localized: "Paste")
        if paste?.title != pasteTitle {
            paste?.title = pasteTitle
            pasteControl.configuration = paste
        }
        show(pasteControl, showsPasteChip)
        show(nextKeyboardChip, showsNextKeyboardChip)
        let animated = window != nil
        if showsHint || showsUndo || showsClipboard {
            statusLabel.isHidden = true
            slotButtons.forEach { $0.configure(with: nil, animated: animated) }
        } else if let statusText, suggestions.isEmpty {
            statusLabel.text = statusText
            statusLabel.isHidden = false
            slotButtons.forEach { $0.configure(with: nil, animated: false) }
        } else {
            statusLabel.isHidden = true
            let slots = Self.slots(for: suggestions)
            for (idx, button) in slotButtons.enumerated() {
                let item = slots.firstIndex(of: idx).map { suggestions[$0] }
                button.configure(with: item, animated: animated)
            }
        }
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func show(_ view: UIView, _ shown: Bool) {
        let visible = !view.isHidden && view.alpha > 0
        guard shown != visible || (shown && view.alpha < 1) else { return }
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else {
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.isHidden = !shown
            return
        }
        if shown {
            if view.isHidden { view.alpha = 0 }
            view.isHidden = false
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            view.alpha = shown ? 1 : 0
        } completion: { _ in
            guard view.alpha == 0 else { return }
            view.isHidden = true
            view.alpha = 1
        }
    }

    static func slots(for suggestions: [KeyboardSuggestion]) -> [Int] {
        if suggestions.count == 1, ![.keepLiteral, .secondary, .revert].contains(suggestions[0].kind) { return [1] }
        return Array(suggestions.indices.prefix(3))
    }

    private var showsClipboard: Bool {
        guard let clipboard, !showsUndo, statusText == nil, !showsFullAccessHint, notice == nil else { return false }
        if case .code = clipboard { return true }
        return currentSuggestions.isEmpty
    }

    private var showsPasteChip: Bool {
        showsClipboard && clipboard != .code(canPaste: false)
    }

    private var showsNextKeyboardChip: Bool {
        guard showsClipboard, case .code = clipboard else { return false }
        return true
    }

    @objc private func handlePaste() {
        onPaste?()
    }

    @objc private func handleNextKeyboard() {
        onNextKeyboard?()
    }

    private func makeFullAccessHintView() {
        let hint = FullAccessHintView()
        hint.chipLeads = hexOnLeading
        hint.onOpenTypr = { [weak self] in self?.onOpenTyprFromHint?() }
        hint.isHidden = true
        addSubview(hint)
        fullAccessHintView = hint
        applyPalette()
        setNeedsLayout()
    }

    private func makeNoticeView() {
        let view = FullAccessHintView()
        view.chipLeads = hexOnLeading
        view.onOpenTypr = { [weak self] in self?.onOpenNotice?() }
        view.isHidden = true
        addSubview(view)
        noticeView = view
        applyPalette()
        setNeedsLayout()
    }

    private func applyPalette() {
        statusLabel.textColor = palette.textMuted
        var paste = pasteControl.configuration
        paste?.baseForegroundColor = palette.stripText
        pasteControl.configuration = paste
        var next = nextKeyboardChip.configuration
        next?.baseForegroundColor = palette.textMuted
        next?.background.backgroundColor = palette.chipFill
        nextKeyboardChip.configuration = next
        var chip = undoChip.configuration
        chip?.baseForegroundColor = palette.textMuted
        chip?.background.backgroundColor = palette.chipFill
        undoChip.configuration = chip
        fullAccessHintView?.palette = palette
        noticeView?.palette = palette
        loggingMark?.textColor = palette.textMuted
        for button in slotButtons { button.palette = palette }
        setNeedsDisplay()
    }

    private var contentCenterY: CGFloat {
        textCenterY ?? bounds.height * 0.5
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let midY = contentCenterY
        statusLabel.frame = CGRect(x: 16, y: max(0, midY - 12), width: max(0, bounds.width - 32), height: 24)
        let chipH = min(chipHeight, max(0, 2 * min(midY, bounds.height - midY)))
        let chipSize = undoChip.sizeThatFits(CGSize(width: bounds.width, height: chipH))
        undoChip.frame = CGRect(
            x: (bounds.width - chipSize.width) / 2,
            y: max(0, midY - chipH / 2),
            width: chipSize.width,
            height: chipH
        )
        let pasteW = pasteControl.sizeThatFits(CGSize(width: bounds.width, height: chipH)).width
        let nextSize = nextKeyboardChip.sizeThatFits(CGSize(width: bounds.width, height: chipH))
        let pasteShown = showsPasteChip
        let nextShown = showsNextKeyboardChip
        let pair = pasteShown && nextShown
        let gap: CGFloat = 8
        let total = pair ? pasteW + gap + nextSize.width : (pasteShown ? pasteW : nextSize.width)
        let midX = barMidX ?? bounds.width / 2
        let startX = max(0, min(bounds.width - total, midX - total / 2))
        let chipY = max(0, midY - chipH / 2)
        pasteControl.frame = CGRect(x: startX, y: chipY, width: pasteW, height: chipH)
        nextKeyboardChip.frame = CGRect(
            x: pair ? startX + pasteW + gap : startX,
            y: chipY,
            width: nextSize.width,
            height: chipH
        )
        let hintHalf = min(midY, bounds.height - midY)
        let hintY = midY - hintHalf
        var hintFrame = CGRect(x: 12, y: hintY, width: max(0, bounds.width - 24), height: 2 * hintHalf)
        if let loggingMark, showsLoggingMark {
            let size = loggingMark.sizeThatFits(bounds.size)
            let markX = hexOnLeading ? bounds.width - 12 - size.width : 12
            loggingMark.frame = CGRect(x: markX, y: (midY - size.height / 2).rounded(), width: size.width, height: size.height)
            bringSubviewToFront(loggingMark)
            hintFrame = hexOnLeading
                ? CGRect(x: 12, y: hintY, width: max(0, loggingMark.frame.minX - 8 - 12), height: 2 * hintHalf)
                : CGRect(x: loggingMark.frame.maxX + 8, y: hintY, width: max(0, bounds.width - loggingMark.frame.maxX - 20), height: 2 * hintHalf)
        }
        fullAccessHintView?.frame = hintFrame
        fullAccessHintView?.chipHeight = chipH
        noticeView?.frame = hintFrame
        noticeView?.chipHeight = chipH
        for (index, frame) in currentSlotFrames.enumerated() {
            let button = slotButtons[index]
            button.frame = frame
            button.leadingRoom = !hexOnLeading && index == 0 ? loggingMarkRoom : 0
            button.trailingRoom = hexOnLeading && index == 2 ? loggingMarkRoom : 0
        }
    }

    private var loggingMarkRoom: CGFloat {
        guard showsLoggingMark, let loggingMark else { return 0 }
        return 16 + loggingMark.sizeThatFits(bounds.size).width
    }

    private var currentSlotFrames: [CGRect] {
        var wanted: [CGFloat] = [0, 0, 0]
        for (suggestion, slot) in zip(currentSuggestions, Self.slots(for: currentSuggestions)) {
            wanted[slot] = Self.wantedWidth(for: suggestion)
        }
        wanted[hexOnLeading ? 2 : 0] += loggingMarkRoom
        let widths = SuggestionSlotLayout.widths(total: bounds.width, wanted: wanted)
        var x: CGFloat = 0
        return widths.map { width in
            let frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
            return frame
        }
    }

    static func wantedWidth(for suggestion: KeyboardSuggestion) -> CGFloat {
        SlotButton.wantedWidth(for: suggestion)
    }

    override func draw(_ rect: CGRect) {
        guard !showsUndo, !showsClipboard, !showsFullAccessHint, notice == nil, statusLabel.isHidden, bounds.width > 60 else { return }
        let reverting = currentSuggestions.first?.kind == .revert

        let lineH: CGFloat = min(24, bounds.height - 2, chipHeight, 2 * contentCenterY)
        let y = contentCenterY - lineH / 2
        palette.stripDivider.setFill()
        let filled = Set(Self.slots(for: currentSuggestions))
        for (index, slot) in currentSlotFrames.prefix(2).enumerated()
        where slot.maxX < bounds.width - 1 && filled.contains(index) && filled.contains(index + 1) && !(reverting && index == 0) {
            UIRectFill(CGRect(x: slot.maxX - 1, y: y, width: 1, height: lineH))
        }
    }

    @objc private func handleUndo() {
        onUndoDictation?()
    }

    @objc private func handleSlotTap(_ sender: SlotButton) {
        guard let item = Self.slots(for: currentSuggestions).firstIndex(of: sender.tag) else { return }
        onSelectSuggestion?(currentSuggestions[item])
    }

    @objc private func handleSlotHold(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let slot = recognizer.view?.tag,
              let item = Self.slots(for: currentSuggestions).firstIndex(of: slot) else { return }
        onHoldSuggestion?(currentSuggestions[item])
    }

    private final class SlotButton: UIControl {
        var textCenterY: CGFloat? { didSet { if textCenterY != oldValue { setNeedsDisplay() } } }
        var chipHeight = KeyboardMetrics.typrStripPillHeight { didSet { if chipHeight != oldValue { setNeedsDisplay() } } }
        var leadingRoom: CGFloat = 0 { didSet { if leadingRoom != oldValue { setNeedsDisplay() } } }
        var trailingRoom: CGFloat = 0 { didSet { if trailingRoom != oldValue { setNeedsDisplay() } } }
        private var suggestion: KeyboardSuggestion?
        var palette = FullKeyboardPalette(isDark: false) { didSet { setNeedsDisplay() } }
        private var outgoing: KeyboardSuggestion?
        private var swapStart: CFTimeInterval = 0
        private var displayLink: CADisplayLink?

        static let letterFade: CFTimeInterval = 0.1
        static let swapLength: CFTimeInterval = 0.2
        static let maxStagger: CFTimeInterval = 0.025

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            contentMode = .redraw
            isAccessibilityElement = false
            isUserInteractionEnabled = false
            accessibilityTraits = .button
            addTarget(self, action: #selector(redraw), for: [.touchDown, .touchDragEnter, .touchDragExit, .touchCancel, .touchUpInside, .touchUpOutside])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var isHighlighted: Bool { didSet { if isHighlighted != oldValue { setNeedsDisplay() } } }

        func configure(with suggestion: KeyboardSuggestion?, animated: Bool) {
            let old = self.suggestion
            self.suggestion = suggestion
            isAccessibilityElement = suggestion != nil
            isUserInteractionEnabled = suggestion != nil
            accessibilityLabel = suggestion?.displayText
            accessibilityHint = suggestion?.kind == .revert ? String(localized: "Undoes the autocorrection") : nil
            if old?.displayText != suggestion?.displayText {
                if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
                    outgoing = old
                    swapStart = CACurrentMediaTime()
                    startTicking()
                } else {
                    endSwap()
                }
            }
            setNeedsDisplay()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { endSwap() }
        }

        private func startTicking() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func endSwap() {
            outgoing = nil
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick() {
            if CACurrentMediaTime() - swapStart >= Self.swapLength { endSwap() }
            setNeedsDisplay()
        }

        @objc private func redraw() { setNeedsDisplay() }

        private struct Word {
            let text: String
            let attributes: [NSAttributedString.Key: Any]
            let origin: CGPoint
            let truncatedRect: CGRect?
        }

        private static let textMargin: CGFloat = 12

        private static func font(for suggestion: KeyboardSuggestion) -> UIFont {
            .systemFont(ofSize: suggestion.kind == .emoji ? 22 : 17, weight: .regular)
        }

        private static func arrowRoom(for suggestion: KeyboardSuggestion) -> CGFloat {
            suggestion.kind == .revert ? revertArrowSize + revertArrowGap : 0
        }

        static func wantedWidth(for suggestion: KeyboardSuggestion) -> CGFloat {
            let text = (suggestion.displayText as NSString).size(withAttributes: [.font: font(for: suggestion)]).width
            return ceil(text) + textMargin + arrowRoom(for: suggestion)
        }

        private func layout(_ suggestion: KeyboardSuggestion, ink: UIColor) -> Word {
            let midY = textCenterY ?? bounds.height * 0.5
            let font = Self.font(for: suggestion)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let arrowRoom = Self.arrowRoom(for: suggestion)
            let textMidX = (leadingRoom + bounds.width - trailingRoom - arrowRoom) / 2
            let maxTextW = max(0, bounds.width - Self.textMargin - leadingRoom - trailingRoom - arrowRoom)
            let text = suggestion.displayText
            let size = (text as NSString).size(withAttributes: attributes)
            guard size.width > maxTextW else {
                let origin = CGPoint(x: textMidX - size.width / 2, y: midY - size.height / 2)
                return Word(text: text, attributes: attributes, origin: origin, truncatedRect: nil)
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = .center
            let small: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular), .foregroundColor: ink, .paragraphStyle: style,
            ]
            let smallSize = (text as NSString).size(withAttributes: small)
            let width = min(maxTextW, smallSize.width)
            let box = CGRect(x: textMidX - width / 2, y: midY - smallSize.height / 2, width: width, height: smallSize.height)
            return Word(text: text, attributes: small, origin: box.origin, truncatedRect: box)
        }

        private func draw(_ word: Word, alpha: (Int) -> CGFloat) {
            let ink = word.attributes[.foregroundColor] as? UIColor ?? .label
            if let box = word.truncatedRect {
                var attributes = word.attributes
                attributes[.foregroundColor] = ink.withAlphaComponent(ink.cgColor.alpha * max(0, alpha(0)))
                (word.text as NSString).draw(in: box, withAttributes: attributes)
                return
            }
            let string = NSMutableAttributedString(string: word.text, attributes: word.attributes)
            var offset = 0
            for (index, character) in word.text.enumerated() {
                let length = String(character).utf16.count
                let a = alpha(index)
                if a < 1 {
                    let faded = ink.withAlphaComponent(ink.cgColor.alpha * max(0, a))
                    string.addAttribute(.foregroundColor, value: faded, range: NSRange(location: offset, length: length))
                }
                offset += length
            }
            string.draw(at: word.origin)
        }

        private static func progress(_ t: CFTimeInterval, start: CFTimeInterval) -> CGFloat {
            let x = min(1, max(0, (t - start) / letterFade))
            return CGFloat(x * x * (3 - 2 * x))
        }

        static let chipPadding: CGFloat = 12
        static let revertArrowSize: CGFloat = 13
        static let revertArrowGap: CGFloat = 5

        private func drawRevertArrow(after word: Word, ink: UIColor) {
            let config = UIImage.SymbolConfiguration(pointSize: Self.revertArrowSize, weight: .medium)
            guard let arrow = UIImage(systemName: "arrow.uturn.backward", withConfiguration: config)?
                .withTintColor(ink, renderingMode: .alwaysOriginal) else { return }
            let textWidth = word.truncatedRect?.width ?? (word.text as NSString).size(withAttributes: word.attributes).width
            let x = word.origin.x + textWidth + Self.revertArrowGap
            arrow.draw(at: CGPoint(x: x, y: (textCenterY ?? bounds.height * 0.5) - arrow.size.height / 2))
        }

        override func draw(_ rect: CGRect) {
            let pilled = suggestion.map { isHighlighted || $0.willAutoReplace || $0.kind == .revert } ?? false
            let ink = pilled ? palette.stripPillText : palette.stripText
            let incoming = suggestion.map { layout($0, ink: ink) }
            if pilled, let incoming, let suggestion {
                let textW = incoming.truncatedRect?.width ?? (incoming.text as NSString).size(withAttributes: incoming.attributes).width
                let arrowRoom = Self.arrowRoom(for: suggestion)
                let midY = textCenterY ?? bounds.height * 0.5
                let chipH = min(chipHeight, max(0, 2 * min(midY, bounds.height - midY)))
                let chipW = min(bounds.width, textW + arrowRoom + 2 * Self.chipPadding)
                let chip = CGRect(
                    x: max(0, min(bounds.width - chipW, incoming.origin.x - (chipW - textW - arrowRoom) / 2)),
                    y: midY - chipH / 2,
                    width: chipW,
                    height: chipH
                )
                (isHighlighted ? palette.stripPillPressedFill : palette.stripPillFill).setFill()
                UIBezierPath(roundedRect: chip, cornerRadius: chipH / 2).fill()
            }
            if let incoming, suggestion?.kind == .revert { drawRevertArrow(after: incoming, ink: ink) }
            guard var leaving = outgoing.map({ layout($0, ink: ink) }) else {
                if let incoming { draw(incoming) { _ in 1 } }
                return
            }
            let t = CACurrentMediaTime() - swapStart
            let oldLetters = Array(leaving.text)
            let newLetters = Array(incoming?.text ?? "")
            let byLetter = leaving.truncatedRect == nil && incoming?.truncatedRect == nil
            var shared = 0
            if byLetter, incoming != nil {
                while shared < min(oldLetters.count, newLetters.count), oldLetters[shared] == newLetters[shared] {
                    shared += 1
                }
            }
            if shared > 0, let incoming {
                leaving = Word(text: leaving.text, attributes: leaving.attributes, origin: incoming.origin, truncatedRect: nil)
            }
            let changing = max(oldLetters.count, newLetters.count) - shared
            let stagger = changing > 1 ? min(Self.maxStagger, (Self.swapLength - Self.letterFade) / Double(changing - 1)) : 0
            draw(leaving) { index in
                guard index >= shared else { return 0 }
                guard byLetter else { return 1 - Self.progress(t, start: 0) }
                return 1 - Self.progress(t, start: Double(oldLetters.count - 1 - index) * stagger)
            }
            if let incoming {
                draw(incoming) { index in
                    guard index >= shared else { return 1 }
                    guard byLetter else { return Self.progress(t, start: 0) }
                    return Self.progress(t, start: Double(index - shared) * stagger)
                }
            }
        }
    }
}

struct KeyboardStripNotice: Equatable {
    let title: String
    let detail: String
    let button: String
}

@MainActor
final class FullAccessHintView: UIView {
    static let title = String(localized: "Allow Full Access to dictate")
    static let path = String(localized: "Settings › Apps › Typr › Keyboards")
    static let spokenPath = String(localized: "Settings, Apps, Typr, Keyboards")

    var palette = FullKeyboardPalette(isDark: false) { didSet { applyPalette() } }
    var chipHeight: CGFloat = 30 { didSet { setNeedsLayout() } }
    var chipLeads = false { didSet { if chipLeads != oldValue { setNeedsLayout() } } }
    var onOpenTypr: (() -> Void)?

    private let titleLabel = UILabel()
    private let pathLabel = UILabel()
    private let openButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        titleLabel.text = Self.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pathLabel.text = Self.path
        pathLabel.font = .systemFont(ofSize: 11.5)
        pathLabel.accessibilityLabel = Self.spokenPath
        for label in [titleLabel, pathLabel] {
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        var open = UIButton.Configuration.plain()
        open.title = String(localized: "Open Typr")
        open.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        open.background.cornerRadius = 15
        openButton.configuration = open
        openButton.accessibilityHint = String(localized: "Opens Typr setup")
        openButton.addTarget(self, action: #selector(handleOpen), for: .touchUpInside)
        addSubview(openButton)
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleOpen() {
        onOpenTypr?()
    }

    func show(_ notice: KeyboardStripNotice) {
        titleLabel.text = notice.title
        pathLabel.text = notice.detail
        pathLabel.accessibilityLabel = nil
        var open = openButton.configuration
        open?.title = notice.button
        openButton.configuration = open
        openButton.accessibilityHint = nil
        setNeedsLayout()
    }

    private func applyPalette() {
        titleLabel.textColor = palette.textBase
        pathLabel.textColor = palette.textMuted
        var open = openButton.configuration
        open?.baseForegroundColor = palette.textBase
        open?.background.backgroundColor = palette.chipFill
        openButton.configuration = open
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let buttonWidth = openButton.sizeThatFits(CGSize(width: bounds.width, height: chipHeight)).width
        openButton.frame = CGRect(
            x: chipLeads ? 0 : bounds.width - buttonWidth,
            y: (bounds.height - chipHeight) / 2,
            width: buttonWidth,
            height: chipHeight
        )
        let textX = chipLeads ? openButton.frame.maxX + 10 : 0
        let textWidth = chipLeads ? max(0, bounds.width - textX) : max(0, openButton.frame.minX - 10)
        let lineHeight: CGFloat = min(16, (bounds.height + 1) / 2)
        let top = (bounds.height - 2 * lineHeight) / 2
        titleLabel.frame = CGRect(x: textX, y: top, width: textWidth, height: lineHeight)
        pathLabel.frame = CGRect(x: textX, y: top + lineHeight, width: textWidth, height: lineHeight)
    }
}

@MainActor
final class TypingLogMarkView: UIView {
    static let text = "Logging"
    static let accessibilityText = "Typing logs are recording"

    var textColor: UIColor = .secondaryLabel {
        didSet {
            label.textColor = textColor
            dot.backgroundColor = textColor
        }
    }

    private let dot = UIView()
    private let label = UILabel()
    private static let dotSize: CGFloat = 5
    private static let gap: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = Self.accessibilityText
        dot.backgroundColor = textColor
        dot.layer.cornerRadius = Self.dotSize / 2
        label.text = Self.text
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = textColor
        addSubview(dot)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(size)
        return CGSize(width: Self.dotSize + Self.gap + ceil(text.width), height: max(Self.dotSize, ceil(text.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dot.frame = CGRect(x: 0, y: (bounds.height - Self.dotSize) / 2, width: Self.dotSize, height: Self.dotSize)
        label.frame = CGRect(x: Self.dotSize + Self.gap, y: 0, width: max(0, bounds.width - Self.dotSize - Self.gap), height: bounds.height)
    }
}
