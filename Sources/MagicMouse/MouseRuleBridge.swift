import Cocoa

/// Translates touch recognition into the shared editor/rule model. Legacy mouse
/// bindings are migrated once, so deleting all mouse rules remains intentional.
enum MouseRuleBridge {
    static func direction(_ gesture: MagicMouseGesture, device: GestureDevice) -> GestureDirection {
        switch gesture {
        case .circleClockwise: return .circleClockwise
        case .circleCounterClockwise: return .circleCounterClockwise
        case .cornerBottomLeft: return .cornerBottomLeft
        case .cornerBottomRight: return .cornerBottomRight
        case .cornerTopLeft: return .cornerTopLeft
        case .cornerTopRight: return .cornerTopRight
        case .tipTapThreeLeft: return .tipTapThreeLeft
        case .tipTapThreeRight: return .tipTapThreeRight
        case .tipSwipeLeftLeft: return .tipSwipeLeftLeft
        case .tipSwipeLeftRight: return .tipSwipeLeftRight
        case .fourFingerTap: return .tap
        case .fourFingerDoubleTap: return .doubleTap
        case .leftTap: return device == .magicMouse ? .leftTap : .tap
        case .rightTap: return device == .magicMouse ? .rightTap : .tap
        case .middleTap: return .middleTap
        case .aboveAppleTap: return .aboveAppleTap
        case .oneFingerMiddleClick: return .middleClick
        case .fourFingerClick: return .click
        case .twoFingerTap, .threeFingerTap: return .tap
        case .twoFingerDoubleTap, .threeFingerDoubleTap: return .doubleTap
        case .tipTapTwoLeft: return .tipTapTwoLeft
        case .tipTapTwoMiddle: return .tipTapTwoMiddle
        case .tipTapTwoRight: return .tipTapTwoRight
        case .tipSwipeLeftUp: return .tipSwipeLeftUp
        case .tipSwipeLeftDown: return .tipSwipeLeftDown
        case .tipTapLeft: return .tipTapLeft
        case .tipTapRight: return .tipTapRight
        case .twoFingerClick, .threeFingerClick: return .click
        case .oneFingerSwipeLeft, .swipeLeft, .threeFingerSwipeLeft, .fourFingerSwipeLeft: return .swipeLeft
        case .oneFingerSwipeRight, .swipeRight, .threeFingerSwipeRight, .fourFingerSwipeRight: return .swipeRight
        case .oneFingerSwipeUp, .swipeUp, .threeFingerSwipeUp, .fourFingerSwipeUp: return .swipeUp
        case .oneFingerSwipeDown, .swipeDown, .threeFingerSwipeDown, .fourFingerSwipeDown: return .swipeDown
        }
    }
    static func recognitionSettings(rules: [GestureRule], device: GestureDevice, base: MagicMouseSettings = MagicMouseSettings()) -> MagicMouseSettings {
        var result = base
        result.bindings = [:]
        let active = rules.filter { $0.device == device && $0.isActive && !$0.isKeyboardBinding }
        for gesture in MagicMouseGesture.allCases {
            if device == .trackpad && !gesture.usesSupplementalTrackpadRecognizer { continue }
            if device == .magicMouse && gesture.trackpadOnly { continue }
            let direction = direction(gesture, device: device)
            if active.contains(where: { $0.fingers == gesture.fingers && ($0.direction == direction || (gesture.isOneFingerTap && $0.direction == .tap)) }) {
                result.bindings[gesture] = .missionControl // enabled marker; actual action is resolved on main
            }
        }
        if device == .magicMouse, active.contains(where: { $0.fingers == 1 && ($0.direction == .middleTap || $0.direction == .aboveAppleTap) }) {
            // Raw taps retain position and side; resolve regional conditions on main.
            result.bindings[.leftTap] = .missionControl
            result.bindings[.rightTap] = .missionControl
        }
        if device == .trackpad, active.contains(where: { $0.fingers == 3 && ($0.direction == .tapTop || $0.direction == .tapBottom) }) {
            result.bindings[.threeFingerTap] = .missionControl
        }
        result.enabled = base.enabled && !result.bindings.isEmpty
        return result
    }
    static func recognitionSettings(rules: [GestureRule], device: GestureDevice,
                                    base: MagicMouseSettings, bundleID: String?) -> MagicMouseSettings {
        recognitionSettings(rules: rules.filter { $0.matchesApp(bundleID) }, device: device, base: base)
    }

    static func migrate(_ settings: MagicMouseSettings) -> [GestureRule] {
        MagicMouseGesture.allCases.compactMap { gesture in
            let old = settings.action(for: gesture)
            guard !gesture.trackpadOnly, old != .none else { return nil }
            let action: GestureAction?
            switch old {
            case .restore: action = .restoreWindow
            case .mute: action = .muteToggle
            default: action = GestureAction(rawValue: old.rawValue)
            }
            guard let action else { return nil }
            var rule = GestureRule(fingers: gesture.fingers, direction: direction(gesture, device: .magicMouse), action: action)
            rule.device = .magicMouse
            return rule
        }
    }
    static func tapDirections(_ gesture: MagicMouseGesture, location: MouseContact?) -> [GestureDirection] {
        var directions: [GestureDirection] = []
        if let location {
            if MagicMouseTouchRegion.isAboveApple(x: location.x, y: location.y) { directions.append(.aboveAppleTap) }
            if MagicMouseTouchRegion.isMiddle(x: location.x) { directions.append(.middleTap) }
            directions.append(location.x < 0.5 ? .leftTap : .rightTap)
        } else { directions.append(direction(gesture, device: .magicMouse)) }
        directions.append(.tap)
        return directions
    }

    static func resolve(in rules: [GestureRule], gesture: MagicMouseGesture, device: GestureDevice,
                        modifiers: CapturedModifiers, location: MouseContact? = nil,
                        bundleID: String?, isFullscreen: Bool = false, isMaximized: Bool = false) -> GestureRule? {
        let directions: [GestureDirection]
        if device == .magicMouse && gesture.isOneFingerTap { directions = tapDirections(gesture, location: location) }
        else if device == .trackpad && gesture == .threeFingerTap, let location {
            directions = [location.y >= 0.5 ? .tapTop : .tapBottom, .tap]
        } else { directions = [direction(gesture, device: device)] }
        // Least-specific regions first: the resolver prefers app-specific rules,
        // then the last rule, making a smaller region win within the same scope.
        let matches = directions.reversed().flatMap { direction in
            GestureRuleResolver.matchingRules(in: rules, fingers: gesture.fingers, direction: direction,
                modifiers: modifiers, device: device, bundleID: bundleID,
                isFullscreen: isFullscreen, isMaximized: isMaximized)
        }
        return GestureRuleResolver.bestRuleMatch(in: matches, speed: .normal)
    }

    static func resolve(_ gesture: MagicMouseGesture, device: GestureDevice, modifiers: CapturedModifiers,
                        location: MouseContact? = nil) -> GestureRule? {
        resolve(in: Settings.shared.rules, gesture: gesture, device: device, modifiers: modifiers, location: location,
                bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                isFullscreen: WindowTargeting.shared.isFrontmostWindowFullscreen(),
                isMaximized: WindowTargeting.shared.isFrontmostWindowMaximized())
    }
}
