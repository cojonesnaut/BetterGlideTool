import Foundation

/// Exercise the complete Settings → YAML → disk → import → Settings path.
/// Every file operation targets an isolated temporary directory.
enum ConfigAuditTests {
    static func run() {
        var seed = GlideConfig()
        seed.gestureSchemaVersion = 1
        seed.speed.swipeThreshold = 0.014123456
        seed.speed.fastVelocityThreshold = 0.009123456
        seed.speed.slowVelocityThreshold = 0.005123456
        seed.edgeControls.marginMm = 12.123456789
        seed.tuning.continuousDebounce = 0.081234567
        seed.tuning.forceClickMarginLeft = 0.23123456
        seed.deviceTuning.trackpadSensitivity = 0.23456789
        seed.deviceTuning.mouseSensitivity = 0.7654321
        seed.deviceTuning.trackpadPointerSpeed = 1.4
        seed.deviceTuning.mousePointerSpeed = 2.3
        seed.deviceTuning.trackpadTipTapMinimum = 0.13
        seed.deviceTuning.mouseTipTapMinimum = 0.17
        seed.deviceTuning.trackpadTipTapAnchor = 0.36
        seed.deviceTuning.mouseTipTapAnchor = 0.47
        seed.deviceTuning.trackpadTipTap = TipTapTuning(sensitivity: 0.27, twoFingerSensitivity: 0.61,
            threeFingerSensitivity: 0.44, allowFingerMovement: true, twoFingerMinimumDistance: 0.08,
            threeFingerMinimumDistance: 0.13, maximumDistance: 0.74, allowSensitiveTipTaps: true)
        seed.deviceTuning.mouseTipTap = TipTapTuning(sensitivity: 0.72, twoFingerSensitivity: 0.21,
            threeFingerSensitivity: 0.31, allowFingerMovement: true, twoFingerMinimumDistance: 0.09,
            threeFingerMinimumDistance: 0.14, maximumDistance: 0.69, allowSensitiveTipTaps: true)
        seed.magicMouse.enabled = false
        seed.magicMouse.invertVerticalScrolling = true
        seed.magicMouse.invertHorizontalScrolling = true
        seed.magicMouse.tapDuration = 0.32123456
        seed.magicMouse.tapMovement = 0.04312345
        seed.magicMouse.swipeDistance = 0.24123456
        Settings.shared.apply(seed)
        var allRules: [GestureRule] = []
        for device in GestureDevice.allCases {
            for count in 1...(device == .magicMouse ? 4 : 5) {
                for direction in GestureDirection.available(fingers: count, device: device) {
                    var rule = GestureRule(name: "\(device) \(count) \(direction) # \"quote\" \\literal\\n\tline\r\nΩ 😀",
                        fingers: count, direction: direction, action: .showDesktop)
                    rule.device = device
                    rule.appFilters = ["com.brave.Browser", "com.apple.finder"]
                    rule.windowStateFilter = .notFullscreen
                    rule.modifierFilter = .shiftHeld
                    if direction == .forceClick { rule.zone = .topRight }
                    allRules.append(rule)
                }
            }
        }
        for action in GestureAction.allCases {
            var rule = GestureRule(name: "Action \(action)", fingers: 3, direction: .swipeUp, action: action)
            rule.appPath = "/Applications/Test \"quoted\" \\ path.app"
            rule.appFilters = ["com.brave.Browser", "com.apple.Safari"]
            rule.desktopOptions.stagePosition = 7
            rule.desktopOptions.stageApps = ["com.apple.finder", "com.brave.Browser"]
            rule.desktopOptions.windowTitle = "Work: # \"Q\" \\ literal\\n\ttext"
            rule.desktopOptions.allowAnimatedFallback = true
            rule.script = "printf '%s\\n' \"quoted\"\n# a comment\r\n\tUnicode Ω"
            rule.shortcutName = "Shortcut: \"QA\" \\n"
            rule.customShortcut = KeyboardShortcut(keyCode: 12, command: true, shift: true)
            rule.menuItemPath = ["File", "Menu: # \"\\text\"", "Ω"]
            rule.advancedKeyboard = [KeyboardInputStep(keyCode: 12), KeyboardInputStep(event: .hold, keyCode: 13, command: true), KeyboardInputStep(event: .release, keyCode: 13, command: true)]
            // Inactive options are retained when choosing another action in the editor.
            allRules.append(rule)
        }
        var keyboard = GestureRule(fingers: 4, direction: .click, action: .showDesktop)
        keyboard.isKeyboardBinding = true
        keyboard.triggerShortcut = KeyboardShortcut(keyCode: 17, command: true, option: true)
        allRules.insert(keyboard, at: 1)
        var reciprocal = GestureRule(fingers: 4, direction: .swipeDown, action: .showDesktop)
        reciprocal.reciprocalAction = .runShellCommand
        reciprocal.script = "printf 'reciprocal \\n'"
        allRules.insert(reciprocal, at: 0)
        var continuous = GestureRule(fingers: 4, direction: .swipeLeftRight, action: .doNothing)
        continuous.continuous = true
        continuous.continuousNegativeAction = .customShortcut
        continuous.continuousNegativeShortcut = KeyboardShortcut(keyCode: 123, command: true)
        continuous.continuousPositiveAction = .advancedKeyboard
        continuous.continuousPositiveKeyboard = [KeyboardInputStep(keyCode: 124)]
        continuous.continuousEndAction = .customShortcut
        continuous.continuousEndShortcut = KeyboardShortcut(keyCode: 53)
        allRules.append(continuous)
        var draft = GestureRule(fingers: 1, direction: .circleClockwise, action: .doNothing)
        draft.isDraft = true
        allRules.append(draft)
        Settings.shared.rules = allRules
        let expectedRules = Settings.shared.rules
        let expectedTuning = Settings.shared.deviceTuning
        let expectedMouse = Settings.shared.magicMouse
        let baseline = GlideConfig.fromSettings()
        let yaml = GlideConfigSerializer.serialize(baseline)
        guard let decoded = GlideConfigParser.parse(yaml: yaml) else { fatalError("Full export must be importable") }
        precondition(decoded.speed.swipeThreshold == baseline.speed.swipeThreshold, "Float precision must survive")
        precondition(decoded.tuning.continuousDebounce == baseline.tuning.continuousDebounce, "Double precision must survive")
        precondition(decoded.edgeControls.marginMm == baseline.edgeControls.marginMm)
        Settings.shared.apply(decoded)
        let actualRules = Settings.shared.rules
        precondition(actualRules.count == expectedRules.count)
        for (expected, actual) in zip(expectedRules, actualRules) {
            var compared = expected; compared.id = actual.id
            let left = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(compared)) as! [String: Any]
            let right = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as! [String: Any]
            precondition((left as NSDictionary).isEqual(to: right), "Rule metadata lost: \(expected.name ?? expected.direction.rawValue)")
        }
        precondition(Settings.shared.deviceTuning == expectedTuning)
        precondition(MagicMouseGesture.allCases.allSatisfy { Settings.shared.magicMouse.action(for: $0) == expectedMouse.action(for: $0) })
        precondition(Settings.shared.magicMouse.invertHorizontalScrolling && Settings.shared.magicMouse.invertVerticalScrolling)
        for _ in 0..<5 {
            let next = GlideConfigSerializer.serialize(GlideConfig.fromSettings())
            precondition(next == yaml, "Repeated export/import must not drift, reorder or lose settings")
            Settings.shared.apply(GlideConfigParser.parse(yaml: next)!)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BetterGlideTool-config-audit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GlideConfigStore(configURL: root.appendingPathComponent("live/config.yaml"))
        let exported = root.appendingPathComponent("backup.yaml")
        precondition(store.exportTo(exported))
        precondition(try! String(contentsOf: exported, encoding: .utf8) == yaml)
        precondition(store.exportTo(exported), "Existing backups must be atomically replaced")
        precondition(store.apply(decoded))
        precondition(store.exportTo(store.configURL), "Exporting to the live path must not delete its source")
        precondition(store.load())
        precondition(store.importFrom(exported))
        precondition(GlideConfigSerializer.serialize(GlideConfig.fromSettings()) == yaml)
        let blocker = root.appendingPathComponent("not-a-directory")
        try! "sentinel".write(to: blocker, atomically: true, encoding: .utf8)
        let failing = GlideConfigStore(configURL: blocker.appendingPathComponent("config.yaml"))
        var changed = decoded; changed.deviceTuning.mouseSensitivity = 0.98
        precondition(!failing.apply(changed), "Failed import must report failure")
        precondition(failing.lastError != nil)
        precondition(GlideConfigSerializer.serialize(GlideConfig.fromSettings()) == yaml, "Failed import must restore previous in-memory settings")
        precondition(!store.exportTo(root), "Cannot overwrite a directory with a config")
        precondition(try! String(contentsOf: exported, encoding: .utf8) == yaml, "Failed export must preserve existing backup")
        let invalid = [
            "touchpad: garbage", "touchpad:\n  device_tuning:\n    mouse_sensitivity: nope",
            "touchpad:\n  device_tuning:\n    mouse_sensitivity: nan",
            "touchpad:\n  magic_mouse:\n    enabled: maybe",
            "touchpad:\n  gesture_schema_version: 99", "touchpad:\n  future_unknown_settings: true",
            "touchpad:\n  gestures:\n    - type: tap\n      fingers: 2",
            "touchpad:\n  gestures:\n    - type: tap\n      action: Unknown action",
            "touchpad:\n  gestures:\n    - type: tap\n      device: typo\n      action: Show Desktop",
            "touchpad:\n  gestures:\n    - type: tap\n      name: \"unfinished\n      action: Show Desktop",
            "touchpad:\n  magic_mouse:\n    enabled: true\n    enabled: false"
        ]
        for input in invalid {
            try! input.write(to: exported, atomically: true, encoding: .utf8)
            precondition(!store.importFrom(exported), "Invalid config must be rejected as a whole: \(input)")
            precondition(GlideConfigSerializer.serialize(GlideConfig.fromSettings()) == yaml)
        }
        let reordered = """
        touchpad: # exported-style config
          gesture_schema_version: 1
          app_switcher:
            enabled: false
          gestures:
            - action: Show Desktop
              type: 'tap'
              device: trackpad
              fingers: 3
              name: 'Literal \\n and it''s a name'
          device_tuning:
            mouse_tiptap_allow_sensitive: true # comment
        """
        let legacyMargins = GlideConfigParser.parse(yaml: "touchpad:\n  tuning:\n    force_click_margin:\n      left: 0.35\n    force_click_corner_margin: 0.25\n  edgecontrols:\n    enabled: false\n")!
        precondition(legacyMargins.toTuning().forceClickMargin.left == 0.35 && legacyMargins.toTuning().forceClickMargin.right == 0.25)
        precondition(!legacyMargins.edgeControls.enabled)
        let crlf = "\u{FEFF}" + reordered.replacingOccurrences(of: "\n", with: "\r\n")
        let reorderedConfig = GlideConfigParser.parse(yaml: crlf)!
        precondition(reorderedConfig.gestures[0].name == "Literal \\n and it's a name")
        precondition(reorderedConfig.deviceTuning.mouseTipTap.allowSensitiveTipTaps)
        // Everything the App Switcher left in configs before 2.11.6 must still import:
        // its gestures are dropped, its edge is switched off, the rest is ignored.
        let retiredSwitcher = """
        touchpad:
          gesture_schema_version: 1
          haptics:
            switcher_open: "rising"
            switcher_step: "soft_tick"
            switcher_commit: "double_tap"
          edge_controls:
            top_edge: app_switcher
          tuning:
            app_switcher_step_threshold: 0.002
            app_switcher_debounce: 0.05
          gestures:
            - type: swipe
              device: trackpad
              direction: right
              fingers: 3
              action: "Next App (App Switcher)"
            - action: Show Desktop
              type: tap
              device: trackpad
              fingers: 3
        """
        guard let retired = GlideConfigParser.parse(yaml: retiredSwitcher) else { fatalError("A pre-2.11.6 App Switcher config must still import") }
        precondition(retired.toRules().map(\.action) == [.showDesktop], "Retired switcher gestures are dropped, others kept")
        precondition(retired.toEdgeControls().topEdge == .none, "A retired switcher edge is switched off")
        print("PASS: \(expectedRules.count) complete gesture/action records; all tuning, metadata, precision and order survive six round-trips; atomic file import/export, failure rollback, invalid-file rejection and legacy text handling")
    }
}
