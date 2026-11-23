import UIKit

/// The keyboard's key layout settings (Settings › Keyboard and Settings › Experiments),
/// applied on every sync: where the Hex key sits, the number row, and whether the Duo unfolded
/// draws one keyboard. Switches that only change typing behaviour stay in
/// `FullKeyboardView.syncSettings`.
@MainActor
extension FullKeyboardView {
    /// Settings › Keyboard › Hex key: Right (the strip's trailing end) or Left (its leading
    /// end), kept in `HexKeyPlacement.current` too for typing logs.
    func syncHexPlacement() {
        let placement = hexPlacementOverride ?? FullKeyboardSettings(defaults: settingsDefaults).hexKeyPlacement
        HexKeyPlacement.current = placement
        guard engine.hexPlacement != placement else { return }
        plane.cancelAllTouches()
        dismissStyleMenu()
        engine.hexPlacement = placement
        setNeedsLayout()
    }

    /// Settings › Keyboard › Number row: the keyboard grows by the row, so the host is asked
    /// for the new height.
    func syncNumberRow() {
        let shows = FullKeyboardSettings(defaults: settingsDefaults).numberRow
        guard engine.showsNumberRow != shows else { return }
        plane.cancelAllTouches()
        dismissStyleMenu()
        engine.showsNumberRow = shows
        setNeedsLayout()
        onPreferredHeightChange?()
    }

    /// Settings › Experiments › Join the keyboard when unfolded: the Duo unfolded upright draws
    /// one keyboard rather than the split one. The rows keep their heights, but Typr's compact
    /// strip only applies joined, so the host is asked for the height again.
    func syncJoinsUnfoldedKeyboard() {
        let joins = typrJoinsUnfoldedKeyboard ?? FullKeyboardSettings(defaults: settingsDefaults).joinsKeyboardWhenUnfolded
        guard engine.joinsUnfoldedKeyboard != joins else { return }
        plane.cancelAllTouches()
        dismissStyleMenu()
        engine.joinsUnfoldedKeyboard = joins
        setNeedsLayout()
        onPreferredHeightChange?()
    }

    /// Settings › Experiments › Dvorak punctuation keys: English's Dvorak letters gain comma,
    /// period and semicolon keys. No row changes height, so the host is asked for nothing.
    func syncDvorakPunctuation() {
        let on = FullKeyboardSettings(defaults: settingsDefaults).dvorakPunctuation
        guard engine.dvorakPunctuation != on else { return }
        plane.cancelAllTouches()
        dismissStyleMenu()
        engine.dvorakPunctuation = on
        setNeedsLayout()
    }
}
