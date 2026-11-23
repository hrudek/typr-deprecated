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
}
