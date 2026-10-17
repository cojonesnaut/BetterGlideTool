import Foundation

// ─────────────────────────────────────────────
// MARK: - GlideConfig (top-level model)
// ─────────────────────────────────────────────

/// Full serializable representation of BetterGlideTool settings.
/// Mirrors the config.yaml schema:
///
///   touchpad:
///     speed: { swipe_threshold, fast_velocity_threshold, ... }
///     preferences: { window_targeting, haptic_feedback, ... }
///     tuning: { ... }
///     gestures:
///       - { type, direction, fingers, speed, action, app_filter, app_path, reciprocal }
///
struct GlideConfig {

    struct Speed {
        var swipeThreshold: Float = 0.014
        var fastVelocityThreshold: Float = 0.009
        var slowVelocityThreshold: Float = 0.005
        var speedLogic: String = "simple"   // "simple" | "classic"
    }

    struct Preferences {
        var windowTargeting: String = "Focused Window First"
        var hapticFeedback: Bool = true
        var debugLogging: Bool = false
        var launchAtLogin: Bool = false
        var autoDisableNativeGestures: Bool = false
    }

    struct EdgeControls {
        var enabled: Bool = true
        var topEdge: String = "none"
        var bottomEdge: String = "none"
        var leftEdge: String = "brightness"
        var rightEdge: String = "volume"
        var marginMm: Double = 12.0
        var activationTravelMm: Double = 4.0
        var scrollSpeed: Double = 26.0
        var invertScroll: Bool = false
        var scrollMomentum: Bool = true
    }

    struct Tuning {
        var appSwitcherStepThreshold: Float = 0.002
        var appSwitcherDebounce: Double = 0.05
        var continuousStepThreshold: Float = 0.025
        var continuousDebounce: Double = 0.08
        var candidateFrames: Int = 3
        var pinchSpreadThreshold: Float = 0.015
        var pinchFrameSpreadThreshold: Float = 0.008
        var swipeCoherenceThreshold: Float = 0.30
        var swipeAngleTolerance: Float = 45.0
        var tapHoldDuration: Double = 0.5
        var explicitForceClickMargins: Set<String> = []
        var forceClickCornerMargin: Float = 0.35
        var forceClickMarginLeft: Float = 0.35
        var forceClickMarginRight: Float = 0.35
        var forceClickMarginTop: Float = 0.35
        var forceClickMarginBottom: Float = 0.35
        var edgeMarginEnabled: Bool = true
        var edgeMarginLeft: Float = 0.0
        var edgeMarginRight: Float = 0.0
        var edgeMarginTop: Float = 0.0
        var edgeMarginBottom: Float = 0.19
    }

    struct Gesture {
        var desktopOptions = DesktopActionOptions()
        var device: String = "trackpad"
        var appFilters: [String] = []
        var name: String? = nil     // user-given label
        var type: String            // "swipe" | "click"
        var direction: String?      // "up" | "down" | "left" | "right" — nil for click
        var fingers: Int
        var speed: String?          // "slow" | "normal" | "fast" — nil for click
        var action: String
        var appFilter: String?
        var windowState: String?
        var modifierFilter: String?
        var zone: String? = nil     // force-click corner: "top_left" … nil = anywhere
        var appPath: String?
        var menuPath: [String]?
        var shortcutKeyCode: Int?
        var shortcutModifiers: [String]?
        var shortcutName: String? = nil
        var script: String? = nil
        var haptic: String? = nil   // per-gesture HapticPattern rawValue; nil = automatic
        var advancedKeyboard: [String]?
        var reciprocal: Bool
        /// Custom inverse action for the reciprocal swipe; nil = automatic inverse.
        var reciprocalAction: String? = nil
        var continuous: Bool = false
        var continuousNegativeAction: String?
        var continuousPositiveAction: String?
        var continuousEndAction: String?
        var continuousNegativeShortcutKeyCode: Int?
        var continuousNegativeShortcutModifiers: [String]?
        var continuousPositiveShortcutKeyCode: Int?
        var continuousPositiveShortcutModifiers: [String]?
        var continuousEndShortcutKeyCode: Int?
        var continuousEndShortcutModifiers: [String]?
        var continuousBeginKeyboard: [String]?
        var continuousNegativeKeyboard: [String]?
        var continuousPositiveKeyboard: [String]?
        var continuousEndKeyboard: [String]?
        var draft: Bool = false
        /// True when this rule is triggered by a global keyboard shortcut, not a trackpad gesture.
        var keyboardBinding: Bool = false
        /// Carbon key code for the global hotkey (only when `keyboardBinding` is true).
        var triggerShortcutKeyCode: Int? = nil
        var triggerShortcutModifiers: [String]? = nil
    }

    var speed: Speed = Speed()
    var preferences: Preferences = Preferences()
    var edgeControls: EdgeControls = EdgeControls()
    var tuning: Tuning = Tuning()
    /// haptic event rawValue → pattern rawValue (see HapticEvent / HapticPattern)
    var haptics: [String: String] = [:]
    var magicMouse = MagicMouseSettings()
    var deviceTuning = DeviceTuningSettings()
    var gestureSchemaVersion = 0
    var gestures: [Gesture] = []
}

// ─────────────────────────────────────────────
// MARK: - GlideConfig ↔ Settings bridge
// ─────────────────────────────────────────────

extension GlideConfig {

    // ── Build a GlideConfig from current in-memory Settings ──

    static func fromSettings() -> GlideConfig {
        let s = Settings.shared
        let t = s.tuning
        var cfg = GlideConfig()
        cfg.magicMouse = s.magicMouse
        cfg.deviceTuning = s.deviceTuning
        cfg.gestureSchemaVersion = 1

        cfg.speed.swipeThreshold         = t.initialThreshold
        cfg.speed.fastVelocityThreshold  = t.fastVelocityThreshold
        cfg.speed.slowVelocityThreshold  = t.slowVelocityThreshold
        cfg.speed.speedLogic             = t.speedLogic.rawValue

        cfg.preferences.windowTargeting  = s.windowTargetingMode.rawValue
        cfg.preferences.hapticFeedback   = s.hapticFeedbackEnabled
        cfg.haptics = Dictionary(uniqueKeysWithValues: s.hapticAssignments.map { ($0.key.rawValue, $0.value.rawValue) })
        cfg.preferences.debugLogging     = s.debugLoggingEnabled
        cfg.preferences.launchAtLogin    = s.launchAtLoginEnabled
        cfg.preferences.autoDisableNativeGestures = s.autoDisableNativeGestures

        cfg.edgeControls.enabled    = s.edgeControls.enabled
        cfg.edgeControls.topEdge    = s.edgeControls.topEdge.rawValue
        cfg.edgeControls.bottomEdge = s.edgeControls.bottomEdge.rawValue
        cfg.edgeControls.leftEdge   = s.edgeControls.leftEdge.rawValue
        cfg.edgeControls.rightEdge   = s.edgeControls.rightEdge.rawValue
        cfg.edgeControls.marginMm    = s.edgeControls.marginMm
        cfg.edgeControls.activationTravelMm = s.edgeControls.activationTravelMm
        cfg.edgeControls.scrollSpeed = s.edgeControls.scrollSpeed
        cfg.edgeControls.invertScroll = s.edgeControls.invertScroll
        cfg.edgeControls.scrollMomentum = s.edgeControls.scrollMomentum

        cfg.tuning.appSwitcherStepThreshold  = t.appSwitcherStepThreshold
        cfg.tuning.appSwitcherDebounce       = t.appSwitcherDebounce
        cfg.tuning.continuousStepThreshold   = t.continuousStepThreshold
        cfg.tuning.continuousDebounce        = t.continuousDebounce
        cfg.tuning.candidateFrames           = t.candidateFrames
        cfg.tuning.pinchSpreadThreshold      = t.pinchSpreadThreshold
        cfg.tuning.pinchFrameSpreadThreshold = t.pinchFrameSpreadThreshold
        cfg.tuning.swipeCoherenceThreshold   = t.swipeCoherenceThreshold
        cfg.tuning.swipeAngleTolerance       = t.swipeAngleTolerance
        cfg.tuning.tapHoldDuration           = t.tapHoldDuration
        cfg.tuning.forceClickMarginLeft      = t.forceClickMargin.left
        cfg.tuning.forceClickMarginRight     = t.forceClickMargin.right
        cfg.tuning.forceClickMarginTop       = t.forceClickMargin.top
        cfg.tuning.forceClickMarginBottom    = t.forceClickMargin.bottom
        cfg.tuning.edgeMarginEnabled         = t.edgeMarginEnabled
        cfg.tuning.edgeMarginLeft            = t.edgeMargin.left
        cfg.tuning.edgeMarginRight           = t.edgeMargin.right
        cfg.tuning.edgeMarginTop             = t.edgeMargin.top
        cfg.tuning.edgeMarginBottom          = t.edgeMargin.bottom

        cfg.gestures = s.rules.map { rule in
            let typeStr: String
            switch rule.direction {
            case .tapTop: typeStr = "tap_top"
            case .tapBottom: typeStr = "tap_bottom"
            case .circleClockwise: typeStr = "circle_clockwise"
            case .circleCounterClockwise: typeStr = "circle_counter_clockwise"
            case .cornerBottomLeft: typeStr = "corner_bottom_left"
            case .cornerBottomRight: typeStr = "corner_bottom_right"
            case .cornerTopLeft: typeStr = "corner_top_left"
            case .cornerTopRight: typeStr = "corner_top_right"
            case .tipTapThreeLeft: typeStr = "tip_tap_three_left"
            case .tipTapThreeRight: typeStr = "tip_tap_three_right"
            case .tipSwipeLeftLeft: typeStr = "tip_swipe_left_left"
            case .tipSwipeLeftRight: typeStr = "tip_swipe_left_right"
            case .forceClick:           typeStr = "force_click"
            case .tap:                  typeStr = "tap"
            case .doubleTap:            typeStr = "double_tap"
            case .tipTapTwoLeft: typeStr = "tip_tap_two_left"
            case .tipTapTwoMiddle: typeStr = "tip_tap_two_middle"
            case .tipTapTwoRight: typeStr = "tip_tap_two_right"
            case .tipSwipeLeftUp: typeStr = "tip_swipe_left_up"
            case .tipSwipeLeftDown: typeStr = "tip_swipe_left_down"
            case .tipTapLeft:           typeStr = "tip_tap_left"
            case .tipTapRight:          typeStr = "tip_tap_right"
            case .middleTap: typeStr = "middle_tap"
            case .aboveAppleTap: typeStr = "above_apple_tap"
            case .middleClick: typeStr = "middle_click"
            case .leftTap:              typeStr = "left_tap"
            case .rightTap:             typeStr = "right_tap"
            case .click:                typeStr = "click"
            case .tapHold:              typeStr = "hold"
            default:                    typeStr = "swipe"
            }
            let hasDirection = !rule.direction.isClickLike
            let normalized = GestureRule.migratingLegacyAppFilter(rule)
            var gesture = GlideConfig.Gesture(
                name:        rule.name,
                type:        typeStr,
                direction:   hasDirection ? yamlDirection(rule.direction) : nil,
                fingers:     rule.fingers,
                speed:       rule.direction.hasSpeed ? rule.speed.rawValue.lowercased() : nil,
                action:      rule.action.rawValue,
                appFilter:      normalized.appFilter,
                windowState:    normalized.windowStateFilter.yamlValue,
                modifierFilter: normalized.modifierFilter.yamlValue,
                zone:           rule.direction == .forceClick ? rule.zone.yamlValue : nil,
                appPath:        rule.appPath,
                menuPath:       rule.menuItemPath,
                shortcutKeyCode: rule.customShortcut.map { Int($0.keyCode) },
                shortcutModifiers: rule.customShortcut?.yamlModifiers,
                shortcutName: rule.shortcutName,
                script:       rule.script,
                haptic:       rule.hapticPattern?.rawValue,
                advancedKeyboard: rule.advancedKeyboard.map(\.token).nilIfEmpty,
                reciprocal:  rule.reciprocalEnabled,
                reciprocalAction: rule.reciprocalAction?.rawValue,
                continuous:  rule.continuous,
                continuousNegativeAction: rule.continuousNegativeAction == .doNothing ? nil : rule.continuousNegativeAction.rawValue,
                continuousPositiveAction: rule.continuousPositiveAction == .doNothing ? nil : rule.continuousPositiveAction.rawValue,
                continuousEndAction:      rule.continuousEndAction == .doNothing ? nil : rule.continuousEndAction.rawValue,
                continuousNegativeShortcutKeyCode: rule.continuousNegativeAction == .customShortcut ? rule.continuousNegativeShortcut.map { Int($0.keyCode) } : nil,
                continuousNegativeShortcutModifiers: rule.continuousNegativeAction == .customShortcut ? rule.continuousNegativeShortcut?.yamlModifiers : nil,
                continuousPositiveShortcutKeyCode: rule.continuousPositiveAction == .customShortcut ? rule.continuousPositiveShortcut.map { Int($0.keyCode) } : nil,
                continuousPositiveShortcutModifiers: rule.continuousPositiveAction == .customShortcut ? rule.continuousPositiveShortcut?.yamlModifiers : nil,
                continuousEndShortcutKeyCode: rule.continuousEndAction == .customShortcut ? rule.continuousEndShortcut.map { Int($0.keyCode) } : nil,
                continuousEndShortcutModifiers: rule.continuousEndAction == .customShortcut ? rule.continuousEndShortcut?.yamlModifiers : nil,
                continuousBeginKeyboard: rule.continuousBeginKeyboard.map(\.token).nilIfEmpty,
                continuousNegativeKeyboard: rule.continuousNegativeAction == .advancedKeyboard ? rule.continuousNegativeKeyboard.map(\.token).nilIfEmpty : nil,
                continuousPositiveKeyboard: rule.continuousPositiveAction == .advancedKeyboard ? rule.continuousPositiveKeyboard.map(\.token).nilIfEmpty : nil,
                continuousEndKeyboard: rule.continuousEndAction == .advancedKeyboard ? rule.continuousEndKeyboard.map(\.token).nilIfEmpty : nil,
                draft:       rule.isDraft
            )
            if rule.isKeyboardBinding {
                gesture.keyboardBinding = true
                gesture.triggerShortcutKeyCode = rule.triggerShortcut.map { Int($0.keyCode) }
                gesture.triggerShortcutModifiers = rule.triggerShortcut?.yamlModifiers
            }
            gesture.desktopOptions = rule.desktopOptions
            gesture.device = rule.device.rawValue
            gesture.appFilters = rule.appFilters
            return gesture
        }
        return cfg
    }

    // ── Convert to Settings-domain types (used by Settings.apply(_:)) ──

    func toEdgeControls() -> EdgeControlsSettings {
        var e = EdgeControlsSettings()
        e.enabled    = edgeControls.enabled
        e.topEdge    = EdgeAction(rawValue: edgeControls.topEdge) ?? .none
        e.bottomEdge = EdgeAction(rawValue: edgeControls.bottomEdge) ?? .none
        e.leftEdge   = EdgeAction(rawValue: edgeControls.leftEdge) ?? .brightness
        e.rightEdge  = EdgeAction(rawValue: edgeControls.rightEdge) ?? .volume
        e.marginMm    = edgeControls.marginMm
        e.activationTravelMm = edgeControls.activationTravelMm
        e.scrollSpeed = edgeControls.scrollSpeed
        e.invertScroll = edgeControls.invertScroll
        e.scrollMomentum = edgeControls.scrollMomentum
        return EdgeControlsSettings.normalized(e)
    }

    func toTuning() -> GestureTuning {
        var t = GestureTuning()
        t.initialThreshold          = speed.swipeThreshold
        t.fastVelocityThreshold     = speed.fastVelocityThreshold
        t.slowVelocityThreshold     = speed.slowVelocityThreshold
        t.speedLogic                = SpeedLogic(rawValue: speed.speedLogic.lowercased()) ?? .simple
        t.appSwitcherStepThreshold  = tuning.appSwitcherStepThreshold
        t.appSwitcherDebounce       = tuning.appSwitcherDebounce
        t.continuousStepThreshold   = tuning.continuousStepThreshold
        t.continuousDebounce        = tuning.continuousDebounce
        t.candidateFrames           = tuning.candidateFrames
        t.pinchSpreadThreshold      = tuning.pinchSpreadThreshold
        t.pinchFrameSpreadThreshold = tuning.pinchFrameSpreadThreshold
        t.swipeCoherenceThreshold   = tuning.swipeCoherenceThreshold
        t.swipeAngleTolerance       = tuning.swipeAngleTolerance
        t.tapHoldDuration           = tuning.tapHoldDuration
        // If a new field was read, use it. Otherwise fall back to the legacy forceClickCornerMargin, which defaults to 0.35.
        t.forceClickMargin.left     = (tuning.explicitForceClickMargins.contains("left") || tuning.forceClickMarginLeft != 0.35) ? tuning.forceClickMarginLeft : tuning.forceClickCornerMargin
        t.forceClickMargin.right    = (tuning.explicitForceClickMargins.contains("right") || tuning.forceClickMarginRight != 0.35) ? tuning.forceClickMarginRight : tuning.forceClickCornerMargin
        t.forceClickMargin.top      = (tuning.explicitForceClickMargins.contains("top") || tuning.forceClickMarginTop != 0.35) ? tuning.forceClickMarginTop : tuning.forceClickCornerMargin
        t.forceClickMargin.bottom   = (tuning.explicitForceClickMargins.contains("bottom") || tuning.forceClickMarginBottom != 0.35) ? tuning.forceClickMarginBottom : tuning.forceClickCornerMargin
        t.edgeMarginEnabled         = tuning.edgeMarginEnabled
        t.edgeMargin.left           = tuning.edgeMarginLeft
        t.edgeMargin.right          = tuning.edgeMarginRight
        t.edgeMargin.top            = tuning.edgeMarginTop
        t.edgeMargin.bottom         = tuning.edgeMarginBottom
        return t
    }

    func toRules() -> [GestureRule] {
        gestures.compactMap { g in
            guard !g.action.isEmpty, let action = GestureAction(rawValue: g.action) else { return nil }

            let direction: GestureDirection
            if g.type == "middle_tap" { direction = .middleTap
            } else if g.type == "above_apple_tap" { direction = .aboveAppleTap
            } else if g.type == "middle_click" { direction = .middleClick
            } else if g.type == "tap_top" { direction = .tapTop
            } else if g.type == "tap_bottom" { direction = .tapBottom
            } else if g.type == "circle_clockwise" { direction = .circleClockwise
            } else if g.type == "circle_counter_clockwise" { direction = .circleCounterClockwise
            } else if g.type == "corner_bottom_left" { direction = .cornerBottomLeft
            } else if g.type == "corner_bottom_right" { direction = .cornerBottomRight
            } else if g.type == "corner_top_left" { direction = .cornerTopLeft
            } else if g.type == "corner_top_right" { direction = .cornerTopRight
            } else if g.type == "tip_tap_three_left" { direction = .tipTapThreeLeft
            } else if g.type == "tip_tap_three_right" { direction = .tipTapThreeRight
            } else if g.type == "tip_swipe_left_left" { direction = .tipSwipeLeftLeft
            } else if g.type == "tip_swipe_left_right" { direction = .tipSwipeLeftRight
            } else if g.type == "tip_tap_two_left" { direction = .tipTapTwoLeft
            } else if g.type == "tip_tap_two_middle" { direction = .tipTapTwoMiddle
            } else if g.type == "tip_tap_two_right" { direction = .tipTapTwoRight
            } else if g.type == "tip_swipe_left_up" { direction = .tipSwipeLeftUp
            } else if g.type == "tip_swipe_left_down" { direction = .tipSwipeLeftDown
            } else if g.type == "double_tap" { direction = .doubleTap
            } else if g.type == "tip_tap_left" { direction = .tipTapLeft
            } else if g.type == "tip_tap_right" { direction = .tipTapRight
            } else if g.type == "left_tap" { direction = .leftTap
            } else if g.type == "right_tap" { direction = .rightTap
            } else if g.type == "tap" {
                direction = .tap
            } else if g.type == "click" {
                direction = .click
            } else if g.type == "force_click" {
                direction = .forceClick
            } else if g.type == "hold" {
                direction = .tapHold
            } else {
                guard let d = swiftDirection(g.direction) else { return nil }
                direction = d
            }

            let speed: GestureSpeed = {
                switch g.speed?.lowercased() {
                case "slow": return .slow
                case "fast": return .fast
                default:     return .normal
                }
            }()

            var rule = GestureRule(
                name:      g.name,
                fingers:   g.fingers,
                direction: direction,
                speed:     speed,
                action:    action,
                appPath:   g.appPath,
                appFilter: g.appFilter,
                windowStateFilter: WindowStateFilter(yamlValue: g.windowState) ?? .any,
                modifierFilter:    ModifierFilter(yamlValue: g.modifierFilter) ?? .any,
                reciprocalEnabled: g.reciprocal,
                reciprocalAction:  g.reciprocalAction.flatMap(GestureAction.init(rawValue:)),
                continuous:        g.continuous,
                continuousNegativeAction: g.continuousNegativeAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                continuousPositiveAction: g.continuousPositiveAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                continuousEndAction:      g.continuousEndAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                advancedKeyboard:          (g.advancedKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousNegativeShortcut: KeyboardShortcut(yamlKeyCode: g.continuousNegativeShortcutKeyCode,
                                                             modifiers: g.continuousNegativeShortcutModifiers),
                continuousPositiveShortcut: KeyboardShortcut(yamlKeyCode: g.continuousPositiveShortcutKeyCode,
                                                             modifiers: g.continuousPositiveShortcutModifiers),
                continuousEndShortcut:      KeyboardShortcut(yamlKeyCode: g.continuousEndShortcutKeyCode,
                                                             modifiers: g.continuousEndShortcutModifiers),
                continuousBeginKeyboard:    (g.continuousBeginKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousNegativeKeyboard: (g.continuousNegativeKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousPositiveKeyboard: (g.continuousPositiveKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousEndKeyboard:      (g.continuousEndKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                menuItemPath:      g.menuPath,
                customShortcut:    KeyboardShortcut(yamlKeyCode: g.shortcutKeyCode,
                                                     modifiers: g.shortcutModifiers),
                shortcutName:      g.shortcutName,
                script:            g.script,
                isDraft:           g.draft,
                isKeyboardBinding: g.keyboardBinding,
                triggerShortcut:   KeyboardShortcut(yamlKeyCode: g.triggerShortcutKeyCode,
                                                    modifiers: g.triggerShortcutModifiers)
            )
            rule.desktopOptions = g.desktopOptions
            rule.device = GestureDevice(rawValue: g.device) ?? .trackpad
            rule.appFilters = g.appFilters
            rule.hapticPattern = g.haptic.flatMap(HapticPattern.init(rawValue:))
            if direction == .forceClick { rule.zone = TrackpadZone(yamlValue: g.zone) ?? .any }
            return GestureRule.migratingLegacyAppFilter(rule)
        }
    }

    // ── Direction helpers ──

    private static func yamlDirection(_ d: GestureDirection) -> String {
        switch d {
        case .swipeLeftRight: return "left_right"
        case .swipeUpDown:    return "up_down"
        case .swipeLeft:  return "left"
        case .swipeRight: return "right"
        case .swipeUp:    return "up"
        case .swipeDown:  return "down"
        case .tapTop, .tapBottom, .circleClockwise, .circleCounterClockwise, .cornerBottomLeft, .cornerBottomRight, .cornerTopLeft, .cornerTopRight, .tipTapThreeLeft, .tipTapThreeRight, .tipSwipeLeftLeft, .tipSwipeLeftRight, .tap, .doubleTap, .tipTapLeft, .tipTapRight, .tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipSwipeLeftUp, .tipSwipeLeftDown, .leftTap, .rightTap, .middleTap, .aboveAppleTap, .middleClick, .click: return "none"
        case .forceClick: return "none"
        case .tapHold:    return "none"
        }
    }

    private func swiftDirection(_ s: String?) -> GestureDirection? {
        switch s?.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "left_right", "leftright", "horizontal", "x": return .swipeLeftRight
        case "up_down", "updown", "vertical", "y":         return .swipeUpDown
        case "left":  return .swipeLeft
        case "right": return .swipeRight
        case "up":    return .swipeUp
        case "down":  return .swipeDown
        default:      return nil
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - YAML Serializer
// ─────────────────────────────────────────────

enum GlideConfigSerializer {

    static func serialize(_ config: GlideConfig) -> String {
        var lines: [String] = [
            "# BetterGlideTool Configuration",
            "# Generated by BetterGlideTool — import via Preferences › Configuration › Import Config",
            "#",
            "touchpad:",
            "  gesture_schema_version: \(config.gestureSchemaVersion)",
            "",
            "  # ── Speed & Velocity ──────────────────────────────",
            "  speed:",
            "    swipe_threshold: \(fmt(config.speed.swipeThreshold))",
            "    fast_velocity_threshold: \(fmt(config.speed.fastVelocityThreshold))",
            "    slow_velocity_threshold: \(fmt(config.speed.slowVelocityThreshold))",
            "    speed_logic: \(config.speed.speedLogic)",
            "",
            "  # ── Preferences ────────────────────────────────────",
            "  preferences:",
            "    window_targeting: \"\(config.preferences.windowTargeting)\"",
            "    haptic_feedback: \(config.preferences.hapticFeedback ? "true" : "false")",
            "    debug_logging: \(config.preferences.debugLogging ? "true" : "false")",
            "    launch_at_login: \(config.preferences.launchAtLogin ? "true" : "false")",
            "    auto_disable_native_gestures: \(config.preferences.autoDisableNativeGestures ? "true" : "false")",
            "",
            "  # ── Haptic patterns (per event) ────────────────────",
            "  haptics:",
        ]
        lines += config.haptics.sorted { $0.key < $1.key }.map { "    \($0.key): \"\($0.value)\"" }
        lines += [
            "",
            "  # ── Edge Controls ──────────────────────────────────",
            "  edge_controls:",
            "    enabled: \(config.edgeControls.enabled ? "true" : "false")",
            "    top_edge: \(config.edgeControls.topEdge)",
            "    bottom_edge: \(config.edgeControls.bottomEdge)",
            "    left_edge: \(config.edgeControls.leftEdge)",
            "    right_edge: \(config.edgeControls.rightEdge)",
            "    margin_mm: \(String(config.edgeControls.marginMm))",
            "    # Travel along an edge required before a gesture commits. Raise to",
            "    # make accidental triggers less likely.",
            "    activation_travel_mm: \(String(config.edgeControls.activationTravelMm))",
            "    # Points of scroll per millimetre of travel, for edges set to `scroll`.",
            "    scroll_speed: \(String(config.edgeControls.scrollSpeed))",
            "    invert_scroll: \(config.edgeControls.invertScroll ? "true" : "false")",
            "    scroll_momentum: \(config.edgeControls.scrollMomentum ? "true" : "false")",
            "",
            "  # ── Tuning ─────────────────────────────────────────",
            "  tuning:",
            "    app_switcher_step_threshold: \(fmt(config.tuning.appSwitcherStepThreshold))",
            "    app_switcher_debounce: \(String(config.tuning.appSwitcherDebounce))",
            "    continuous_step_threshold: \(fmt(config.tuning.continuousStepThreshold))",
            "    continuous_debounce: \(String(config.tuning.continuousDebounce))",
            "    candidate_frames: \(config.tuning.candidateFrames)",
            "    pinch_spread_threshold: \(fmt(config.tuning.pinchSpreadThreshold))",
            "    pinch_frame_spread_threshold: \(fmt(config.tuning.pinchFrameSpreadThreshold))",
            "    swipe_coherence_threshold: \(fmt(config.tuning.swipeCoherenceThreshold))",
            "    swipe_angle_tolerance: \(String(config.tuning.swipeAngleTolerance))",
            "    tap_hold_duration: \(String(config.tuning.tapHoldDuration))",
            "    force_click_margin:",
            "      left: \(fmt(config.tuning.forceClickMarginLeft))",
            "      right: \(fmt(config.tuning.forceClickMarginRight))",
            "      top: \(fmt(config.tuning.forceClickMarginTop))",
            "      bottom: \(fmt(config.tuning.forceClickMarginBottom))",
            "",
            "    edge_margin:",
            "      enabled: \(config.tuning.edgeMarginEnabled ? "true" : "false")",
            "      left: \(fmt(config.tuning.edgeMarginLeft))",
            "      right: \(fmt(config.tuning.edgeMarginRight))",
            "      top: \(fmt(config.tuning.edgeMarginTop))",
            "      bottom: \(fmt(config.tuning.edgeMarginBottom))",
            "",
            "  # ── Gestures ────────────────────────────────────────",
            "  gestures:",
        ]

        for gesture in config.gestures { lines += serializeGesture(gesture) }

        lines += ["", "  device_tuning:",
                  "    trackpad_sensitivity: \(config.deviceTuning.trackpadSensitivity)",
                  "    mouse_sensitivity: \(config.deviceTuning.mouseSensitivity)",
                  "    trackpad_pointer_speed: \(config.deviceTuning.trackpadPointerSpeed)",
                  "    mouse_pointer_speed: \(config.deviceTuning.mousePointerSpeed)",
                  "    trackpad_tiptap_minimum: \(config.deviceTuning.trackpadTipTapMinimum)",
                  "    mouse_tiptap_minimum: \(config.deviceTuning.mouseTipTapMinimum)",
                  "    trackpad_tiptap_anchor: \(config.deviceTuning.trackpadTipTapAnchor)",
                  "    mouse_tiptap_anchor: \(config.deviceTuning.mouseTipTapAnchor)"]
        lines.append("    trackpad_tiptap_sensitivity: \(config.deviceTuning.trackpadTipTap.sensitivity)")
        lines.append("    trackpad_tiptap_two_sensitivity: \(config.deviceTuning.trackpadTipTap.twoFingerSensitivity)")
        lines.append("    trackpad_tiptap_three_sensitivity: \(config.deviceTuning.trackpadTipTap.threeFingerSensitivity)")
        lines.append("    trackpad_tiptap_two_minimum_distance: \(config.deviceTuning.trackpadTipTap.twoFingerMinimumDistance)")
        lines.append("    trackpad_tiptap_three_minimum_distance: \(config.deviceTuning.trackpadTipTap.threeFingerMinimumDistance)")
        lines.append("    trackpad_tiptap_maximum_distance: \(config.deviceTuning.trackpadTipTap.maximumDistance)")
        lines.append("    trackpad_tiptap_allow_movement: \(config.deviceTuning.trackpadTipTap.allowFingerMovement)")
        lines.append("    trackpad_tiptap_allow_sensitive: \(config.deviceTuning.trackpadTipTap.allowSensitiveTipTaps)")
        lines.append("    mouse_tiptap_sensitivity: \(config.deviceTuning.mouseTipTap.sensitivity)")
        lines.append("    mouse_tiptap_two_sensitivity: \(config.deviceTuning.mouseTipTap.twoFingerSensitivity)")
        lines.append("    mouse_tiptap_three_sensitivity: \(config.deviceTuning.mouseTipTap.threeFingerSensitivity)")
        lines.append("    mouse_tiptap_two_minimum_distance: \(config.deviceTuning.mouseTipTap.twoFingerMinimumDistance)")
        lines.append("    mouse_tiptap_three_minimum_distance: \(config.deviceTuning.mouseTipTap.threeFingerMinimumDistance)")
        lines.append("    mouse_tiptap_maximum_distance: \(config.deviceTuning.mouseTipTap.maximumDistance)")
        lines.append("    mouse_tiptap_allow_movement: \(config.deviceTuning.mouseTipTap.allowFingerMovement)")
        lines.append("    mouse_tiptap_allow_sensitive: \(config.deviceTuning.mouseTipTap.allowSensitiveTipTaps)")
        lines += ["", "  # Magic Mouse settings are independent of trackpad gestures.", "  magic_mouse:",
                  "    enabled: \(config.magicMouse.enabled)",
                  "    invert_vertical_scrolling: \(config.magicMouse.invertVerticalScrolling)",
                  "    invert_horizontal_scrolling: \(config.magicMouse.invertHorizontalScrolling)",
                  "    tap_duration: \(config.magicMouse.tapDuration)",
                  "    tap_movement: \(config.magicMouse.tapMovement)",
                  "    swipe_distance: \(config.magicMouse.swipeDistance)"]
        for gesture in MagicMouseGesture.allCases {
            lines.append("    \(gesture.rawValue): \"\(config.magicMouse.action(for: gesture).rawValue)\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializeGesture(_ g: GlideConfig.Gesture) -> [String] {
        var lines: [String] = [""]
        let comment = "\(g.fingers)-finger \(g.type)\(g.direction.map { " \($0)" } ?? "")\(g.speed.map { " (\($0))" } ?? "") → \(g.action)"
        lines.append("    # \(comment.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "))")
        lines.append("    - type: \(g.type)")
        if let n = g.name, !n.isEmpty { lines.append("      name: \"\(escape(n))\"") }
        lines.append("      device: \(g.device)")
        appendStringList(g.appFilters, key: "app_filters", to: &lines)
        if let d = g.direction { lines.append("      direction: \(d)") }
        lines.append("      fingers: \(g.fingers)")
        if let s = g.speed { lines.append("      speed: \(s)") }
        if g.draft { lines.append("      draft: true") }
        if g.keyboardBinding {
            lines.append("      keyboard_binding: true")
            if let code = g.triggerShortcutKeyCode {
                lines.append("      trigger_shortcut_key_code: \(code)")
                if let mods = g.triggerShortcutModifiers, !mods.isEmpty {
                    lines.append("      trigger_shortcut_modifiers:")
                    for mod in mods { lines.append("        - \(mod)") }
                }
            }
        }
        lines.append("      action: \"\(escape(g.action))\"")
        if let h = g.haptic { lines.append("      haptic: \"\(h)\"") }
        if let ws = g.windowState { lines.append("      window_state: \(ws)") }
        if let mf = g.modifierFilter { lines.append("      modifier_filter: \(mf)") }
        if let z = g.zone { lines.append("      zone: \(z)") }
        lines.append("      app_filter: \(g.appFilter.map { "\"\(escape($0))\"" } ?? "null")")
        if g.type == "swipe" || g.appPath != nil {
            lines.append("      app_path: \(g.appPath.map { "\"\(escape($0))\"" } ?? "null")")
            lines.append("      reciprocal: \(g.reciprocal ? "true" : "false")")
            if let ra = g.reciprocalAction {
                lines.append("      reciprocal_action: \"\(escape(ra))\"")
            }
            if g.type == "swipe" {
                lines.append("      continuous: \(g.continuous ? "true" : "false")")
                appendStringList(g.continuousBeginKeyboard, key: "continuous_begin_keyboard", to: &lines)
                if let action = g.continuousNegativeAction {
                    lines.append("      continuous_update_negative_action: \"\(escape(action))\"")
                }
                if let action = g.continuousPositiveAction {
                    lines.append("      continuous_update_positive_action: \"\(escape(action))\"")
                }
                if let action = g.continuousEndAction {
                    lines.append("      continuous_end_action: \"\(escape(action))\"")
                }
                if g.continuousNegativeAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousNegativeKeyboard, key: "continuous_update_negative_keyboard", to: &lines)
                }
                if g.continuousPositiveAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousPositiveKeyboard, key: "continuous_update_positive_keyboard", to: &lines)
                }
                if g.continuousEndAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousEndKeyboard, key: "continuous_end_keyboard", to: &lines)
                }
            }
        }
        if let path = g.menuPath, !path.isEmpty {
            lines.append("      menu_path:")
            for segment in path {
                lines.append("        - \"\(escape(segment))\"")
            }
        }
        if let code = g.shortcutKeyCode {
            lines.append("      shortcut_key_code: \(code)")
            if let mods = g.shortcutModifiers, !mods.isEmpty {
                lines.append("      shortcut_modifiers:")
                for mod in mods {
                    lines.append("        - \(mod)")
                }
            }
        }
        if g.advancedKeyboard != nil {
            appendStringList(g.advancedKeyboard, key: "advanced_keyboard", to: &lines)
        }
        if g.desktopOptions != DesktopActionOptions() || GestureAction(rawValue: g.action)?.isStageAction == true {
            lines.append("      stage_position: \(g.desktopOptions.stagePosition)")
            lines.append("      stage_window_title: \"\(escape(g.desktopOptions.windowTitle))\"")
            lines.append("      allow_animated_fallback: \(g.desktopOptions.allowAnimatedFallback)")
            if !g.desktopOptions.stageApps.isEmpty {
                lines.append("      stage_apps:")
                for app in g.desktopOptions.stageApps { lines.append("        - \"\(escape(app))\"") }
            }
        }
        if let name = g.shortcutName, !name.isEmpty {
            lines.append("      shortcut_name: \"\(escape(name))\"")
        }
        if let script = g.script, !script.isEmpty {
            lines.append("      script: \"\(escape(script))\"")
        }
        if g.continuousNegativeAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousNegativeShortcutKeyCode, modifiers: g.continuousNegativeShortcutModifiers,
                           keyPrefix: "continuous_update_negative", to: &lines)
        }
        if g.continuousPositiveAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousPositiveShortcutKeyCode, modifiers: g.continuousPositiveShortcutModifiers,
                           keyPrefix: "continuous_update_positive", to: &lines)
        }
        if g.continuousEndAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousEndShortcutKeyCode, modifiers: g.continuousEndShortcutModifiers,
                           keyPrefix: "continuous_end", to: &lines)
        }
        return lines
    }

    private static func fmt(_ v: Float) -> String { String(v) }

    private static func appendStringList(_ values: [String]?, key: String, to lines: inout [String]) {
        guard let values, !values.isEmpty else { return }
        lines.append("      \(key):")
        for value in values {
            lines.append("        - \"\(escape(value))\"")
        }
    }

    private static func appendShortcut(_ keyCode: Int?, modifiers: [String]?, keyPrefix: String, to lines: inout [String]) {
        guard let keyCode else { return }
        lines.append("      \(keyPrefix)_shortcut_key_code: \(keyCode)")
        if let modifiers, !modifiers.isEmpty {
            lines.append("      \(keyPrefix)_shortcut_modifiers:")
            for modifier in modifiers {
                lines.append("        - \(modifier)")
            }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// ─────────────────────────────────────────────
// MARK: - YAML Parser
// ─────────────────────────────────────────────

enum GlideConfigParser {
    private static let gestureTypes: Set<String> = ["above_apple_tap", "circle_clockwise", "circle_counter_clockwise", "click", "corner_bottom_left", "corner_bottom_right", "corner_top_left", "corner_top_right", "double_tap", "force_click", "hold", "left_tap", "middle_click", "middle_tap", "right_tap", "swipe", "tap", "tap_bottom", "tap_top", "tip_swipe_left_down", "tip_swipe_left_left", "tip_swipe_left_right", "tip_swipe_left_up", "tip_tap_left", "tip_tap_right", "tip_tap_three_left", "tip_tap_three_right", "tip_tap_two_left", "tip_tap_two_middle", "tip_tap_two_right"]


    static func parse(yaml: String) -> GlideConfig? {
        let input = yaml.hasPrefix("\u{FEFF}") ? String(yaml.dropFirst()) : yaml
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map(ConfigImportSyntax.withoutComment)
        var cfg = GlideConfig()
        var i = 0

        guard ConfigImportSyntax.isValid(lines), scanToKey("touchpad", in: lines, from: &i) else { return nil }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (indent, key, _) = tokenize(line)
            if indent == 0 && key != nil && key != "touchpad" { break }
            switch key {
            case "gesture_schema_version": cfg.gestureSchemaVersion = intVal(tokenize(line).2) ?? 0; i += 1
            case "speed":       i += 1; parseSpeed(lines, from: &i, parentIndent: indent, into: &cfg.speed)
            case "preferences":  i += 1; parsePreferences(lines, from: &i, parentIndent: indent, into: &cfg.preferences)
            case "haptics":     i += 1; parseHaptics(lines, from: &i, parentIndent: indent, into: &cfg.haptics)
            // Retired sections: still accepted in older files, but nothing reads them.
            case "app_switcher", "trackpoint": i += 1; skipSection(lines, from: &i, parentIndent: indent)
            case "edge_controls", "edgecontrols": i += 1; parseEdgeControls(lines, from: &i, parentIndent: indent, into: &cfg.edgeControls)
            case "device_tuning": i += 1; parseDeviceTuning(lines, from: &i, parentIndent: indent, into: &cfg.deviceTuning)
            case "magic_mouse":  i += 1; parseMagicMouse(lines, from: &i, parentIndent: indent, into: &cfg.magicMouse)
            case "tuning":       i += 1; parseTuning(lines, from: &i, parentIndent: indent, into: &cfg.tuning)
            case "gestures":
                i += 1
                guard parseGestures(lines, from: &i, parentIndent: indent, into: &cfg.gestures) else { return nil }
            default:            i += 1
            }
        }
        guard (0...1).contains(cfg.gestureSchemaVersion), cfg.toRules().count == cfg.gestures.count,
              cfg.gestures.allSatisfy({ GestureDevice(rawValue: $0.device) != nil && Self.gestureTypes.contains($0.type) }) else { return nil }
        return cfg
    }

    private static func parseDeviceTuning(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout DeviceTuningSettings) {
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { i += 1; continue }
            let (indent, key, val) = tokenize(line)
            if indent <= parentIndent { break }
            if key == "trackpad_tiptap_allow_movement" { tuning.trackpadTipTap.allowFingerMovement = boolVal(val) ?? tuning.trackpadTipTap.allowFingerMovement }
            if key == "trackpad_tiptap_allow_sensitive" { tuning.trackpadTipTap.allowSensitiveTipTaps = boolVal(val) ?? tuning.trackpadTipTap.allowSensitiveTipTaps }
            if key == "mouse_tiptap_allow_movement" { tuning.mouseTipTap.allowFingerMovement = boolVal(val) ?? tuning.mouseTipTap.allowFingerMovement }
            if key == "mouse_tiptap_allow_sensitive" { tuning.mouseTipTap.allowSensitiveTipTaps = boolVal(val) ?? tuning.mouseTipTap.allowSensitiveTipTaps }
            if let number = doubleVal(val) {
                switch key {
                case "trackpad_tiptap_sensitivity": tuning.trackpadTipTap.sensitivity = number
                case "trackpad_tiptap_two_sensitivity": tuning.trackpadTipTap.twoFingerSensitivity = number
                case "trackpad_tiptap_three_sensitivity": tuning.trackpadTipTap.threeFingerSensitivity = number
                case "trackpad_tiptap_two_minimum_distance": tuning.trackpadTipTap.twoFingerMinimumDistance = number
                case "trackpad_tiptap_three_minimum_distance": tuning.trackpadTipTap.threeFingerMinimumDistance = number
                case "trackpad_tiptap_maximum_distance": tuning.trackpadTipTap.maximumDistance = number
                case "mouse_tiptap_sensitivity": tuning.mouseTipTap.sensitivity = number
                case "mouse_tiptap_two_sensitivity": tuning.mouseTipTap.twoFingerSensitivity = number
                case "mouse_tiptap_three_sensitivity": tuning.mouseTipTap.threeFingerSensitivity = number
                case "mouse_tiptap_two_minimum_distance": tuning.mouseTipTap.twoFingerMinimumDistance = number
                case "mouse_tiptap_three_minimum_distance": tuning.mouseTipTap.threeFingerMinimumDistance = number
                case "mouse_tiptap_maximum_distance": tuning.mouseTipTap.maximumDistance = number
                case "trackpad_sensitivity": tuning.trackpadSensitivity = number
                case "mouse_sensitivity": tuning.mouseSensitivity = number
                case "trackpad_pointer_speed": tuning.trackpadPointerSpeed = number
                case "mouse_pointer_speed": tuning.mousePointerSpeed = number
                case "trackpad_tiptap_minimum": tuning.trackpadTipTapMinimum = number
                case "mouse_tiptap_minimum": tuning.mouseTipTapMinimum = number
                case "trackpad_tiptap_anchor": tuning.trackpadTipTapAnchor = number
                case "mouse_tiptap_anchor": tuning.mouseTipTapAnchor = number
                default: break
                }
            }
            i += 1
        }
        tuning = DeviceTuningSettings.normalized(tuning)
    }

    private static func parseMagicMouse(_ lines: [String], from i: inout Int, parentIndent: Int, into mouse: inout MagicMouseSettings) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (indent, key, val) = tokenize(line)
            if indent <= parentIndent { break }
            switch key {
            case "invert_vertical_scrolling": mouse.invertVerticalScrolling = boolVal(val) ?? false
            case "invert_horizontal_scrolling": mouse.invertHorizontalScrolling = boolVal(val) ?? false
            case "enabled": mouse.enabled = boolVal(val) ?? mouse.enabled
            case "tap_duration": mouse.tapDuration = doubleVal(val) ?? mouse.tapDuration
            case "tap_movement": mouse.tapMovement = doubleVal(val) ?? mouse.tapMovement
            case "swipe_distance": mouse.swipeDistance = doubleVal(val) ?? mouse.swipeDistance
            default:
                if let key, let gesture = MagicMouseGesture(rawValue: key) {
                    // Unknown actions disable that binding, rather than silently
                    // activating a default action from a newer configuration.
                    mouse.bindings[gesture] = stringVal(val).flatMap(MagicMouseAction.init(rawValue:)) ?? MagicMouseAction.none
                }
            }
            i += 1
        }
        mouse = MagicMouseSettings.normalized(mouse)
    }

    private static func parseSpeed(_ lines: [String], from i: inout Int, parentIndent: Int, into speed: inout GlideConfig.Speed) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "swipe_threshold":          speed.swipeThreshold         = floatVal(val) ?? speed.swipeThreshold
            case "fast_velocity_threshold":  speed.fastVelocityThreshold  = floatVal(val) ?? speed.fastVelocityThreshold
            case "slow_velocity_threshold":  speed.slowVelocityThreshold  = floatVal(val) ?? speed.slowVelocityThreshold
            case "speed_logic":              speed.speedLogic             = stringVal(val) ?? speed.speedLogic
            default: break  // includes retired speed_sample_count from old exports
            }
            i += 1
        }
    }

    private static func parsePreferences(_ lines: [String], from i: inout Int, parentIndent: Int, into prefs: inout GlideConfig.Preferences) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "window_targeting": prefs.windowTargeting = stringVal(val) ?? prefs.windowTargeting
            case "haptic_feedback":  prefs.hapticFeedback  = boolVal(val)   ?? prefs.hapticFeedback
            case "debug_logging":    prefs.debugLogging    = boolVal(val)   ?? prefs.debugLogging
            case "launch_at_login":  prefs.launchAtLogin   = boolVal(val)   ?? prefs.launchAtLogin
            case "auto_disable_native_gestures": prefs.autoDisableNativeGestures = boolVal(val) ?? prefs.autoDisableNativeGestures
            default: break
            }
            i += 1
        }
    }

    private static func parseHaptics(_ lines: [String], from i: inout Int, parentIndent: Int, into haptics: inout [String: String]) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            if let k = key, let v = stringVal(val) { haptics[k] = v }
            i += 1
        }
    }

    private static func skipSection(_ lines: [String], from i: inout Int, parentIndent: Int) {
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && tokenize(lines[i]).0 <= parentIndent { return }
            i += 1
        }
    }

    private static func parseEdgeControls(_ lines: [String], from i: inout Int, parentIndent: Int, into edge: inout GlideConfig.EdgeControls) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "enabled":     edge.enabled    = boolVal(val)   ?? edge.enabled
            case "top_edge":    edge.topEdge    = stringVal(val) ?? edge.topEdge
            case "bottom_edge": edge.bottomEdge = stringVal(val) ?? edge.bottomEdge
            case "left_edge":   edge.leftEdge   = stringVal(val) ?? edge.leftEdge
            case "right_edge":   edge.rightEdge    = stringVal(val) ?? edge.rightEdge
            case "margin_mm":    edge.marginMm     = doubleVal(val) ?? edge.marginMm
            case "activation_travel_mm": edge.activationTravelMm = doubleVal(val) ?? edge.activationTravelMm
            case "scroll_speed": edge.scrollSpeed  = doubleVal(val) ?? edge.scrollSpeed
            case "invert_scroll": edge.invertScroll = boolVal(val)  ?? edge.invertScroll
            case "scroll_momentum": edge.scrollMomentum = boolVal(val) ?? edge.scrollMomentum
            default: break
            }
            i += 1
        }
    }

    private static func parseTuning(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout GlideConfig.Tuning) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "app_switcher_step_threshold":  tuning.appSwitcherStepThreshold  = floatVal(val)  ?? tuning.appSwitcherStepThreshold
            case "app_switcher_debounce":        tuning.appSwitcherDebounce       = doubleVal(val) ?? tuning.appSwitcherDebounce
            case "continuous_step_threshold":     tuning.continuousStepThreshold   = floatVal(val)  ?? tuning.continuousStepThreshold
            case "continuous_debounce":           tuning.continuousDebounce        = doubleVal(val) ?? tuning.continuousDebounce
            case "candidate_frames":             tuning.candidateFrames           = intVal(val)    ?? tuning.candidateFrames
            case "pinch_spread_threshold":       tuning.pinchSpreadThreshold      = floatVal(val)  ?? tuning.pinchSpreadThreshold
            case "pinch_frame_spread_threshold": tuning.pinchFrameSpreadThreshold = floatVal(val)  ?? tuning.pinchFrameSpreadThreshold
            case "swipe_coherence_threshold":    tuning.swipeCoherenceThreshold   = floatVal(val)  ?? tuning.swipeCoherenceThreshold
            case "swipe_angle_tolerance":        tuning.swipeAngleTolerance       = floatVal(val)  ?? tuning.swipeAngleTolerance
            case "tap_hold_duration":            tuning.tapHoldDuration           = doubleVal(val) ?? tuning.tapHoldDuration
            case "force_click_corner_margin":    tuning.forceClickCornerMargin    = floatVal(val)  ?? tuning.forceClickCornerMargin
            case "force_click_margin":
                let marginIndent = ind
                i += 1
                parseForceClickMargin(lines, from: &i, parentIndent: marginIndent, into: &tuning)
                continue
            case "edge_margin":
                let marginIndent = ind
                i += 1
                parseEdgeMargin(lines, from: &i, parentIndent: marginIndent, into: &tuning)
                continue
            default: break
            }
            i += 1
        }
    }

    private static func parseForceClickMargin(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout GlideConfig.Tuning) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "left": tuning.explicitForceClickMargins.insert("left");    tuning.forceClickMarginLeft    = floatVal(val) ?? tuning.forceClickMarginLeft
            case "right": tuning.explicitForceClickMargins.insert("right");   tuning.forceClickMarginRight   = floatVal(val) ?? tuning.forceClickMarginRight
            case "top": tuning.explicitForceClickMargins.insert("top");     tuning.forceClickMarginTop     = floatVal(val) ?? tuning.forceClickMarginTop
            case "bottom": tuning.explicitForceClickMargins.insert("bottom");  tuning.forceClickMarginBottom  = floatVal(val) ?? tuning.forceClickMarginBottom
            default: break
            }
            i += 1
        }
    }

    private static func parseEdgeMargin(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout GlideConfig.Tuning) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "enabled": tuning.edgeMarginEnabled = boolVal(val)  ?? tuning.edgeMarginEnabled
            case "left":    tuning.edgeMarginLeft    = floatVal(val) ?? tuning.edgeMarginLeft
            case "right":   tuning.edgeMarginRight   = floatVal(val) ?? tuning.edgeMarginRight
            case "top":     tuning.edgeMarginTop     = floatVal(val) ?? tuning.edgeMarginTop
            case "bottom":  tuning.edgeMarginBottom  = floatVal(val) ?? tuning.edgeMarginBottom
            default: break
            }
            i += 1
        }
    }

    private static func parseGestures(_ lines: [String], from i: inout Int, parentIndent: Int, into gestures: inout [GlideConfig.Gesture]) -> Bool {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            
            let ind = leadingSpaces(line)
            if ind <= parentIndent { return true }
            
            if trimmed.hasPrefix("-") {
                let g = parseGestureBlock(lines, from: &i, blockIndent: ind)
                guard !g.type.isEmpty && !g.action.isEmpty else { return false }
                gestures.append(g)
                continue
            }
            i += 1
        }
        return true
    }

    private static func parseStringList(_ lines: [String], from i: inout Int, parentIndent: Int) -> [String]? {
        var items: [String] = []
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { i += 1; continue }
            let ind = leadingSpaces(lines[i])
            if ind <= parentIndent { break }
            if line.hasPrefix("-") {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if let s = stringVal(String(item)) { items.append(s) }
                i += 1
                continue
            }
            break
        }
        return items.isEmpty ? nil : items
    }

    private static func parseGestureBlock(_ lines: [String], from i: inout Int, blockIndent: Int) -> GlideConfig.Gesture {
        var g = GlideConfig.Gesture(type: "", direction: nil, fingers: 3,
                                    speed: nil, action: "", appFilter: nil, windowState: nil,
                                    modifierFilter: nil, appPath: nil, menuPath: nil,
                                    shortcutKeyCode: nil, shortcutModifiers: nil,
                                    advancedKeyboard: nil,
                                    reciprocal: true, continuous: false,
                                    continuousNegativeAction: nil,
                                    continuousPositiveAction: nil,
                                    continuousEndAction: nil,
                                    continuousNegativeShortcutKeyCode: nil,
                                    continuousNegativeShortcutModifiers: nil,
                                    continuousPositiveShortcutKeyCode: nil,
                                    continuousPositiveShortcutModifiers: nil,
                                    continuousEndShortcutKeyCode: nil,
                                    continuousEndShortcutModifiers: nil,
                                    continuousBeginKeyboard: nil,
                                    continuousNegativeKeyboard: nil,
                                    continuousPositiveKeyboard: nil,
                                    continuousEndKeyboard: nil,
                                    draft: false)
        let firstIndex = i
        while i < lines.count {
            let line = i == firstIndex
                ? String(repeating: " ", count: blockIndent + 2) + lines[i].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)
                : lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            
            let ind = leadingSpaces(line)
            if ind <= blockIndent { return g }
            
            let (_, key, val) = tokenize(line)
            switch key {
            case "type":       g.type      = stringVal(val) ?? g.type
            case "name":       g.name      = stringVal(val)
            case "direction":  g.direction = stringVal(val)
            case "fingers":    g.fingers   = intVal(val) ?? g.fingers
            case "speed":      g.speed     = stringVal(val)
            case "action":     g.action    = mapActionSynonym(stringVal(val) ?? g.action)
            case "device": g.device = stringVal(val) ?? "trackpad"
            case "app_filters":
                i += 1
                g.appFilters = parseStringList(lines, from: &i, parentIndent: ind) ?? []
                continue
            case "app_filter":    g.appFilter    = nullableStringVal(val)
            case "window_state":    g.windowState    = nullableStringVal(val)
            case "modifier_filter": g.modifierFilter = nullableStringVal(val)
            case "zone":            g.zone           = nullableStringVal(val)
            case "app_path":        g.appPath        = nullableStringVal(val)
            case "menu_path":
                let menuIndent = ind
                i += 1
                g.menuPath = parseStringList(lines, from: &i, parentIndent: menuIndent)
                continue
            case "shortcut_key_code": g.shortcutKeyCode = intVal(val)
            case "stage_position": g.desktopOptions.stagePosition = min(32, max(1, intVal(val) ?? 1))
            case "stage_window_title": g.desktopOptions.windowTitle = stringVal(val) ?? ""
            case "allow_animated_fallback": g.desktopOptions.allowAnimatedFallback = boolVal(val) ?? false
            case "stage_apps":
                i += 1
                g.desktopOptions.stageApps = parseStringList(lines, from: &i, parentIndent: ind) ?? []
                continue
            case "shortcut_name":     g.shortcutName    = stringVal(val)
            case "script":            g.script          = stringVal(val)
            case "haptic":            g.haptic          = stringVal(val)
            case "shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.shortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "advanced_keyboard":
                let listIndent = ind
                i += 1
                g.advancedKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "reciprocal": g.reciprocal = boolVal(val) ?? g.reciprocal
            case "reciprocal_action": g.reciprocalAction = stringVal(val).map(mapActionSynonym)
            case "continuous": g.continuous = boolVal(val) ?? g.continuous
            case "continuous_update_negative_action": g.continuousNegativeAction = stringVal(val).map(mapActionSynonym)
            case "continuous_update_positive_action": g.continuousPositiveAction = stringVal(val).map(mapActionSynonym)
            case "continuous_end_action":             g.continuousEndAction      = stringVal(val).map(mapActionSynonym)
            case "continuous_update_negative_shortcut_key_code": g.continuousNegativeShortcutKeyCode = intVal(val)
            case "continuous_update_positive_shortcut_key_code": g.continuousPositiveShortcutKeyCode = intVal(val)
            case "continuous_end_shortcut_key_code":             g.continuousEndShortcutKeyCode      = intVal(val)
            case "continuous_update_negative_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousNegativeShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_update_positive_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousPositiveShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_end_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousEndShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_begin_keyboard":
                let listIndent = ind
                i += 1
                g.continuousBeginKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_update_negative_keyboard":
                let listIndent = ind
                i += 1
                g.continuousNegativeKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_update_positive_keyboard":
                let listIndent = ind
                i += 1
                g.continuousPositiveKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_end_keyboard":
                let listIndent = ind
                i += 1
                g.continuousEndKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "draft":           g.draft           = boolVal(val) ?? g.draft
            case "keyboard_binding": g.keyboardBinding = boolVal(val) ?? g.keyboardBinding
            case "trigger_shortcut_key_code": g.triggerShortcutKeyCode = intVal(val)
            case "trigger_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.triggerShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            default: break
            }
            i += 1
        }
        return g
    }

    // ── Low-level tokenizer ──

    private static func tokenize(_ raw: String) -> (Int, String?, String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return (0, nil, nil) }
        let indent = leadingSpaces(raw)
        guard let colon = trimmed.firstIndex(of: ":") else { return (indent, nil, nil) }
        let key  = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        let rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (indent, key, rest.isEmpty ? nil : rest)
    }

    private static func leadingSpaces(_ s: String) -> Int { s.prefix(while: { $0 == " " }).count }

    @discardableResult
    private static func scanToKey(_ key: String, in lines: [String], from i: inout Int) -> Bool {
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\(key):") || t == key { return true }
            i += 1
        }
        return false
    }

    // ── Value converters ──

    private static func floatVal(_ s: String?) -> Float?    { s.flatMap { Float($0) } }
    private static func doubleVal(_ s: String?) -> Double?  { s.flatMap { Double($0) } }
    private static func intVal(_ s: String?) -> Int?        { s.flatMap { Int($0) } }

    private static func boolVal(_ s: String?) -> Bool? {
        switch s?.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    private static func stringVal(_ s: String?) -> String? {
        guard let s else { return nil }
        if s.hasPrefix("'") && s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if s.hasPrefix("\"") && s.hasSuffix("\"") {
            return unescapeQuotedString(String(s.dropFirst().dropLast()))
        }
        return s
    }

    private static func unescapeQuotedString(_ s: String) -> String {
        var result = ""
        var escaping = false
        for ch in s {
            if escaping {
                switch ch {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(ch)
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    private static func nullableStringVal(_ s: String?) -> String? {
        guard let s, s.lowercased() != "null", s != "~" else { return nil }
        return stringVal(s)
    }

    private static func mapActionSynonym(_ s: String) -> String {
        switch s.lowercased() {
        case "launch app":           return "Open App…"
        case "open spotlight":       return "Spotlight"
        case "screenshot selection":       return "Screenshot (Area)"
        case "take screenshot":            return "Screenshot (Full)"
        case "screenshot clipboard":       return "Screenshot (Area → Clipboard)"
        case "screenshot full clipboard":  return "Screenshot (Full → Clipboard)"
        case "screenshot toolbar":         return "Screenshot Toolbar"
        default: return s
        }
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

// ─────────────────────────────────────────────
// MARK: - GlideConfigStore
// ─────────────────────────────────────────────
//
// Manages the live config file at:
//   ~/Library/Application Support/BetterGlideTool/config.yaml
//
// • save()  — serializes current Settings to disk
// • load()  — reads file and applies it to Settings via Settings.apply(_:)
//
final class GlideConfigStore {
    static let shared = GlideConfigStore()
    private let location: URL?
    private(set) var lastError: String?
    init(configURL: URL? = nil) { location = configURL }

    /// Coalesces rapid preference edits (e.g. slider drags) into a single disk write.
    private var pendingSave: DispatchWorkItem?
    private var isDirty = false
    private let saveDebounceInterval: TimeInterval = 0.4

    // MARK: Path

    var configURL: URL {
        if let location { return location }
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BetterGlideTool", isDirectory: true)
        return dir.appendingPathComponent("config.yaml")
    }

    var configPath: String { configURL.path }

    // MARK: Save

    /// Queues a debounced write. In-memory `Settings` are already updated; the engine sees changes immediately.
    func scheduleSave() {
        isDirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            _ = self.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
    }

    /// Writes immediately if a debounced save is still pending (prefs close, quit, sleep).
    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty else { return }
        _ = save()
    }

    @discardableResult
    func save() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        lastError = nil

        let url = configURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let yaml = GlideConfigSerializer.serialize(GlideConfig.fromSettings())
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            AppLogger.debug("[Config] Saved → \(url.lastPathComponent)")
            return true
        } catch {
            isDirty = true
            lastError = error.localizedDescription
            AppLogger.debug("[Config] Save failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Load

    @discardableResult
    func load() -> Bool {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            AppLogger.debug("[Config] No config file — using defaults")
            return false
        }
        guard let raw = try? String(contentsOf: configURL, encoding: .utf8),
              let cfg = GlideConfigParser.parse(yaml: raw) else {
            AppLogger.debug("[Config] Failed to parse config")
            return false
        }
        Settings.shared.apply(cfg)
        AppLogger.debug("[Config] Loaded from \(configURL.lastPathComponent)")
        return true
    }

    // MARK: Export / Import

    @discardableResult
    func exportTo(_ destination: URL) -> Bool {
        lastError = nil
        do {
            // Atomic replacement never deletes an existing backup first. Serialize
            // current memory directly, including slider edits awaiting autosave.
            let yaml = GlideConfigSerializer.serialize(GlideConfig.fromSettings())
            try yaml.write(to: destination, atomically: true, encoding: .utf8)
            return true
        } catch {
            lastError = error.localizedDescription
            AppLogger.debug("[Config] Export failed: \(error.localizedDescription)")
            return false
        }
    }

    /// A gesture in an incoming config that would run code, not just drive the UI.
    struct ExecutableAction {
        /// How the gesture is described to the user, e.g. "3-finger swipe up".
        let gesture: String
        /// "Shell Command", "AppleScript", "Shortcut".
        let kind: String
        /// The command, script, or shortcut name that would run.
        let payload: String
    }

    /// Parses `source` without applying it, so a caller can show what it does
    /// before committing.
    func inspect(_ source: URL) -> GlideConfig? {
        guard let raw = try? String(contentsOf: source, encoding: .utf8) else { return nil }
        return GlideConfigParser.parse(yaml: raw)
    }

    /// Every gesture in `config` bound to an action that executes code.
    ///
    /// Configs are meant to be shared, and three of the available actions run
    /// arbitrary code the moment the gesture is performed — a shell command, an
    /// AppleScript, or a named Shortcut. Importing one is therefore equivalent
    /// to running a script, and the user deserves to be told which.
    static func executableActions(in config: GlideConfig) -> [ExecutableAction] {
        let scripted: Set<String> = [
            GestureAction.runShellCommand.rawValue,
            GestureAction.runAppleScript.rawValue,
            GestureAction.runShortcut.rawValue,
        ]

        return config.gestures.compactMap { gesture -> ExecutableAction? in
            // Continuous sub-actions can't be scripted, so only the primary
            // action and the reciprocal override need checking.
            let actions = [gesture.action, gesture.reciprocalAction].compactMap { $0 }
            guard let action = actions.first(where: { scripted.contains($0) }) else { return nil }

            let kind: String
            let payload: String
            switch action {
            case GestureAction.runShellCommand.rawValue:
                kind = "Shell command"
                payload = gesture.script ?? "(empty)"
            case GestureAction.runAppleScript.rawValue:
                kind = "AppleScript"
                payload = gesture.script ?? "(empty)"
            default:
                kind = "Shortcut"
                payload = gesture.shortcutName ?? "(unnamed)"
            }

            let fingers = "\(gesture.fingers)-finger"
            let motion = gesture.direction.map { "\(gesture.type) \($0)" } ?? gesture.type
            return ExecutableAction(
                gesture: gesture.name ?? "\(fingers) \(motion)",
                kind: kind,
                payload: payload
            )
        }
    }

    /// Applies an already-parsed config. Used by the import flow so the file is
    /// only read and parsed once, with the confirmation step in between.
    @discardableResult
    func apply(_ config: GlideConfig) -> Bool {
        let previous = GlideConfig.fromSettings()
        Settings.shared.apply(config)
        guard save() else {
            Settings.shared.apply(previous)
            return false
        }
        return true
    }

    @discardableResult
    func importFrom(_ source: URL) -> Bool {
        guard let cfg = inspect(source) else { return false }
        return apply(cfg)
    }
}
