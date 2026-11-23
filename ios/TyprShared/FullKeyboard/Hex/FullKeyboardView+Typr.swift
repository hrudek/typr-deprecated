import UIKit

/// Typr's strip geometry on the Hex keyboard (S2, #349): suggestions use the whole inset width
/// in every layout. Hex's `stripBarFrame` keeps a split keyboard's strip over one half.
extension FullKeyboardView {
    /// The strip with the Hex key's room, across the whole inset width.
    static func typrStripBarFrame(_ layout: KeyboardLayout) -> CGRect {
        let m = layout.metrics
        let inset = layout.horizontalInset
        return CGRect(x: inset, y: m.stripTop, width: layout.width - 2 * inset, height: m.stripHeight)
    }

    /// The strip up to the Hex key and its gap when the key sits in the strip, which a split
    /// keyboard puts at the outer end of its half.
    static func typrStripFrame(_ layout: KeyboardLayout) -> CGRect {
        let full = typrStripBarFrame(layout)
        guard let hex = layout.key(.hex), hex.row < 0 else { return full }
        let gap = layout.metrics.gap
        let minX = layout.hexOnLeading ? hex.frame.maxX + gap : full.minX
        let maxX = layout.hexOnLeading ? full.maxX : hex.frame.minX - gap
        return CGRect(x: minX, y: full.minY, width: max(0, maxX - minX), height: full.height)
    }
}

/// Typr's mechanical design and Hex's keyboard themes are never both active: the mechanical
/// design wins, and the Hex keyboard then keeps Automatic, whatever theme is stored.
extension FullKeyboardView {
    nonisolated static func typrKeyboardTheme(design: KeyboardDesign, hexTheme: KeyboardTheme) -> KeyboardTheme {
        design == .mechanical ? .automatic : hexTheme
    }

    static func typrKeyboardTheme(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) -> KeyboardTheme {
        typrKeyboardTheme(
            design: TyprFullKeyboardSettings(defaults: defaults).design,
            hexTheme: FullKeyboardSettings(defaults: defaults).effectiveKeyboardTheme
        )
    }

    static func typrKeyboardDesign(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) -> KeyboardDesign {
        TyprFullKeyboardSettings(defaults: defaults).design
    }
}

extension FullKeyboardPalette {
    private var typrMechanical: TyprFullKeyboardPalette? {
        mechanical ? TyprFullKeyboardPalette(isDark: isDark, design: .mechanical) : nil
    }

    var typrMechanicalKeyFill: UIColor? { typrMechanical?.keyFill }
    var typrMechanicalPressedFill: UIColor? { typrMechanical?.keyPressedFill }

    var keyInk: UIColor { typrMechanical?.keyLabel ?? textBase }

    func inkFrame(_ cap: CGRect) -> CGRect {
        mechanical ? MechanicalKeycap(isDark: isDark).inkFrame(cap) : cap
    }
}

extension CGContext {
    func fillKeycap(_ rect: CGRect, palette: FullKeyboardPalette, fill: UIColor, radius: CGFloat) {
        if palette.mechanical {
            MechanicalKeycap(isDark: palette.isDark).draw(in: self, rect: rect, face: fill, radius: radius)
        } else {
            fillKeycap(rect, fill: fill, shadow: palette.keyShadow, radius: radius)
        }
    }
}

extension FullKeyboardView {
    func syncTyprVariants(_ settings: TyprSettings = TyprSettings(), keyboard: TyprFullKeyboardSettings = TyprFullKeyboardSettings()) {
        let bottomRow = settings[experiment: .typrBottomRow] ? keyboard.bottomRow : nil
        if engine.typrBottomRow != bottomRow {
            engine.typrBottomRow = bottomRow
            setNeedsLayout()
        }
        let showsStrip = !(settings[experiment: .typrCompactStrip] && settings.hideSuggestionBar)
        if engine.showsStrip != showsStrip {
            engine.showsStrip = showsStrip
            setNeedsLayout()
            onPreferredHeightChange?()
        }
        let repeats = !settings[experiment: .deleteSlide]
        if plane.repeatsHeldDelete != repeats { plane.repeatsHeldDelete = repeats }
        plane.slidesDeleteByWord = !repeats || !settings[experiment: .typrDeleteSliding]
        engine.slidesCursorByCharacter = settings[experiment: .typrCursorSliding]
    }
}

extension FullKeyboardView {
    var recordingPanelMetrics: KeyboardMetrics {
        guard !engine.showsStrip else { return engine.layout.metrics }
        return engine.orientation == .landscape ? .typrLandscape : .typrPortrait
    }
}
