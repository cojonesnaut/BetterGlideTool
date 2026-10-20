import Cocoa
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - CursorDriver
// ─────────────────────────────────────────────

/// Places the system cursor by synthesizing mouse events.
///
/// An absolute `mouseMoved`/`mouseDragged` event is posted (rather than
/// `CGWarpMouseCursorPosition`) so apps see hover, tracking areas, and drags
/// exactly as they would from a real pointer.
final class CursorDriver {

    static let shared = CursorDriver()
    private init() {}

    /// Stamped into `eventSourceUserData` on everything we post, so Glide's own
    /// suppression tap can recognise these events and let them through. Without
    /// it the tap would swallow the very motion it asked for.
    static let syntheticMarker: Int64 = 0x476C_6964   // 'Glid'

    private lazy var eventSource = CGEventSource(stateID: .hidSystemState)

    /// Places the cursor at an absolute location.
    ///
    /// Used to undo pointer drift that happened *before* a gesture was recognised.
    /// The events that moved it have already been delivered, so suppression cannot
    /// help retroactively — the only way back is to move the cursor again.
    ///
    /// Posted as a drag when a button is held: a plain `mouseMoved` mid-drag ends
    /// the drag.
    func warp(to point: CGPoint) {
        let current = CGEvent(source: nil)?.location ?? point
        guard current != point else { return }
        let (type, button) = Self.currentDragState()
        guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source,
                                  mouseType: type,
                                  mouseCursorPosition: point,
                                  mouseButton: button) else { return }
        // Apps that read deltas instead of absolute position (games, canvases,
        // custom scroll views) need these to see any movement at all.
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - current.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - current.y).rounded()))
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    /// Movement with a button held has to be posted as a drag or the drag ends.
    private static func currentDragState() -> (CGEventType, CGMouseButton) {
        if CGEventSource.buttonState(.combinedSessionState, button: .left)   { return (.leftMouseDragged, .left) }
        if CGEventSource.buttonState(.combinedSessionState, button: .right)  { return (.rightMouseDragged, .right) }
        if CGEventSource.buttonState(.combinedSessionState, button: .center) { return (.otherMouseDragged, .center) }
        return (.mouseMoved, .left)
    }
}
