import UIKit

/// Typr cursor sliding: the space bar of Typr's own keyboard (Space bar trackpad like Apple's
/// off) on Hex's. Held `trackpadHoldDelay`, then slid `trackpadActivationDistance` along, it
/// moves the cursor one character per `trackpadPointsPerCharacter`, at any speed and only along
/// the line. Held without sliding, letting go types a space.
@MainActor
extension FullKeyboardEngine {
    /// A held space bar touch moved to `point`: true once the slide owns it.
    func slideCursorByCharacter(_ touch: inout ActiveTouch, id: Int, to point: CGPoint) -> Bool {
        guard touch.isTrackpad else {
            guard touch.isHeldToSlideCursor, !touch.committed,
                  abs(point.x - touch.startPoint.x) >= Self.trackpadActivationDistance else { return false }
            touch.isTrackpad = true
            touch.cursorSlideAnchorX = point.x
            trackpadUpdated(touch, id: id, started: true)
            typingLog?.ui("trackpad_start", [TypingLogField("id", .int(id))])
            onSelectionStep?()
            onChange?()
            return true
        }
        let steps = Int(((point.x - touch.cursorSlideAnchorX) / Self.trackpadPointsPerCharacter).rounded(.towardZero))
        guard steps != 0 else { return true }
        touch.cursorSlideAnchorX += CGFloat(steps) * Self.trackpadPointsPerCharacter
        touch.trackpadOffset += steps
        typingLog?.edit("cursor", [TypingLogField("offset", .int(steps))])
        trackpadUpdated(touch, id: id)
        trackpadMovedCursor(by: steps)
        onSelectionStep?()
        return true
    }
}
