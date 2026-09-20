import Foundation

enum MagicMouseGesture: String, CaseIterable, Codable, Identifiable {
    case leftTap = "left_tap", rightTap = "right_tap"
    case twoFingerTap = "two_finger_tap", threeFingerTap = "three_finger_tap"
    case swipeLeft = "swipe_left", swipeRight = "swipe_right"
    case swipeUp = "swipe_up", swipeDown = "swipe_down"
    var id: String { rawValue }
    var isSwipe: Bool { rawValue.hasPrefix("swipe_") }
    var title: String {
        switch self {
        case .leftTap: return "One-finger tap · left side"
        case .rightTap: return "One-finger tap · right side"
        case .twoFingerTap: return "Two-finger tap"
        case .threeFingerTap: return "Three-finger tap"
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

struct MagicMouseSettings: Equatable {
    var enabled = true
    var tapDuration: Double = 0.25
    var tapMovement: Double = 0.035
    var swipeDistance: Double = 0.18
    var bindings: [MagicMouseGesture: MagicMouseAction] = [
        .twoFingerTap: .middleClick, .threeFingerTap: .missionControl
    ]
    func action(for gesture: MagicMouseGesture) -> MagicMouseAction { bindings[gesture] ?? .none }
    var hasSwipes: Bool { MagicMouseGesture.allCases.contains { $0.isSwipe && action(for: $0) != .none } }
    static func normalized(_ value: Self) -> Self {
        var result = value
        result.tapDuration = value.tapDuration.isFinite ? min(0.45, max(0.10, value.tapDuration)) : 0.25
        result.tapMovement = value.tapMovement.isFinite ? min(0.08, max(0.01, value.tapMovement)) : 0.035
        result.swipeDistance = value.swipeDistance.isFinite ? min(0.45, max(0.10, value.swipeDistance)) : 0.18
        return result
    }
}
