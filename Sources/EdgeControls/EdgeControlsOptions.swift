import Cocoa

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Edge Controls options
//
// The smaller choices behind Edge Controls: where a side slide may start, how
// strong the slide's haptic tick is, and what a double-tap in each corner does.
// ─────────────────────────────────────────────────────────────────────────────

/// Which part of a side edge a slide may start in. Only the landing point is
/// checked: once a slide has started it may run the whole length of the edge.
enum EdgeActiveArea: String, Codable, CaseIterable, Identifiable {
    case full               = "full"
    case topThreeQuarters   = "top_three_quarters"
    case topHalf            = "top_half"
    case topQuarter         = "top_quarter"
    case bottomThreeQuarters = "bottom_three_quarters"
    case bottomHalf         = "bottom_half"
    case bottomQuarter      = "bottom_quarter"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .full:                return "Full Edge"
        case .topThreeQuarters:    return "Top ¾"
        case .topHalf:             return "Top Half"
        case .topQuarter:          return "Top ¼"
        case .bottomThreeQuarters: return "Bottom ¾"
        case .bottomHalf:          return "Bottom Half"
        case .bottomQuarter:       return "Bottom ¼"
        }
    }

    /// The allowed band as fractions of the edge's height, 0 at the bottom.
    var band: ClosedRange<Double> {
        switch self {
        case .full:                return 0.0...1.0
        case .topThreeQuarters:    return 0.25...1.0
        case .topHalf:             return 0.5...1.0
        case .topQuarter:          return 0.75...1.0
        case .bottomThreeQuarters: return 0.0...0.75
        case .bottomHalf:          return 0.0...0.5
        case .bottomQuarter:       return 0.0...0.25
        }
    }

    /// `y` is the normalised trackpad height, 0 at the bottom, as the sensor reports it.
    func allows(y: Double) -> Bool { band.contains(y) }
}

/// How strong the tick is that an edge slide plays as it moves.
enum EdgeHapticLevel: String, Codable, CaseIterable, Identifiable {
    case off    = "off"
    case light  = "light"
    case medium = "medium"
    case strong = "strong"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .off:    return "Off"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    /// The pattern for one tick. A fast slide plays a step softer, so a brisk
    /// sweep reads as a ripple rather than a buzz.
    func pattern(attenuated: Bool) -> HapticPattern {
        switch self {
        case .off:    return .none
        case .light:  return .softTick
        case .medium: return attenuated ? .softTick : .tap
        case .strong: return attenuated ? .tap : .knock
        }
    }

    /// The stronger pulse for a one-off action — a skipped track or a corner tap.
    var confirmation: HapticPattern {
        switch self {
        case .off:    return .none
        case .light:  return .tap
        case .medium: return .tap
        case .strong: return .knock
        }
    }
}

enum TrackpadCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft     = "top_left"
    case topRight    = "top_right"
    case bottomLeft  = "bottom_left"
    case bottomRight = "bottom_right"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .topLeft:     return "Top-Left Corner"
        case .topRight:    return "Top-Right Corner"
        case .bottomLeft:  return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }

    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
}

/// What a double-tap in a trackpad corner does.
enum EdgeCornerAction: String, Codable, CaseIterable, Identifiable {
    case none              = "none"
    case mute              = "mute"
    case playPause         = "play_pause"
    case nextTrack         = "next_track"
    case previousTrack     = "previous_track"
    case missionControl    = "mission_control"
    case appExpose         = "app_expose"
    case showDesktop       = "show_desktop"
    case notificationCenter = "notification_center"
    case spotlight         = "spotlight"
    case screenshotArea    = "screenshot_area"
    case screenshotToolbar = "screenshot_toolbar"
    case lockScreen        = "lock_screen"
    case runShortcut       = "run_shortcut"

    var id: String { rawValue }

    var displayName: String { L(englishName) }
    var englishName: String {
        switch self {
        case .none:               return "None"
        case .mute:               return "Mute / Unmute"
        case .playPause:          return "Play / Pause"
        case .nextTrack:          return "Next Track"
        case .previousTrack:      return "Previous Track"
        case .missionControl:     return "Mission Control"
        case .appExpose:          return "App Exposé"
        case .showDesktop:        return "Show Desktop"
        case .notificationCenter: return "Notification Center"
        case .spotlight:          return "Spotlight"
        case .screenshotArea:     return "Screenshot (Area)"
        case .screenshotToolbar:  return "Screenshot Toolbar"
        case .lockScreen:         return "Lock Screen"
        case .runShortcut:        return "Run Shortcut…"
        }
    }

    var iconName: String {
        switch self {
        case .none:               return "slash.circle"
        case .mute:               return "speaker.slash.fill"
        case .playPause:          return "playpause.fill"
        case .nextTrack:          return "forward.fill"
        case .previousTrack:      return "backward.fill"
        case .missionControl:     return "rectangle.3.group"
        case .appExpose:          return "rectangle.stack"
        case .showDesktop:        return "menubar.dock.rectangle"
        case .notificationCenter: return "bell"
        case .spotlight:          return "magnifyingglass"
        case .screenshotArea:     return "viewfinder"
        case .screenshotToolbar:  return "camera.viewfinder"
        case .lockScreen:         return "lock.fill"
        case .runShortcut:        return "square.2.layers.3d"
        }
    }

    /// The gesture action that does the same thing, so corners share one
    /// implementation with every other trigger.
    var gestureAction: GestureAction? {
        switch self {
        case .none:               return nil
        case .mute:               return .muteToggle
        case .playPause:          return .playPause
        case .nextTrack:          return .nextTrack
        case .previousTrack:      return .previousTrack
        case .missionControl:     return .missionControl
        case .appExpose:          return .appExpose
        case .showDesktop:        return .showDesktop
        case .notificationCenter: return .notifCenter
        case .spotlight:          return .spotlight
        case .screenshotArea:     return .screenshotArea
        case .screenshotToolbar:  return .screenshotToolbar
        case .lockScreen:         return .lockScreen
        case .runShortcut:        return .runShortcut
        }
    }

    /// Grouped for the corner pickers.
    static let groups: [[EdgeCornerAction]] = [
        [.none],
        [.mute, .playPause, .nextTrack, .previousTrack],
        [.missionControl, .appExpose, .showDesktop, .notificationCenter, .spotlight],
        [.screenshotArea, .screenshotToolbar, .lockScreen],
        [.runShortcut],
    ]
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeTapClaims
//
// A double-tap in a corner or on the media strip is two taps, and with tap to
// click turned on macOS turns each into a click wherever the pointer is. Each
// qualifying tap is recorded here when the finger lifts, and the click
// observation tap asks whether a trackpad button-down that follows is that tap's
// echo. Recorded sessions put the echo 30–90 ms after the lift.
// ─────────────────────────────────────────────────────────────────────────────

enum EdgeTapClaims {
    private static let lock = NSLock()
    private static var lastTapUptime: Double = -.infinity
    private static var swallowedButtons: [Int: Double] = [:]

    /// How long after a qualifying tap lifts its tap-to-click is expected.
    static let echoWindow: Double = 0.25

    /// Called on lift of a tap that landed in an assigned corner or strip.
    static func recordTap(uptime: Double) {
        lock.lock(); lastTapUptime = uptime; lock.unlock()
    }

    static func reset() {
        lock.lock(); lastTapUptime = -.infinity; swallowedButtons.removeAll(); lock.unlock()
    }

    /// Whether a native button event is a corner or strip tap's click and must be
    /// swallowed. The matching button-up goes with it, so apps never see half a
    /// click. `isTrackpad` is only consulted for candidates.
    static func claimsNativeClick(_ type: CGEventType, uptime: Double, isTrackpad: () -> Bool) -> Bool {
        let button: Int, down: Bool
        switch type {
        case .leftMouseDown:  button = 0; down = true
        case .leftMouseUp:    button = 0; down = false
        case .rightMouseDown: button = 1; down = true
        case .rightMouseUp:   button = 1; down = false
        default: return false
        }
        lock.lock()
        swallowedButtons = swallowedButtons.filter { uptime - $0.value < 1.0 }
        if !down {
            let claimed = swallowedButtons.removeValue(forKey: button) != nil
            lock.unlock()
            return claimed
        }
        let age = uptime - lastTapUptime
        guard age >= -0.02, age <= echoWindow else { lock.unlock(); return false }
        lock.unlock()
        guard isTrackpad() else { return false }
        lock.lock(); swallowedButtons[button] = uptime; lock.unlock()
        return true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Live levels
//
// Current output volume and display brightness, for the diagram in Preferences.
// Read on demand while the page is open; nothing runs otherwise.
// ─────────────────────────────────────────────────────────────────────────────

enum EdgeLiveLevels {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let getBrightness: GetBrightnessFn? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightnessFn.self)
    }()

    /// 0–1, or nil when the main display does not report one (most third-party monitors).
    static func displayBrightness() -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value).clamped(to: 0...1)
    }

    /// 0–1 output volume of the current output device.
    static func volume() -> Double? {
        AudioDeviceVolume.defaultOutput().read().map { $0.clamped(to: 0...1) }
    }

    /// Whether to read a level for this action at all.
    static func level(for action: EdgeAction) -> Double? {
        switch action {
        case .volume:     return volume()
        case .brightness: return displayBrightness()
        default:          return nil
        }
    }
}
