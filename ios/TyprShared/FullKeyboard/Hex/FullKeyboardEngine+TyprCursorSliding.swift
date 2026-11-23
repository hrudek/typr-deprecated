import UIKit

@MainActor
extension FullKeyboardEngine {
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
