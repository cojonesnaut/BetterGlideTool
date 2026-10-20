import Foundation

enum MagicMouseGesture: String, CaseIterable, Codable, Identifiable {
    case fourFingerTap = "four_finger_tap", fourFingerDoubleTap = "four_finger_double_tap"
    case circleClockwise = "circle_clockwise", circleCounterClockwise = "circle_counter_clockwise"
    case cornerBottomLeft = "corner_bottom_left", cornerBottomRight = "corner_bottom_right"
    case cornerTopLeft = "corner_top_left", cornerTopRight = "corner_top_right"
    case tipTapThreeLeft = "tip_tap_three_left", tipTapThreeRight = "tip_tap_three_right"
    case tipSwipeLeftLeft = "tip_swipe_left_left", tipSwipeLeftRight = "tip_swipe_left_right"
    case middleTap = "middle_tap", aboveAppleTap = "above_apple_tap", oneFingerMiddleClick = "one_finger_middle_click"
    case fourFingerClick = "four_finger_click"
    case fourFingerSwipeLeft = "four_finger_swipe_left", fourFingerSwipeRight = "four_finger_swipe_right"
    case fourFingerSwipeUp = "four_finger_swipe_up", fourFingerSwipeDown = "four_finger_swipe_down"
    case threeFingerDoubleTap = "three_finger_double_tap", threeFingerClick = "three_finger_click"
    case threeFingerSwipeLeft = "three_finger_swipe_left", threeFingerSwipeRight = "three_finger_swipe_right"
    case threeFingerSwipeUp = "three_finger_swipe_up", threeFingerSwipeDown = "three_finger_swipe_down"
    case tipTapTwoLeft = "tip_tap_two_left", tipTapTwoMiddle = "tip_tap_two_middle", tipTapTwoRight = "tip_tap_two_right"
    case tipSwipeLeftUp = "tip_swipe_left_up", tipSwipeLeftDown = "tip_swipe_left_down"
    case leftTap = "left_tap", rightTap = "right_tap"
    case twoFingerDoubleTap = "two_finger_double_tap", tipTapLeft = "tip_tap_left", tipTapRight = "tip_tap_right", twoFingerClick = "two_finger_click"
    case twoFingerTap = "two_finger_tap", threeFingerTap = "three_finger_tap"
    case oneFingerSwipeLeft = "one_finger_swipe_left", oneFingerSwipeRight = "one_finger_swipe_right"
    case oneFingerSwipeUp = "one_finger_swipe_up", oneFingerSwipeDown = "one_finger_swipe_down"
    case swipeLeft = "swipe_left", swipeRight = "swipe_right"
    case swipeUp = "swipe_up", swipeDown = "swipe_down"
    var id: String { rawValue }
    var isSwipe: Bool { rawValue.contains("swipe_") }
    var isPhysicalClick: Bool { isCornerClick || [.oneFingerMiddleClick, .twoFingerClick, .threeFingerClick, .fourFingerClick].contains(self) }
    var isOneFingerTap: Bool { [.leftTap, .rightTap, .middleTap, .aboveAppleTap].contains(self) }
    var isCornerClick: Bool { [.cornerBottomLeft, .cornerBottomRight, .cornerTopLeft, .cornerTopRight].contains(self) }
    var isCircle: Bool { self == .circleClockwise || self == .circleCounterClockwise }
    var usesThreeFixedFingers: Bool { self == .tipTapThreeLeft || self == .tipTapThreeRight }
    var usesFixedFingers: Bool { usesTwoFixedFingers || usesThreeFixedFingers }
    var trackpadOnly: Bool { isCornerClick || usesThreeFixedFingers || [.fourFingerTap, .fourFingerDoubleTap, .tipSwipeLeftLeft, .tipSwipeLeftRight].contains(self) }
    var usesSupplementalTrackpadRecognizer: Bool {
        (fingers <= 2 && ![.middleTap, .aboveAppleTap, .oneFingerMiddleClick].contains(self)) ||
        [.threeFingerTap, .threeFingerDoubleTap, .fourFingerTap, .fourFingerDoubleTap].contains(self) || usesFixedFingers
    }
    var usesTwoFixedFingers: Bool { [.tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipSwipeLeftUp, .tipSwipeLeftDown, .tipSwipeLeftLeft, .tipSwipeLeftRight].contains(self) }
    var fingers: Int {
        switch self {
        case .circleClockwise, .circleCounterClockwise, .cornerBottomLeft, .cornerBottomRight, .cornerTopLeft, .cornerTopRight: return 1
        case .fourFingerTap, .fourFingerDoubleTap, .tipTapThreeLeft, .tipTapThreeRight: return 4
        case .tipSwipeLeftLeft, .tipSwipeLeftRight: return 3
        case .middleTap, .aboveAppleTap, .oneFingerMiddleClick, .leftTap, .rightTap, .oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown: return 1
        case .threeFingerTap, .threeFingerDoubleTap, .threeFingerClick, .threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp, .threeFingerSwipeDown, .tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipSwipeLeftUp, .tipSwipeLeftDown: return 3
        case .fourFingerClick, .fourFingerSwipeLeft, .fourFingerSwipeRight, .fourFingerSwipeUp, .fourFingerSwipeDown: return 4
        default: return 2
        }
    }
    var title: String {
        switch self {
        case .fourFingerTap: return "4 Finger Tap"
        case .fourFingerDoubleTap: return "4 Finger Double Tap"
        case .circleClockwise: return "1 Finger Circle Clockwise"
        case .circleCounterClockwise: return "1 Finger Circle Counter-Clockwise"
        case .cornerBottomLeft: return "Corner Click Bottom Left"
        case .cornerBottomRight: return "Corner Click Bottom Right"
        case .cornerTopLeft: return "Corner Click Top Left"
        case .cornerTopRight: return "Corner Click Top Right"
        case .tipTapThreeLeft: return "TipTap Left (3 Fingers Fix)"
        case .tipTapThreeRight: return "TipTap Right (3 Fingers Fix)"
        case .tipSwipeLeftLeft: return "TipSwipe Left Finger Left (2 Fingers Fix)"
        case .tipSwipeLeftRight: return "TipSwipe Left Finger Right (2 Fingers Fix)"
        case .middleTap: return "1 Finger Tap Middle"
        case .aboveAppleTap: return "1 Finger Tap Above Apple"
        case .oneFingerMiddleClick: return "1 Finger Middle Click"
        case .fourFingerClick: return "4 Finger Click"
        case .fourFingerSwipeLeft: return "4 Finger Swipe Left"
        case .fourFingerSwipeRight: return "4 Finger Swipe Right"
        case .fourFingerSwipeUp: return "4 Finger Swipe Up"
        case .fourFingerSwipeDown: return "4 Finger Swipe Down"
        case .leftTap: return "1 Finger Tap Left"
        case .rightTap: return "1 Finger Tap Right"
        case .twoFingerTap: return "2 Finger Tap"
        case .twoFingerDoubleTap: return "2 Finger Double-Tap"
        case .tipTapLeft: return "TipTap Left (1 Finger Fix)"
        case .tipTapRight: return "TipTap Right (1 Finger Fix)"
        case .twoFingerClick: return "2 Finger Click"
        case .threeFingerTap: return "3 Finger Tap"
        case .threeFingerDoubleTap: return "3 Finger Double-Tap"
        case .threeFingerClick: return "3 Finger Click"
        case .threeFingerSwipeLeft: return "3 Finger Swipe Left"
        case .threeFingerSwipeRight: return "3 Finger Swipe Right"
        case .threeFingerSwipeUp: return "3 Finger Swipe Up"
        case .threeFingerSwipeDown: return "3 Finger Swipe Down"
        case .tipTapTwoLeft: return "TipTap Left (2 Fingers Fix)"
        case .tipTapTwoMiddle: return "TipTap Middle (2 Fingers Fix)"
        case .tipTapTwoRight: return "TipTap Right (2 Fingers Fix)"
        case .tipSwipeLeftUp: return "TipSwipe Left Finger Up (2 Fingers Fix)"
        case .tipSwipeLeftDown: return "TipSwipe Left Finger Down (2 Fingers Fix)"
        case .oneFingerSwipeLeft: return "One-finger swipe left"
        case .oneFingerSwipeRight: return "One-finger swipe right"
        case .oneFingerSwipeUp: return "One-finger swipe up"
        case .oneFingerSwipeDown: return "One-finger swipe down"
        case .swipeLeft: return "Two-finger swipe left"
        case .swipeRight: return "Two-finger swipe right"
        case .swipeUp: return "Two-finger swipe up"
        case .swipeDown: return "Two-finger swipe down"
        }
    }
}

enum MagicMouseAction: String, CaseIterable, Codable, Identifiable {
    case none = "Do Nothing", leftClick = "Left Click", rightClick = "Right Click", middleClick = "Middle Click"
    case missionControl = "Mission Control", showDesktop = "Show Desktop"
    case nextApp = "Activate Next App", previousApp = "Activate Previous App"
    case snapLeft = "Snap: Left Half", snapRight = "Snap: Right Half"
    case maximize = "Maximize Window", restore = "Restore Window", minimize = "Minimize Window"
    case playPause = "Play / Pause", nextTrack = "Next Track", previousTrack = "Previous Track"
    case volumeUp = "Volume Up", volumeDown = "Volume Down", mute = "Mute / Unmute"
    var id: String { rawValue }
}

struct MouseScrollAxes: OptionSet {
    let rawValue: Int
    static let horizontal = Self(rawValue: 1)
    static let vertical = Self(rawValue: 2)
}

/// Carries a swipe's scroll reservation through the rest of that native scroll.
///
/// A swipe reserves its axes only while the recognizer accepts it, which ends the
/// moment one finger starts to lift. macOS's scroll does not end there: the
/// remaining finger keeps scrolling, and after the lift a momentum run keeps the
/// page moving for up to a second or more. Left through, the page scrolls after
/// the gesture is done. So once an axis has been reserved, it stays reserved for
/// the same sequence — through the lift and its momentum — until macOS ends the
/// momentum or the user begins a new scroll.
struct ScrollSequenceReservation {
    private(set) var owned: MouseScrollAxes = []
    private var lastOwned = 0.0
    /// Backstop if a sequence never reports its end.
    static let timeout = 1.0

    /// CGEvent scroll and momentum phase values.
    static let phaseBegan: Int64 = 1, phaseMayBegin: Int64 = 128
    static let momentumEnded: Int64 = 3

    /// The axes to withhold from this scroll event.
    mutating func axes(touching: MouseScrollAxes, scrollPhase: Int64, momentumPhase: Int64, timestamp: Double) -> MouseScrollAxes {
        if !owned.isEmpty {
            let freshScroll = touching.isEmpty && momentumPhase == 0 &&
                (scrollPhase == Self.phaseBegan || scrollPhase == Self.phaseMayBegin)
            if freshScroll || timestamp - lastOwned > Self.timeout { owned = [] }
        }
        owned.formUnion(touching)
        let withheld = owned
        if !owned.isEmpty { lastOwned = timestamp }
        if momentumPhase == Self.momentumEnded { owned = [] }
        return withheld
    }

    mutating func reset() { owned = [] }
}

/// Selected by the input device, not persisted as user tuning.
enum TipTapSpacingGeometry: Equatable {
    case surface
    case magicMouse
}

struct MagicMouseSettings: Equatable {
    /// How much the main axis must outweigh the other for a swipe to count.
    /// Swipes on a Magic Mouse follow the thumb's arc: measured "up" swipes ran
    /// 53–60° from horizontal (ratio 1.3–1.7), and 1.5 missed a quarter of them.
    /// 1.2 (about 50°) still keeps up and right apart.
    static let swipeAxisDominance = 1.2
    /// Swipes made with the fingers a device scrolls with — one on a Magic
    /// Mouse, two on a trackpad — are flicks: they never withhold the scroll,
    /// and fire only on speed, so panning a chart or page never triggers them.
    /// Measured on TradingView with spoken cues: slow pans peaked at 0.44–0.75
    /// surface widths per second on the Magic Mouse and 0.32–0.50 on the
    /// trackpad; flicks peaked at 3.5–9.6 and 6.1–7.1.
    static let flickSpeed = 2.0
    /// Travel a flick needs, so a twitch at speed is not a swipe. The shortest
    /// recorded flick moved 0.21.
    static let flickDistance = 0.12
    /// Speed is taken over at least this window, as in the measurements.
    static let flickWindow = 0.045
    /// One-finger circles fire live, BetterTouchTool-style: at this fraction
    /// of a full turn (its default, 0.8), then once per further full turn.
    static let circleTurns = 0.8
    /// For a first trigger at one turn or less, the circle must come within
    /// this many seconds of the touch, as in BetterTouchTool, so a slowly
    /// curving scroll never becomes a circle.
    static let circleTimeLimit = 2.5
    /// Smallest span of the loop on either axis, against tiny jitter loops.
    static let circleMinimumSize = 0.06
    func isFlick(fingers: Int) -> Bool {
        (fingers == 1 && tipTapSpacingGeometry == .magicMouse) || (fingers == 2 && tipTapSpacingGeometry == .surface)
    }
    var enabled = true
    var invertVerticalScrolling = false
    var invertHorizontalScrolling = false
    var hasScrollInversion: Bool { invertVerticalScrolling || invertHorizontalScrolling }
    var tipTap = TipTapTuning()
    var tipTapSpacingGeometry: TipTapSpacingGeometry = .surface
    var tipTapMinimumDuration: Double = 0.08
    var tipTapAnchorDuration: Double = 0.25
    var tapDuration: Double = 0.25
    var tapMovement: Double = 0.035
    var swipeDistance: Double = 0.18
    var bindings: [MagicMouseGesture: MagicMouseAction] = [
        .twoFingerTap: .middleClick, .threeFingerTap: .missionControl
    ]
    func action(for gesture: MagicMouseGesture) -> MagicMouseAction { bindings[gesture] ?? .none }
    var hasSwipes: Bool { MagicMouseGesture.allCases.contains { $0.isSwipe && action(for: $0) != .none } }
    func hasSwipes(fingers: Int) -> Bool {
        MagicMouseGesture.allCases.contains { $0.isSwipe && $0.fingers == fingers && action(for: $0) != .none }
    }
    /// Any gesture of two or more fingers is bound, so native scrolling under
    /// two or more fingers would compete with it.
    var holdsMultiFingerScroll: Bool {
        enabled && bindings.contains { $0.value != .none && $0.key.fingers >= 2 && !$0.key.isPhysicalClick }
    }
    func reservedScrollAxes(fingers: Int) -> MouseScrollAxes {
        guard enabled else { return [] }
        let horizontal: [MagicMouseGesture], vertical: [MagicMouseGesture]
        switch fingers {
        case 1:
            // One finger is how a Magic Mouse scrolls: its swipes fire on top
            // of the scroll instead of taking it (see flickSpeed).
            return []
        case 2:
            horizontal = [.swipeLeft, .swipeRight]
            vertical = [.swipeUp, .swipeDown]
        case 3:
            horizontal = [.threeFingerSwipeLeft, .threeFingerSwipeRight]
            vertical = [.threeFingerSwipeUp, .threeFingerSwipeDown]
        case 4:
            horizontal = [.fourFingerSwipeLeft, .fourFingerSwipeRight]
            vertical = [.fourFingerSwipeUp, .fourFingerSwipeDown]
        default: return []
        }
        var axes: MouseScrollAxes = []
        if horizontal.contains(where: { action(for: $0) != .none }) { axes.insert(.horizontal) }
        if vertical.contains(where: { action(for: $0) != .none }) { axes.insert(.vertical) }
        return axes
    }
    static func normalized(_ value: Self) -> Self {
        var result = value
        result.tipTap = TipTapTuning.normalized(value.tipTap)
        result.tipTapMinimumDuration = value.tipTapMinimumDuration.isFinite ? min(0.2, max(0.04, value.tipTapMinimumDuration)) : 0.08
        result.tipTapAnchorDuration = value.tipTapAnchorDuration.isFinite ? min(0.6, max(0.12, value.tipTapAnchorDuration)) : 0.25
        result.tapDuration = value.tapDuration.isFinite ? min(0.45, max(0.10, value.tapDuration)) : 0.25
        result.tapMovement = value.tapMovement.isFinite ? min(0.08, max(0.01, value.tapMovement)) : 0.035
        result.swipeDistance = value.swipeDistance.isFinite ? min(0.45, max(0.10, value.swipeDistance)) : 0.18
        return result
    }
}

/// Normalized touch-surface regions. Y increases toward the front of the mouse.
/// Above Apple is the lower central patch, above the printed logo.
enum MagicMouseTouchRegion {
    static func isMiddle(x: Double) -> Bool { (0.4...0.6).contains(x) }
    static func isAboveApple(x: Double, y: Double) -> Bool { (0.35...0.65).contains(x) && (0.15...0.4).contains(y) }
}

/// Touch-size thresholds are sensor units, not Force Touch pressure. Keeping this
/// independent of UI lets both providers apply the same filtering consistently.
struct TipTapTuning: Equatable {
    var sensitivity = 0.38
    var twoFingerSensitivity = 0.5
    var threeFingerSensitivity = 0.35
    var allowFingerMovement = false
    var twoFingerMinimumDistance = 0.03
    var threeFingerMinimumDistance = 0.03
    var maximumDistance = 0.55
    var allowSensitiveTipTaps = false
    static var trackpadDefaults: Self {
        var value = Self()
        value.sensitivity = 0.25
        value.twoFingerSensitivity = 0.25
        value.threeFingerSensitivity = 0.25
        value.twoFingerMinimumDistance = 0.02
        value.threeFingerMinimumDistance = 0.02
        value.maximumDistance = 0.80
        return value
    }
    static var mouseDefaults: Self {
        var value = Self(); value.sensitivity = 0.5; value.twoFingerSensitivity = 0.3
        return value
    }
    static func normalized(_ value: Self) -> Self {
        var result = value
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.sensitivity = clamp(value.sensitivity, 0.05...1, 0.38)
        result.twoFingerSensitivity = clamp(value.twoFingerSensitivity, 0.05...1, 0.5)
        result.threeFingerSensitivity = clamp(value.threeFingerSensitivity, 0.05...1, 0.35)
        result.maximumDistance = clamp(value.maximumDistance, 0.05...1, 0.55)
        result.twoFingerMinimumDistance = clamp(value.twoFingerMinimumDistance, 0.01...min(0.3, result.maximumDistance), 0.03)
        result.threeFingerMinimumDistance = clamp(value.threeFingerMinimumDistance, 0.01...min(0.3, result.maximumDistance), 0.03)
        return result
    }
    func requiredSize(anchors: Int) -> Double {
        let value = anchors == 1 ? sensitivity : (anchors == 2 ? twoFingerSensitivity : threeFingerSensitivity)
        return value * (allowSensitiveTipTaps ? 0.65 : 1)
    }
    func minimumDistance(anchors: Int) -> Double { anchors == 1 ? twoFingerMinimumDistance : threeFingerMinimumDistance }
    func allowsSpacing(_ moving: MouseContact, anchors: [MouseContact], geometry: TipTapSpacingGeometry = .surface) -> Bool {
        guard !anchors.isEmpty else { return false }
        let minimum = minimumDistance(anchors: anchors.count)
        if geometry == .magicMouse {
            // Mouse X/Y coordinates span a narrow, curved surface, not a square.
            // TipTap sides are defined across its width. Compare the tapping
            // finger with its nearest neighbour, not the entire chord span or
            // a diagonal to a finger resting further up the mouse.
            let gap = anchors.reduce(Double.infinity) { min($0, abs(moving.x - $1.x)) }
            return gap >= minimum && gap <= maximumDistance
        }
        return anchors.allSatisfy {
            let distance = hypot(moving.x - $0.x, moving.y - $0.y)
            return distance >= minimum && distance <= maximumDistance
        }
    }
}
