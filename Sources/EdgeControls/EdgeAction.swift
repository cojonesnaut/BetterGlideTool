import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeAction
//
// Represents an action that can be assigned to any edge of the trackpad
// (Top, Bottom, Left, or Right).
// ─────────────────────────────────────────────────────────────────────────────

enum EdgeAction: String, Codable, CaseIterable, Identifiable {
    case none              = "none"
    case scroll            = "scroll"
    case volume            = "volume"
    case brightness        = "brightness"
    case keyboardBacklight = "keyboard_backlight"
    case microphone        = "microphone"
    case nightShift        = "night_shift"
    case media             = "media"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .none:              return "None"
        case .scroll:            return "Scroll"
        case .volume:            return "Volume"
        case .brightness:        return "Display Brightness"
        case .keyboardBacklight: return "Keyboard Backlight"
        case .microphone:        return "Microphone Gain"
        case .nightShift:        return "Night Shift Warmth"
        case .media:             return "Media Strip"
        }
    }

    var iconName: String {
        switch self {
        case .none:              return "slash.circle"
        case .scroll:            return "arrow.up.arrow.down"
        case .volume:            return "speaker.wave.3.fill"
        case .brightness:        return "sun.max.fill"
        case .keyboardBacklight: return "keyboard.fill"
        case .microphone:        return "mic.fill"
        case .nightShift:        return "moon.stars.fill"
        case .media:             return "music.note"
        }
    }

    var usesNativeOSD: Bool {
        switch self {
        case .volume, .brightness, .keyboardBacklight:
            return true
        default:
            return false
        }
    }

    /// Whether the action consumes raw finger travel rather than discrete notches.
    ///
    /// Continuous actions bypass `TickAccumulator`: its rate ceiling and
    /// two-ticks-per-frame cap exist to keep notched controls from buzzing, and
    /// applying them to scrolling would turn a smooth slide into visible steps.
    var isContinuous: Bool {
        self == .scroll
    }

    /// Driven in the system's quarter steps rather than full notches.
    var usesFineSteps: Bool {
        switch self {
        case .volume, .brightness, .keyboardBacklight:
            return true
        default:
            return false
        }
    }

    /// Whether a haptic tick should fire as the action advances. Notched controls
    /// feel better with one; a continuous action would vibrate every frame.
    var wantsHapticTicks: Bool {
        switch self {
        case .scroll, .none, .media:
            return false
        default:
            return true
        }
    }

    /// What one slide along the edge does, for the edge rows in Preferences.
    var hint: String {
        switch self {
        case .none:   return L("Off")
        case .scroll: return L("Scrolls the window under the pointer")
        case .media:  return L("Swipe to skip tracks, double-tap to play or pause")
        default:      return L("Slide to adjust")
        }
    }
}

enum TrackpadPhysicalEdge: String, Codable, CaseIterable, Identifiable {
    case top    = "top"
    case bottom = "bottom"
    case left   = "left"
    case right  = "right"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .top:    return "Top Edge"
        case .bottom: return "Bottom Edge"
        case .left:   return "Left Edge"
        case .right:  return "Right Edge"
        }
    }

    var isHorizontal: Bool {
        self == .top || self == .bottom
    }
}
