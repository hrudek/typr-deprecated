import UIKit

/// The Typr key right of space. Warm session: an orange mark, and a hold records here.
/// Otherwise the mark shows ↗ (faded in light), and a hold leaves for Typr to start one.
/// A tap types a space; sliding up opens the style menu and, with the switch key on,
/// sliding down shows the compact dictation bar (`TyprKeyGesture`).
@MainActor
final class TyprKeyControl: UIControl {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { setNeedsDisplay() } } }
    var isWarm = false { didSet { if isWarm != oldValue { setNeedsDisplay(); updateAccessibility() } } }
    var cornerRadius: CGFloat = FullKeyboardPalette.cornerRadius { didSet { if cornerRadius != oldValue { setNeedsDisplay() } } }
    /// The drawn keycap inside the control's (larger) touch target.
    var keycapFrame: CGRect = .zero { didSet { if keycapFrame != oldValue { setNeedsDisplay() } } }

    /// The key plane supplies the shared background; this control keeps its original target.
    var joinsSpace = false { didSet { if joinsSpace != oldValue { setNeedsDisplay() } } }

    /// Typr: a downward slide shows the compact dictation bar.
    var allowsCompactBar = false { didSet { if allowsCompactBar != oldValue { updateAccessibility() } } }

    /// Touch-down: a warm session starts capturing now, so a hold dictates from this moment.
    var onArm: (() -> Void)?
    /// The touch ended, slid or was cancelled: drops an arming the hold did not commit.
    var onDisarm: (() -> Void)?
    /// A still hold: dictate, or open Typr.
    var onHold: (() -> Void)?
    /// Typr: a quick tap types a space.
    var onTap: (() -> Void)?
    /// Typr: a downward slide shows the compact dictation bar.
    var onShowCompactBar: (() -> Void)?
    /// Points are in this control's coordinates.
    var onMenuOpen: ((CGPoint) -> Void)?
    var onMenuDrag: ((CGPoint) -> Void)?
    var onMenuRelease: ((CGPoint) -> Void)?

    /// Drawing state only; the plane paints both connected key backgrounds.
    var onHighlightChanged: ((Bool) -> Void)?

    private var gesture = TyprKeyGesture()
    private var holdWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                setNeedsDisplay()
                onHighlightChanged?(isHighlighted)
            }
        }
    }

    private func updateAccessibility() {
        accessibilityLabel = isWarm ? "Dictate with Typr" : "Open Typr to dictate"
        accessibilityHint = allowsCompactBar
            ? "Tap for space, hold to dictate, slide up for styles, slide down for the dictation bar"
            : "Tap for space, hold to dictate, slide up for styles"
        var actions = [
            UIAccessibilityCustomAction(name: "Space") { [weak self] _ in
                self?.onTap?()
                return true
            },
            UIAccessibilityCustomAction(name: "Dictation styles") { [weak self] _ in
                guard let self else { return false }
                self.onMenuOpen?(CGPoint(x: self.bounds.midX, y: self.bounds.midY))
                return true
            },
        ]
        if allowsCompactBar {
            actions.append(UIAccessibilityCustomAction(name: "Show dictation bar") { [weak self] _ in
                self?.onShowCompactBar?()
                return true
            })
        }
        accessibilityCustomActions = actions
    }

    override func accessibilityActivate() -> Bool {
        onHold?()
        return true
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        gesture.touchDown(at: touch.location(in: self))
        isHighlighted = true
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.holdElapsed() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TyprKeyGesture.holdDuration, execute: work)
        onArm?()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        switch gesture.touchMoved(to: point, allowsCompactBar: allowsCompactBar) {
        case .showCompactBar:
            stopTimer()
            isHighlighted = false
            onDisarm?()
            onShowCompactBar?()
        case .openMenu:
            stopTimer()
            isHighlighted = false
            onDisarm?()
            onMenuOpen?(point)
        case .dragMenu:
            onMenuDrag?(point)
        default:
            break
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        stopTimer()
        isHighlighted = false
        onDisarm?()
        switch gesture.touchUp() {
        case .releaseMenu:
            if let touch { onMenuRelease?(touch.location(in: self)) }
        case .tap:
            onTap?()
        default:
            break
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        stopTimer()
        isHighlighted = false
        onDisarm?()
        gesture.cancel()
    }

    private func holdElapsed() {
        holdWork = nil
        guard gesture.holdElapsed() == .hold else { return }
        isHighlighted = false
        onHold?()
    }

    private func stopTimer() {
        holdWork?.cancel()
        holdWork = nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let cap = keycapFrame == .zero ? bounds : keycapFrame
        if !joinsSpace {
            context.fillKeycap(
                cap,
                palette: palette,
                fill: isHighlighted ? palette.keyPressedFill : palette.keyFill,
                radius: cornerRadius
            )
        }
        let isMechanical = palette.design == .mechanical
        let markRect = isMechanical ? MechanicalKeycap(isDark: palette.isDark).markFrame(in: cap) : TyprMarkPath.frame(in: cap)
        if isWarm {
            TyprMarkPath.draw(in: context, rect: markRect, color: palette.textBase, coreColor: palette.warmCore)
        } else {
            // Dark matches the reference: a white mark and a thin white ↗.
            let ink = isMechanical ? palette.keyGlyph : (palette.isDark ? palette.textBase : palette.textMuted)
            TyprMarkPath.draw(in: context, rect: markRect, color: ink, coreColor: nil)
            TyprMarkPath.drawArrow(in: context, rect: TyprMarkPath.arrowFrame(in: cap), color: ink)
        }
    }
}

/// While recording, this replaces the suggestion strip only, so the keys stay put: a Dot
/// Scope well that takes the rest of the strip, then ✕ and ✓, which turns into a spinner
/// while the recording is transcribed.
@MainActor
final class TyprKeyRecordingPanel: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    let scope: DotScopeHostView
    private let well = UIView()
    private let cancelButton = PanelKeyButton()
    private let doneButton = PanelKeyButton()
    private let doneSpinner = UIActivityIndicatorView(style: .medium)
    var horizontalInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    var metrics = KeyboardMetrics.portrait { didSet { setNeedsLayout() } }

    init(loudness: @escaping () -> Float) {
        var tuning = DotScopeTuning.bar(leadingInset: 0, trailingInset: 0, fade: 24, spacing: 5)
        tuning.height = Float(KeyboardMetrics.stripPillHeight)
        // Cap drawables at 2 inside the keyboard extension to save ~2.2 MB of IOSurface RAM.
        scope = DotScopeHostView(tuning: tuning, maximumDrawableCount: 2)
        super.init(frame: .zero)
        scope.drawPlate = false
        scope.loudnessProvider = loudness
        scope.reduceMotion = UIAccessibility.isReduceMotionEnabled
        scope.useDemoVoice = ProcessInfo.processInfo.arguments.contains("--snap-state")

        well.layer.cornerCurve = .continuous
        well.clipsToBounds = true
        well.addSubview(scope)

        cancelButton.symbol = "xmark"
        cancelButton.accessibilityLabel = "Cancel dictation"
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        doneButton.symbol = "checkmark"
        doneButton.accessibilityLabel = "Done"
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        doneSpinner.hidesWhenStopped = true
        doneSpinner.isUserInteractionEnabled = false
        for view in [well, cancelButton, doneButton, doneSpinner] {
            addSubview(view)
        }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func tearDown() {
        scope.phase = .hidden
        scope.tearDown()
    }

    func update(phase: DotScopePhase) {
        let isTranscribing = phase == .processing
        scope.phase = phase
        doneButton.symbol = isTranscribing ? nil : "checkmark"
        doneButton.isEnabled = !isTranscribing
        doneButton.accessibilityLabel = isTranscribing ? "Transcribing" : "Done"
        if isTranscribing { doneSpinner.startAnimating() } else { doneSpinner.stopAnimating() }
    }

    private func applyPalette() {
        well.backgroundColor = palette.wellFill
        scope.isDark = palette.isDark
        cancelButton.palette = palette
        doneButton.palette = palette
        doneSpinner.color = palette.textBase
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let innerLeft = horizontalInset + metrics.side
        let innerRight = bounds.width - horizontalInset - metrics.side
        let rowH = KeyboardMetrics.stripPillHeight
        let rowY = KeyboardMetrics.stripInset

        doneButton.cornerRadius = rowH / 2
        cancelButton.cornerRadius = rowH / 2
        doneButton.frame = CGRect(x: innerRight - rowH, y: rowY, width: rowH, height: rowH)
        cancelButton.frame = CGRect(x: doneButton.frame.minX - 6 - rowH, y: rowY, width: rowH, height: rowH)
        doneSpinner.center = CGPoint(x: doneButton.frame.midX, y: doneButton.frame.midY)
        well.frame = CGRect(x: innerLeft, y: rowY, width: max(24, cancelButton.frame.minX - 6 - innerLeft), height: rowH)
        well.layer.cornerRadius = rowH / 2
        scope.frame = well.bounds
    }

    @objc private func done() { onDone?() }
    @objc private func cancel() { onCancel?() }
}

/// A keycap-styled button for the recording panel.
@MainActor
final class PanelKeyButton: UIControl {
    var palette = FullKeyboardPalette(isDark: false) { didSet { setNeedsDisplay() } }
    var title: String? { didSet { setNeedsDisplay() } }
    var symbol: String? { didSet { setNeedsDisplay() } }
    var cornerRadius: CGFloat = FullKeyboardPalette.cornerRadius { didSet { setNeedsDisplay() } }

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

    var fill: UIColor { isHighlighted ? palette.keyPressedFill : palette.keyFill }

    override var isEnabled: Bool { didSet { setNeedsDisplay() } }
    @objc private func redraw() { setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.fillKeycap(bounds, palette: palette, fill: fill, radius: cornerRadius)
        let ink = isEnabled ? palette.keyGlyph : palette.textMuted
        if let symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 16.5, weight: .medium)
            if let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(ink, renderingMode: .alwaysOriginal) {
                image.draw(at: CGPoint(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2))
            }
        } else if let title {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16.5, weight: .semibold),
                .foregroundColor: ink,
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(
                at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}

/// Holding the Typr key: dictation styles.
@MainActor
final class TyprStyleMenuView: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { rebuild() } }
    var style: DictationStyle = .polished { didSet { rebuild() } }
    var onStyle: ((DictationStyle) -> Void)?
    var onDismiss: (() -> Void)?
    var onHoverChanged: (() -> Void)?
    /// The Typr key's keycap, in this view's coordinates; the panel opens above it.
    var anchor: CGRect = .zero { didSet { setNeedsLayout() } }

    private let panel = UIView()
    private var rows: [MenuRow] = []
    private var hoveredIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        panel.layer.cornerRadius = 13
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1 / 3.0
        panel.layer.shadowOffset = CGSize(width: 0, height: 4)
        panel.layer.shadowRadius = 12
        panel.layer.shadowOpacity = 1
        addSubview(panel)
        accessibilityViewIsModal = true
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Updates row highlight while the user holds the Typr key and slides into the menu (`point` in this view's coordinates).
    func updateDrag(at point: CGPoint) {
        let local = convert(point, to: panel)
        let nextIndex = rows.firstIndex { $0.frame.contains(local) }
        guard nextIndex != hoveredIndex else { return }
        hoveredIndex = nextIndex
        for (idx, row) in rows.enumerated() {
            row.isSlideHovered = (idx == nextIndex)
        }
        if nextIndex != nil {
            onHoverChanged?()
        }
    }

    /// Commits a hovered row if the hold-and-slide ended inside the panel; otherwise leaves the menu open for a tap.
    func finishDrag(at point: CGPoint) {
        let local = convert(point, to: panel)
        if let idx = rows.firstIndex(where: { $0.frame.contains(local) }) {
            hoveredIndex = nil
            rows[idx].trigger()
        } else {
            hoveredIndex = nil
            rows.forEach { $0.isSlideHovered = false }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A tap outside the panel closes the menu.
        if let touch = touches.first, !panel.frame.contains(touch.location(in: self)) {
            onDismiss?()
        }
    }

    private func rebuild() {
        panel.backgroundColor = palette.popupFill
        panel.layer.borderColor = palette.popupBorder.cgColor
        panel.layer.borderWidth = 1 / max(1, traitCollection.displayScale)
        panel.layer.shadowColor = palette.popupShadow.cgColor
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        for option in DictationStyle.allCases {
            rows.append(makeRow(title: option.label, selected: option == style) { [weak self] in
                self?.onStyle?(option)
            })
        }
        rows.forEach(panel.addSubview)
        setNeedsLayout()
    }

    private func makeRow(title: String, selected: Bool, action: @escaping () -> Void) -> MenuRow {
        MenuRow(palette: palette, title: title, selected: selected, onTrigger: action)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width: CGFloat = 224
        let padding: CGFloat = 5
        let available = max(80, anchor.minY - 6 - 4)
        let rowH = min(36, (available - 2 * padding) / CGFloat(max(1, rows.count)))
        let height = CGFloat(rows.count) * rowH + 2 * padding
        // Opens toward the middle of the keyboard: the Typr key sits right of space.
        let x = min(bounds.width - 6 - width, max(6, anchor.maxX - width))
        panel.frame = CGRect(x: x, y: max(2, anchor.minY - 6 - height), width: width, height: height)
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: padding, y: padding + CGFloat(i) * rowH, width: width - 2 * padding, height: rowH)
        }
    }

    private final class MenuRow: UIControl {
        private let palette: FullKeyboardPalette
        private let title: String
        private let isChosen: Bool
        private let onTrigger: () -> Void
        var isSlideHovered = false { didSet { if isSlideHovered != oldValue { setNeedsDisplay() } } }

        init(
            palette: FullKeyboardPalette,
            title: String,
            selected: Bool,
            onTrigger: @escaping () -> Void
        ) {
            self.palette = palette
            self.title = title
            self.isChosen = selected
            self.onTrigger = onTrigger
            super.init(frame: .zero)
            isOpaque = false
            backgroundColor = .clear
            contentMode = .redraw
            isAccessibilityElement = true
            accessibilityLabel = title
            accessibilityTraits = isChosen ? [.button, .selected] : .button
            addAction(UIAction { [weak self] _ in self?.onTrigger() }, for: .touchUpInside)
            addTarget(self, action: #selector(redraw), for: [.touchDown, .touchDragEnter, .touchDragExit, .touchCancel, .touchUpInside, .touchUpOutside])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func trigger() { onTrigger() }

        @objc private func redraw() { setNeedsDisplay() }

        override var isHighlighted: Bool {
            didSet { if isHighlighted != oldValue { setNeedsDisplay() } }
        }

        override func draw(_ rect: CGRect) {
            let activeHover = isHighlighted || isSlideHovered
            let lit = isChosen || activeHover
            if lit {
                let fill = activeHover ? palette.keyPressedFill : palette.selectFill
                fill.setFill()
                UIBezierPath(roundedRect: bounds, cornerRadius: 8.5).fill()
            }
            let ink = isChosen ? palette.selectText : palette.textBase
            let font = UIFont.systemFont(ofSize: 15.5, weight: isChosen ? .medium : .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: CGPoint(x: 12, y: bounds.midY - size.height / 2), withAttributes: attributes)

            if isChosen {
                let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                if let image = UIImage(systemName: "checkmark", withConfiguration: config)?
                    .withTintColor(ink, renderingMode: .alwaysOriginal) {
                    image.draw(at: CGPoint(
                        x: bounds.maxX - 12 - image.size.width,
                        y: bounds.midY - image.size.height / 2
                    ))
                }
            }
        }
    }
}
