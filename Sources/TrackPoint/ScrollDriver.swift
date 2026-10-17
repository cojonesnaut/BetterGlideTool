import Cocoa
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - ScrollDriver
// ─────────────────────────────────────────────

/// Emits scroll wheel events for the TrackPoint's scroll stick.
///
/// Pixel units rather than lines, so slow pushes scroll smoothly instead of
/// jumping a line at a time. Wheel deltas are integers, so the fractional part
/// of each step is carried forward — without that, any push whose per-tick
/// distance rounds below one pixel would scroll nothing at all, and the slow end
/// of the range would be dead.
final class ScrollDriver {

    static let shared = ScrollDriver()
    private init() {}

    private lazy var eventSource = CGEventSource(stateID: .hidSystemState)
    private var residualVertical = 0.0
    private var residualHorizontal = 0.0

    /// Clears carried-over fractions. Call once per session.
    func begin() {
        residualVertical = 0
        residualHorizontal = 0
    }

    /// - Parameters:
    ///   - vertical: points to scroll, positive scrolls toward the start of the document.
    ///   - horizontal: points to scroll, positive scrolls toward the left.
    func scroll(vertical: Double, horizontal: Double) {
        residualVertical += vertical
        residualHorizontal += horizontal

        let stepVertical = residualVertical.rounded(.towardZero)
        let stepHorizontal = residualHorizontal.rounded(.towardZero)
        guard stepVertical != 0 || stepHorizontal != 0 else { return }
        residualVertical -= stepVertical
        residualHorizontal -= stepHorizontal

        guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32(stepVertical),
                                  wheel2: Int32(stepHorizontal),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: CursorDriver.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Trackpad-style scrolling

    /// Where an event sits in a trackpad scroll. Raw values are the CGEvent field
    /// values: scroll phases are bit flags, momentum phases are sequential.
    enum Phase {
        case began, changed, ended
        case momentumBegan, momentumChanged, momentumEnded

        var scrollPhase: Int64 {
            switch self {
            case .began:   return 1   // kCGScrollPhaseBegan
            case .changed: return 2   // kCGScrollPhaseChanged
            case .ended:   return 4   // kCGScrollPhaseEnded
            case .momentumBegan, .momentumChanged, .momentumEnded: return 0
            }
        }

        var momentumPhase: Int64 {
            switch self {
            case .began, .changed, .ended: return 0
            case .momentumBegan:   return 1   // kCGMomentumScrollPhaseBegin
            case .momentumChanged: return 2   // kCGMomentumScrollPhaseContinue
            case .momentumEnded:   return 3   // kCGMomentumScrollPhaseEnd
            }
        }
    }

    /// Posts one scroll event shaped like the trackpad's own.
    ///
    /// The plain wheel path above reads to apps as a mouse wheel: whole pixels, no
    /// phases. Many apps then run their own wheel smoothing or line acceleration on
    /// top, and finger-driven travel arrives quantised, so a steady slide comes out
    /// in uneven steps. Flagging the event continuous and giving it scroll and
    /// momentum phases puts it on the same path as a two-finger scroll — precise
    /// deltas applied as-is, rubber-banding at the ends, and the app's momentum
    /// handling. The point deltas carry the exact fractional travel; only the
    /// integer fields, kept for apps that still read them, carry a residual.
    ///
    /// Zero-delta events are posted deliberately: `.ended` and `.momentumEnded`
    /// are how an app learns the gesture is over.
    func scrollContinuous(vertical: Double, horizontal: Double, phase: Phase) {
        residualVertical += vertical
        residualHorizontal += horizontal
        let stepVertical = residualVertical.rounded(.towardZero)
        let stepHorizontal = residualHorizontal.rounded(.towardZero)
        residualVertical -= stepVertical
        residualHorizontal -= stepHorizontal

        guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32(stepVertical),
                                  wheel2: Int32(stepHorizontal),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phase.momentumPhase)
        event.setIntegerValueField(.eventSourceUserData, value: CursorDriver.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
