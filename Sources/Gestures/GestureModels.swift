import Foundation
import Cocoa

// ─────────────────────────────────────────────
// MARK: - Touch frame data
// ─────────────────────────────────────────────

struct TouchFrameData {
    let count: Int32
    let cx: Float
    let cy: Float
    let spread: Float
    let coherence: Float
    /// The trackpad's own timestamp for this frame, in seconds. Velocities are
    /// measured on this rather than on when the frame reached the main thread:
    /// that arrival time jitters with main-thread load and frame coalescing, and
    /// the jitter lands directly in every speed the recognizer computes. Zero
    /// for synthetic frames, which fall back to arrival time.
    var timestamp: TimeInterval = 0
}

// ─────────────────────────────────────────────
// MARK: - Gesture classification
// ─────────────────────────────────────────────

enum GestureKind { case unknown, swipe, pinch }

// ─────────────────────────────────────────────
// MARK: - Session state machine models
// ─────────────────────────────────────────────

struct CandidateData {
    let startX: Float; let startY: Float
    let fingers: Int; let startTime: TimeInterval
    let initialSpread: Float
    let modifiersAtStart: CapturedModifiers
    var frameCount: Int
    var cumulativeSpreadDelta: Float
    var prevSpread: Float
    var minCoherence: Float
    var prevCx: Float; var prevCy: Float
    /// Wall-clock time when the centroid first moved past the movement epsilon —
    /// speed is measured from here, not finger-down, so resting fingers don't read slow.
    var movementStartTime: TimeInterval?
    /// Per-frame centroid velocities (widths/second) for classic speed logic.
    var velocitySamples: [Float] = []
    /// Timestamp of the previous frame — turns per-frame distances into velocities.
    var lastFrameTime: TimeInterval
    var gestureKind: GestureKind = .unknown
    var classificationFrameDelay: Int = 0
    /// When the contact count first fell below `fingers`, while it stays below.
    var fingerDropoutStart: TimeInterval?
}

struct SwipeTrackData {
    let startX: Float; let startY: Float
    var lastX: Float; var lastY: Float
    let fingers: Int; let startTime: TimeInterval
    let modifiersAtStart: CapturedModifiers
    var movementStartTime: TimeInterval?
    var velocitySamples: [Float]
    var lastFrameTime: TimeInterval
    var recentDeltas: [(dx: Float, dy: Float)]
    let initialSpread: Float
    var prevSpread: Float
    var cumulativeSpreadDelta: Float
    var continuousRefX: Float
    var continuousRefY: Float
    var lastContinuousActionTime: TimeInterval
    var continuousRule: GestureRule?
    var lockedSpeed: GestureSpeed?
}

enum GesturePhase {
    case idle
    case candidate(CandidateData)
    case lockedSwipe(SwipeTrackData)
    case ignored
    case fired
    case continuousSwipe(SwipeTrackData)
}

// ─────────────────────────────────────────────
// MARK: - Reciprocal token
// ─────────────────────────────────────────────

struct ReciprocalToken {
    let inverseAction: GestureAction
    let desktopOptions: DesktopActionOptions
    let fingers: Int
    let direction: GestureDirection
    let sourceRuleID: UUID
    let expiresAt: TimeInterval
}
import Foundation

extension GestureDirection {

    /// Determines the cardinal direction from a 0-360 degree angle.
    static func fromAngle(_ angle: Float, tolerance: Float) -> GestureDirection? {
        if angle >= (360 - tolerance) || angle < tolerance          { return .swipeRight }
        if angle >= (90 - tolerance)  && angle < (90 + tolerance)   { return .swipeUp }
        if angle >= (180 - tolerance) && angle < (180 + tolerance)  { return .swipeLeft }
        if angle >= (270 - tolerance) && angle < (270 + tolerance)  { return .swipeDown }
        return nil
    }

    /// Returns true if the direction matches the primary axis (horizontal/vertical)
    /// of the starting direction.
    func matchesAxis(of other: GestureDirection) -> Bool {
        switch other {
        case .swipeLeft, .swipeRight, .swipeLeftRight:
            return self == .swipeLeft || self == .swipeRight
        case .swipeUp, .swipeDown, .swipeUpDown:
            return self == .swipeUp || self == .swipeDown
        case .tapTop, .tapBottom, .circleClockwise, .circleCounterClockwise, .cornerBottomLeft, .cornerBottomRight, .cornerTopLeft, .cornerTopRight, .tipTapThreeLeft, .tipTapThreeRight, .tipSwipeLeftLeft, .tipSwipeLeftRight, .tap, .doubleTap, .tipTapLeft, .tipTapRight, .tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipSwipeLeftUp, .tipSwipeLeftDown, .leftTap, .rightTap, .middleTap, .aboveAppleTap, .middleClick, .click, .forceClick, .tapHold:
            return false
        }
    }
}
