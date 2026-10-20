import Foundation
import CoreGraphics

@main
struct ConfigurationTests {
    static func verifyTrackpadNativeEvents() {
        let gestures: [MagicMouseGesture] = [.tipTapLeft, .tipTapRight, .tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipTapThreeLeft, .tipTapThreeRight]
        for gesture in gestures {
            let count = gesture.fingers - 1
            let anchors = (0..<count).map { MouseContact(id: Int32($0), x: 0.4 + Double($0) * 0.1, y: 0.5) }
            let x = gesture == .tipTapTwoMiddle ? 0.45 : (gesture.rawValue.hasSuffix("left") ? 0.2 : 0.8)
            let tip = MouseContact(id: 20, x: x, y: 0.5)
            var settings = MagicMouseSettings()
            settings.tipTap = TipTapTuning(); settings.tipTapSpacingGeometry = .surface
            settings.bindings = [gesture: .missionControl]
            for event in [CGEventType.scrollWheel, .leftMouseDown, .rightMouseDown] {
                for isTrackpad in [false, true] {
                    var recognizer = MagicMouseRecognizer()
                    _ = recognizer.consume(anchors, timestamp: 1, settings: settings)
                    _ = recognizer.consume(anchors + [tip], timestamp: 1.4, settings: settings)
                    precondition(recognizer.ownsFixedFingerSession)
                    _ = LowFingerTrackpadInput.handleNativeEvent(event, confirmedTrackpad: isTrackpad, timestamp: 1.45, recognizer: &recognizer)
                    let result = recognizer.consume(anchors, timestamp: 1.52, settings: settings)
                    let physicalClick = isTrackpad && event != .scrollWheel
                    precondition(result == (physicalClick ? nil : gesture), "Native event arbitration for \(gesture), \(event), trackpad \(isTrackpad)")
                }
            }
            // macOS can post button events during a TipTap sequence. The
            // interrupted tap must be rejected, but button-up plus tip lift
            // should allow fresh taps without lifting the resting chord.
            for down in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
                let up: CGEventType = down == .leftMouseDown ? .leftMouseUp : (down == .rightMouseDown ? .rightMouseUp : .otherMouseUp)
                var r = MagicMouseRecognizer()
                _ = r.consume(anchors, timestamp: 10, settings: settings)
                _ = r.consume(anchors + [tip], timestamp: 10.4, settings: settings)
                precondition(r.consume(anchors, timestamp: 10.52, settings: settings) == gesture)
                _ = r.consume(anchors + [tip], timestamp: 10.6, settings: settings)
                _ = LowFingerTrackpadInput.handleNativeEvent(down, confirmedTrackpad: true, timestamp: 10.64, recognizer: &r)
                precondition(r.consume(anchors, timestamp: 10.72, settings: settings) == nil, "A held mouse button blocks TipTaps")
                _ = r.consume(anchors + [tip], timestamp: 10.8, settings: settings)
                _ = LowFingerTrackpadInput.handleNativeEvent(up, confirmedTrackpad: true, timestamp: 10.82, recognizer: &r)
                precondition(r.consume(anchors + [tip], timestamp: 10.84, settings: settings) == nil, "Button release cannot revive a held tip")
                precondition(r.consume(anchors, timestamp: 10.92, settings: settings) == nil, "The interrupted tip release only rearms")
                for time in [11.0, 11.25, 11.5] {
                    _ = r.consume(anchors + [tip], timestamp: time, settings: settings)
                    precondition(r.consume(anchors, timestamp: time + 0.12, settings: settings) == gesture, "Fresh trackpad TipTap repeats after button-up without lifting anchors: \(gesture)")
                }
            }
            // Native button events can follow the tip's release frame. There
            // may be no additional anchor-only frame before the next tap lands.
            do {
                var r = MagicMouseRecognizer()
                _ = r.consume(anchors, timestamp: 20, settings: settings)
                _ = r.consume(anchors + [tip], timestamp: 20.4, settings: settings)
                precondition(r.consume(anchors, timestamp: 20.52, settings: settings) == gesture)
                _ = LowFingerTrackpadInput.handleNativeEvent(.leftMouseDown, confirmedTrackpad: true, timestamp: 20.53, recognizer: &r)
                _ = LowFingerTrackpadInput.handleNativeEvent(.leftMouseUp, confirmedTrackpad: true, timestamp: 20.55, recognizer: &r)
                _ = r.consume(anchors + [tip], timestamp: 20.62, settings: settings)
                precondition(r.consume(anchors, timestamp: 20.74, settings: settings) == gesture, "Button-up rearms the observed resting chord before the next tip lands")
            }
            // Native scroll cannot turn a raw moving finger into a valid tap.
            var moving = MagicMouseRecognizer()
            _ = moving.consume(anchors, timestamp: 2, settings: settings)
            _ = moving.consume(anchors + [tip], timestamp: 2.4, settings: settings)
            _ = LowFingerTrackpadInput.handleNativeEvent(.scrollWheel, confirmedTrackpad: true, timestamp: 2.43, recognizer: &moving)
            _ = moving.consume(anchors + [MouseContact(id: 20, x: x, y: 0.7)], timestamp: 2.46, settings: settings)
            precondition(moving.consume(anchors, timestamp: 2.52, settings: settings) == nil)
        }
        var ordinary = MagicMouseRecognizer()
        let points = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.6, y: 0.5)]
        let settings = MagicMouseSettings()
        _ = ordinary.consume(points, timestamp: 4, settings: settings)
        _ = LowFingerTrackpadInput.handleNativeEvent(.scrollWheel, confirmedTrackpad: true, timestamp: 4.05, recognizer: &ordinary)
        precondition(ordinary.consume([], timestamp: 4.12, settings: settings) == nil, "Scrolling still cancels an ordinary tap")
        print("PASS: all seven trackpad TipTaps survive native scroll and unrelated-device events; physical clicks, finger motion and ordinary scroll taps remain rejected")
    }
    @MainActor
    static func main() {
        try! verifyLiveContacts()
        try! renderLiveContactsPreviewIfRequested()
        verifyTrackpadNativeEvents()
        let freshTuning = GlideConfigParser.parse(yaml: "touchpad:\n  device_tuning:\n    trackpad_sensitivity: 0.5")!.deviceTuning
        precondition(freshTuning.trackpadTipTap == .trackpadDefaults && freshTuning.mouseTipTap == .mouseDefaults)
        let savedTuning = GlideConfigParser.parse(yaml: """
        touchpad:
          device_tuning:
            trackpad_tiptap_sensitivity: 0.38
            trackpad_tiptap_two_sensitivity: 0.5
            trackpad_tiptap_three_sensitivity: 0.35
            trackpad_tiptap_two_minimum_distance: 0.03
            trackpad_tiptap_three_minimum_distance: 0.03
            trackpad_tiptap_maximum_distance: 0.55
        """)!.deviceTuning
        precondition(savedTuning.trackpadTipTap == TipTapTuning(), "Explicit saved tuning must not be overwritten by new defaults")
        // Reproduce the crash's stage-worker -> window-mutation handoff without
        // posting UI events or changing permissions in a headless test.
        var stageMutationFinished = false
        DispatchQueue(label: "verification.stage-worker").async {
            precondition(!Thread.isMainThread)
            DesktopActions.performStageWindowMutation {
                precondition(Thread.isMainThread, "Stage window mutations must execute on main")
                stageMutationFinished = true
            }
        }
        let mutationDeadline = Date().addingTimeInterval(3)
        while !stageMutationFinished && Date() < mutationDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(stageMutationFinished, "Stage mutation must not deadlock waiting for main")
        let leftDisplay = DesktopActions.StageDisplay(id: 1, bounds: CGRect(x: -1440, y: 0, width: 1440, height: 900))
        let mainDisplay = DesktopActions.StageDisplay(id: 2, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let aboveDisplay = DesktopActions.StageDisplay(id: 3, bounds: CGRect(x: 0, y: -900, width: 1440, height: 900))
        let displays = [leftDisplay, mainDisplay, aboveDisplay]
        let leftWindow = CGRect(x: -1400, y: 50, width: 900, height: 700)
        precondition(DesktopActions.focusedDisplay(window: leftWindow, pointer: CGPoint(x: 500, y: 500), displays: displays)?.id == 1)
        precondition(DesktopActions.focusedDisplay(window: nil, pointer: CGPoint(x: 500, y: 500), displays: displays)?.id == 2)
        precondition(DesktopActions.displayForWindow(CGRect(x: 20, y: -800, width: 120, height: 100), displays: displays)?.id == 3)
        precondition(DesktopActions.displayForWindow(CGRect(x: -100, y: 30, width: 500, height: 500), displays: displays)?.id == 2)
        precondition(DesktopActions.displayForWindow(CGRect(x: -500, y: 30, width: 600, height: 500), displays: displays)?.id == 1)
        precondition(DesktopActions.displayForWindow(.zero, displays: displays) == nil)
        precondition(DesktopActions.focusedDisplay(window: CGRect(x: 9000, y: 0, width: 100, height: 100), pointer: .zero, displays: displays) == nil)
        precondition(DesktopActions.displayForWindow(CGRect(x: 1920, y: 10, width: 100, height: 100), displays: displays) == nil)
        // A covered strip slides off the screen edge. Recorded on a 2752-wide main
        // display: buttons at x = -240 overlap no display, or a neighbour's.
        let hiddenButton = CGRect(x: -240, y: 221, width: 176, height: 107)
        let mainSpace = DesktopActions.stageSpaceDisplay(identifier: "sm.space", role: "AXGroup",
                                                         frame: mainDisplay.bounds, displays: displays)
        precondition(mainSpace == 2, "The sm.space group stands for its display")
        precondition(DesktopActions.stageDisplayID(buttonFrame: hiddenButton, space: mainSpace, displays: displays) == 2,
                     "A hidden strip's stages still belong to the display of their space")
        precondition(DesktopActions.stageDisplayID(buttonFrame: CGRect(x: -240, y: 30, width: 176, height: 107), space: mainSpace, displays: displays) == 2,
                     "A hidden strip overlapping a neighbouring display stays with its own space")
        precondition(DesktopActions.stageSpaceDisplay(identifier: nil, role: "AXGroup", frame: leftDisplay.bounds, displays: displays) == 1,
                     "An unnamed group sized to a display is that display's space")
        precondition(DesktopActions.stageSpaceDisplay(identifier: nil, role: "AXGroup", frame: CGRect(x: 0, y: 0, width: 300, height: 300), displays: displays) == nil)
        precondition(DesktopActions.stageSpaceDisplay(identifier: nil, role: "AXList", frame: mainDisplay.bounds, displays: displays) == nil)
        precondition(DesktopActions.stageDisplayID(buttonFrame: CGRect(x: 16, y: 218, width: 176, height: 107), space: nil, displays: displays) == 2,
                     "Without a space container the button's own frame decides")
        let desktopNames = [GestureAction.spaceLeftInstant, .spaceRightInstant, .windowSpaceLeft, .windowSpaceRight,
                            .stagePosition, .stageNext, .stagePrevious, .stageMatching, .stageMenu, .stageToggle, .stageRecentToggle]
        precondition(Set(desktopNames).count == 11)
        precondition(desktopNames.allSatisfy { action in GestureAction.catalog.contains { $0.actions.contains(action) } })
        let partialOptions = try! JSONDecoder().decode(DesktopActionOptions.self, from: Data(#"{"stagePosition":2}"#.utf8))
        precondition(partialOptions.stagePosition == 2 && partialOptions.stageApps.isEmpty && !partialOptions.allowAnimatedFallback)
        var invalidTarget = GestureRule(fingers: 2, direction: .tap, action: .stageMatching)
        precondition(!invalidTarget.isActive)
        invalidTarget.desktopOptions.stagePosition = -9
        invalidTarget.desktopOptions.stageApps = [" com.apple.finder ", "com.apple.finder", " "]
        invalidTarget.desktopOptions.windowTitle = "  project  "
        let cleanTarget = Settings.normalizedRule(invalidTarget)
        precondition(cleanTarget.desktopOptions.stagePosition == 1 && cleanTarget.desktopOptions.stageApps == ["com.apple.finder"] && cleanTarget.desktopOptions.windowTitle == "project")
        var desktopConfig = GlideConfigParser.parse(yaml: """
        touchpad:
          gesture_schema_version: 1
          gestures:
            - type: tap
              fingers: 2
              device: magicMouse
              action: "Stage Manager: Activate Stage Containing Specific Apps / Windows"
              stage_position: 3
              stage_apps:
                - com.brave.Browser
                - com.apple.finder
              stage_window_title: "Work: project"
              allow_animated_fallback: true
        """)!
        Settings.shared.apply(desktopConfig)
        let desktopRule = Settings.shared.rules[0]
        precondition(desktopRule.desktopOptions.stageApps.count == 2 && desktopRule.desktopOptions.stagePosition == 3)
        precondition(desktopRule.desktopOptions.windowTitle == "Work: project" && desktopRule.isActive)
        let desktopRoundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(GlideConfig.fromSettings()))!.toRules()[0]
        precondition(desktopRoundtrip.desktopOptions == desktopRule.desktopOptions)
        let desktopJSON = try! JSONEncoder().encode(desktopRule)
        precondition(try! JSONDecoder().decode(GestureRule.self, from: desktopJSON).desktopOptions == desktopRule.desktopOptions)
        desktopConfig.deviceTuning.mouseTipTapMinimum = 0.17
        desktopConfig.deviceTuning.trackpadTipTapAnchor = 0.42
        precondition(GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(desktopConfig))!.deviceTuning == desktopConfig.deviceTuning)
        let spaces: [[String: Any]] = [["id64": NSNumber(value: 10), "type": 0], ["id64": NSNumber(value: 20), "type": 4], ["id64": NSNumber(value: 30), "type": 0]]
        precondition(DesktopActions.adjacentID(in: spaces, current: 10, next: true, desktopsOnly: false) == 20)
        precondition(DesktopActions.adjacentID(in: spaces, current: 10, next: true, desktopsOnly: true) == nil)
        precondition(DesktopActions.adjacentID(in: spaces, current: 10, next: false, desktopsOnly: false) == nil)
        var stageOrder: [String] = []
        precondition(DesktopActions.nextStageKey(visible: ["A", "B", "C"], previous: nil, forward: true, order: &stageOrder) == "A")
        precondition(DesktopActions.nextStageKey(visible: ["C", "B"], previous: "A", forward: true, order: &stageOrder) == "B")
        precondition(DesktopActions.nextStageKey(visible: ["A", "C"], previous: "B", forward: false, order: &stageOrder) == "A")
        // macOS can expose unnamed Stage Manager groups through their role
        // hierarchy and member IDs. Never treat unrelated Dock/MC buttons as stages.
        func stageButton(host: String = "com.apple.WindowManager", role: String = "AXButton",
                         parent: String = "AXList", grandparent: String = "AXGroup",
                         actions: [String] = ["AXPress"], members: [UInt32] = [42],
                         descriptors: [String] = [], insideStrip: Bool = false) -> Bool {
            DesktopActions.isStageButton(host: host, role: role, parentRole: parent, grandparentRole: grandparent,
                descriptors: descriptors, actions: actions, windowIDs: members, insideStrip: insideStrip)
        }
        precondition(stageButton())
        precondition(!stageButton(host: "com.apple.dock"))
        precondition(!stageButton(parent: "AXGroup"))
        precondition(!stageButton(grandparent: "AXWindow"))
        precondition(!stageButton(members: []))
        precondition(stageButton(actions: [])) // Member windows don't require AXPress on the thumbnail.
        precondition(!stageButton(actions: [], members: []))
        precondition(stageButton(parent: "AXGroup", members: [], descriptors: ["StageManagerPile"]))
        precondition(stageButton(parent: "AXGroup", members: [], insideStrip: true))
        precondition(stageButton(parent: "AXGroup", actions: ["AXPress", "AXAddToStage"], members: []))
        precondition(!stageButton(host: "com.example.app", actions: ["AXPress", "AXAddToStage"], members: []))
        precondition(DesktopActions.stageIdentity(identifier: "generic-button", labels: ["Browser"], windowIDs: [2]) !=
                     DesktopActions.stageIdentity(identifier: "generic-button", labels: ["Browser"], windowIDs: [3]))
        precondition(DesktopActions.stageIdentity(identifier: "changed", labels: ["New title"], windowIDs: [2, 3]) ==
                     DesktopActions.stageIdentity(identifier: "old", labels: ["Old title"], windowIDs: [3, 2]))
        precondition(DesktopActions.isStageStrip("stage-manager-piles"))
        precondition(DesktopActions.isStageStrip("StageManagerStrip"))
        precondition(!DesktopActions.isStageStrip("stage-manager-piles-42"))
        precondition(DesktopActions.stageIdentity(identifier: "pile-42", labels: ["New title"], windowIDs: [8]) == "windows:8")
        precondition(DesktopActions.stageIdentity(identifier: nil, labels: [], windowIDs: [4, 2, 4]) == "windows:2,4")
        precondition(DesktopActions.stageIdentity(identifier: "stage-manager-pile", labels: ["Browser"], windowIDs: [4]) == "windows:4")
        precondition(DesktopActions.stageIdentity(identifier: nil, labels: ["Brave", "Finder"], windowIDs: []) == DesktopActions.stageIdentity(identifier: nil, labels: ["Finder", "Brave"], windowIDs: []))
        precondition(DesktopActions.stageIdentity(identifier: nil, labels: [" "], windowIDs: []) == nil)
        precondition(DesktopActions.stageActivationConfirmed(members: [10, 11], before: 1, after: 11))
        precondition(!DesktopActions.stageActivationConfirmed(members: [10, 11], before: 1, after: 2))
        precondition(!DesktopActions.stageActivationConfirmed(members: [10], before: 1, after: nil))
        precondition(DesktopActions.stageActivationConfirmed(members: [10], before: 10, after: 10))
        precondition(!DesktopActions.stageActivationConfirmed(members: [], before: nil, after: 10))
        precondition(DesktopActions.stageActivationConfirmed(members: [], before: 1, after: 10))
        stageOrder = []
        precondition(DesktopActions.nextStageKey(visible: ["A", "B", "C"], previous: nil, forward: false, order: &stageOrder) == "C")
        precondition(DesktopActions.nextStageKey(visible: ["A", "B"], previous: "C", forward: false, order: &stageOrder) == "B")
        precondition(DesktopActions.nextStageKey(visible: ["C", "A"], previous: "B", forward: true, order: &stageOrder) == "C")
        // Rapid switching can produce incomplete/reordered strip snapshots.
        stageOrder = ["A", "B", "C", "D"]
        precondition(DesktopActions.nextStageKey(visible: ["D", "C"], previous: "A", forward: true, order: &stageOrder) == "C")
        precondition(DesktopActions.nextStageKey(visible: ["D", "A", "B"], previous: "C", forward: false, order: &stageOrder) == "B")
        var cycle = DesktopActions.CycleState(last: "A", order: ["A", "B", "C"])
        precondition(cycle.next(visible: ["B", "C"], current: "A", forward: true) == "B")
        // B failed to activate; another forward tap must try C, not B again.
        precondition(cycle.next(visible: ["B", "C"], current: "A", forward: true) == "C")
        cycle.last = "C"
        precondition(cycle.next(visible: ["A", "B"], current: "C", forward: false) == "B")
        cycle.last = "B"
        precondition(cycle.next(visible: ["A", "C"], current: "B", forward: true) == "C")
        // User manually focused A: discard the old requested cursor.
        precondition(cycle.next(visible: ["B", "C"], current: "A", forward: true) == "B")
        precondition(cycle.currentKey(groups: ["A": [10], "B": [20], "C": [30]], focused: 10) == "A")
        precondition(cycle.currentKey(groups: ["B": [20], "C": [30]], focused: 10) == "A", "Current stage disappears from the strip")
        precondition(cycle.currentKey(groups: ["B": [20], "C": [30]], focused: 99) == nil)
        var otherDisplay = DesktopActions.CycleState()
        precondition(otherDisplay.next(visible: ["X", "Y"], current: nil, forward: false) == "Y")
        precondition(cycle.attempted == "B")
        precondition(otherDisplay.next(visible: [], current: nil, forward: true) == nil)
        let stageScreen = DesktopActions.StageDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let secondScreen = DesktopActions.StageDisplay(id: 2, bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let screens = [stageScreen, secondScreen]
        precondition(DesktopActions.memberIsOnDisplay(nativeDisplay: 1, frame: CGRect(x: -3000, y: 0, width: 800, height: 600), target: stageScreen, displays: screens))
        precondition(!DesktopActions.memberIsOnDisplay(nativeDisplay: 2, frame: CGRect(x: 100, y: 100, width: 800, height: 600), target: stageScreen, displays: screens))
        precondition(DesktopActions.memberIsOnDisplay(nativeDisplay: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 600), target: stageScreen, displays: screens))
        precondition(!DesktopActions.memberIsOnDisplay(nativeDisplay: 0, frame: nil, target: stageScreen, displays: screens))
        precondition(GLDWDisplayForWindow(0) == 0 && !GLDWFocusWindow(0, 0))
        print("PASS: Stage Manager failed-target progress, transient strip order, reversals, external focus and native display ownership")
        print("PASS: 11 desktop actions, target options round-trip, Space bounds and stage cycling")

        let oneFingerNames = ["1 Finger Tap", "1 Finger Tap Left", "1 Finger Tap Right", "1 Finger Middle Click", "1 Finger Tap Middle", "1 Finger Tap Above Apple"]
        let oneFingerMenu = GestureDirection.available(fingers: 1, device: .magicMouse)
        precondition(Array(oneFingerMenu.prefix(6)).map { $0.title(fingers: 1) } == oneFingerNames)
        let fourFingerMenu = GestureDirection.available(fingers: 4, device: .magicMouse)
        precondition(fourFingerMenu.map { $0.title(fingers: 4) } == ["4 Finger Click", "4 Finger Swipe Up", "4 Finger Swipe Down", "4 Finger Swipe Left", "4 Finger Swipe Right"])
        precondition(!GestureDirection.available(fingers: 1, device: .trackpad).contains(.middleTap))
        precondition(GestureDirection(rawValue: "Tap Left Side") == .leftTap && GestureDirection(rawValue: "Tap Right Side") == .rightTap)
        func mouseRule(_ direction: GestureDirection, fingers: Int = 1) -> GestureRule {
            var rule = GestureRule(fingers: fingers, direction: direction, action: .showDesktop)
            rule.device = .magicMouse
            return rule
        }
        let regionRules = Array(oneFingerMenu.prefix(6)).map { mouseRule($0) }
        let fourRules = fourFingerMenu.map { mouseRule($0, fingers: 4) }
        Settings.shared.rules = regionRules + fourRules
        let newRoundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(GlideConfig.fromSettings()))!.toRules()
        precondition(newRoundtrip.count == 11 && newRoundtrip.allSatisfy { $0.device == .magicMouse })
        precondition(Set(newRoundtrip.filter { $0.fingers == 1 }.map(\.direction)) == Set(regionRules.map(\.direction)))
        precondition(Set(newRoundtrip.filter { $0.fingers == 4 }.map(\.direction)) == Set(fourFingerMenu))
        for rule in regionRules + fourRules {
            precondition(try! JSONDecoder().decode(GestureRule.self, from: JSONEncoder().encode(rule)) == rule)
        }
        let fourRecognition = MouseRuleBridge.recognitionSettings(rules: fourRules, device: .magicMouse)
        precondition(MagicMouseGesture.allCases.filter { $0.fingers == 4 && !$0.trackpadOnly }.allSatisfy { fourRecognition.action(for: $0) != .none })
        let horizontalFour = MouseRuleBridge.recognitionSettings(rules: [mouseRule(.swipeLeft, fingers: 4)], device: .magicMouse)
        precondition(horizontalFour.reservedScrollAxes(fingers: 4) == .horizontal && horizontalFour.reservedScrollAxes(fingers: 1).isEmpty)
        let genericTap = mouseRule(.tap)
        let genericRecognition = MouseRuleBridge.recognitionSettings(rules: [genericTap], device: .magicMouse)
        precondition(genericRecognition.action(for: .oneFingerMiddleClick) == .none, "General tap must not enable a physical click")
        for direction in [GestureDirection.middleTap, .aboveAppleTap] {
            let regionalRecognition = MouseRuleBridge.recognitionSettings(rules: [mouseRule(direction)], device: .magicMouse)
            precondition(regionalRecognition.action(for: .leftTap) != .none && regionalRecognition.action(for: .rightTap) != .none)
        }
        func regionalMatch(_ rules: [GestureRule], x: Double = 0.48, y: Double = 0.25, app: String? = nil, modifiers: CapturedModifiers = CapturedModifiers([]), fullscreen: Bool = false) -> GestureRule? {
            MouseRuleBridge.resolve(in: rules, gesture: x < 0.5 ? .leftTap : .rightTap, device: .magicMouse,
                modifiers: modifiers, location: MouseContact(id: 1, x: x, y: y), bundleID: app, isFullscreen: fullscreen)
        }
        let sideTap = mouseRule(.leftTap), centerTap = mouseRule(.middleTap), logoTap = mouseRule(.aboveAppleTap)
        precondition(regionalMatch([logoTap, sideTap, genericTap, centerTap])?.id == logoTap.id)
        precondition(regionalMatch([sideTap, genericTap, centerTap], y: 0.6)?.id == centerTap.id)
        precondition(regionalMatch([genericTap, sideTap], x: 0.2)?.id == sideTap.id)
        precondition(regionalMatch([genericTap, sideTap], x: 0.8)?.id == genericTap.id)
        precondition(regionalMatch([logoTap], x: 0.2) == nil)
        var scopedTap = genericTap; scopedTap.id = UUID(); scopedTap.appFilters = ["com.brave.Browser", "com.apple.Safari"]
        precondition(regionalMatch([scopedTap, logoTap], app: "com.brave.Browser")?.id == scopedTap.id, "App scope takes priority over Any App region")
        precondition(regionalMatch([scopedTap, logoTap], app: "com.apple.finder")?.id == logoTap.id)
        var shiftedLogo = logoTap; shiftedLogo.modifierFilter = .shiftHeld
        precondition(regionalMatch([shiftedLogo, centerTap])?.id == centerTap.id, "An unmatched regional modifier falls back to the next region")
        precondition(regionalMatch([shiftedLogo, centerTap], modifiers: CapturedModifiers(.shift))?.id == shiftedLogo.id)
        var fullscreenLogo = logoTap; fullscreenLogo.windowStateFilter = .fullscreen
        precondition(regionalMatch([fullscreenLogo, centerTap])?.id == centerTap.id)
        precondition(regionalMatch([fullscreenLogo, centerTap], fullscreen: true)?.id == fullscreenLogo.id)
        print("PASS: exact one/four-finger menu names, persisted mouse rules, region/app/modifier/window arbitration, opt-in clicks and four-finger scroll axes")

        let addedTrackpad: [(Int, GestureDirection)] = [(1, .circleClockwise), (1, .circleCounterClockwise), (1, .cornerBottomLeft), (1, .cornerBottomRight), (1, .cornerTopLeft), (1, .cornerTopRight), (3, .tapTop), (3, .tapBottom), (3, .tipSwipeLeftLeft), (3, .tipSwipeLeftRight), (4, .tap), (4, .doubleTap), (4, .tipTapThreeLeft), (4, .tipTapThreeRight)]
        let addedRules = addedTrackpad.map { count, direction -> GestureRule in
            precondition(GestureDirection.available(fingers: count, device: .trackpad).contains(direction))
            return GestureRule(fingers: count, direction: direction, action: .showDesktop)
        }
        Settings.shared.rules = addedRules
        let trackpadRoundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(GlideConfig.fromSettings()))!.toRules()
        precondition(trackpadRoundtrip.count == addedRules.count && trackpadRoundtrip.allSatisfy { $0.device == .trackpad })
        for rule in addedRules {
            precondition(trackpadRoundtrip.contains { $0.fingers == rule.fingers && $0.direction == rule.direction })
        }
        let supplemental = LowFingerTrackpadInput.recognitionSettings(rules: addedRules)
        for gesture in MagicMouseGesture.allCases where gesture.trackpadOnly {
            precondition(supplemental.action(for: gesture) != .none)
            precondition(LowFingerTrackpadInput.direction(for: gesture) != nil)
            precondition(!GestureDirection.available(fingers: gesture.fingers, device: .magicMouse).contains(MouseRuleBridge.direction(gesture, device: .magicMouse)))
        }
        precondition(supplemental.action(for: .fourFingerClick) == .none, "Existing trackpad four-finger click stays on its original engine")
        let upper = GestureRule(fingers: 3, direction: .tapTop, action: .showDesktop)
        let lower = GestureRule(fingers: 3, direction: .tapBottom, action: .missionControl)
        let generalThree = GestureRule(fingers: 3, direction: .tap, action: .maximizeWindow)
        for (y, expected) in [(0.2, lower.id), (0.8, upper.id)] {
            let match = MouseRuleBridge.resolve(in: [upper, lower, generalThree], gesture: .threeFingerTap, device: .trackpad, modifiers: CapturedModifiers([]), location: MouseContact(id: 1, x: 0.5, y: y), bundleID: nil)
            precondition(match?.id == expected)
        }
        var tipConfig = GlideConfig()
        tipConfig.deviceTuning.trackpadTipTap.sensitivity = 0.71
        tipConfig.deviceTuning.trackpadTipTap.twoFingerSensitivity = 0.62
        tipConfig.deviceTuning.trackpadTipTap.threeFingerSensitivity = 0.43
        tipConfig.deviceTuning.trackpadTipTap.allowFingerMovement = true
        tipConfig.deviceTuning.trackpadTipTap.twoFingerMinimumDistance = 0.09
        tipConfig.deviceTuning.trackpadTipTap.threeFingerMinimumDistance = 0.12
        tipConfig.deviceTuning.trackpadTipTap.maximumDistance = 0.65
        tipConfig.deviceTuning.mouseTipTap.sensitivity = 0.82
        tipConfig.deviceTuning.mouseTipTap.twoFingerSensitivity = 0.27
        tipConfig.deviceTuning.mouseTipTap.allowSensitiveTipTaps = true
        let tipRoundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(tipConfig))!
        precondition(tipRoundtrip.deviceTuning == tipConfig.deviceTuning, "All per-device TipTap sliders/toggles survive export/import")
        precondition(tipRoundtrip.deviceTuning.applying(to: MagicMouseSettings(), device: .magicMouse).tipTap == tipConfig.deviceTuning.mouseTipTap)
        precondition(tipRoundtrip.deviceTuning.applying(to: MagicMouseSettings(), device: .trackpad).tipTap == tipConfig.deviceTuning.trackpadTipTap)
        precondition(GlideConfigParser.parse(yaml: "touchpad:\n  device_tuning:\n    trackpad_sensitivity: 0.5")!.deviceTuning.mouseTipTap == .mouseDefaults)
        precondition(GestureDirection.doubleTap.title(fingers: 4) == "4 Finger Double Tap" && GestureDirection.forceClick.title(fingers: 4) == "4 Finger FORCE Click")
        print("PASS: new trackpad menus, all gesture YAML round-trips, top/bottom routing, no duplicate high-finger recognition, per-device TipTap persistence and migration")

        let threeDirections = GestureDirection.available(fingers: 3, device: .magicMouse)
        precondition(threeDirections.count == 12)
        precondition(threeDirections.allSatisfy { GestureDirection.available(fingers: 3, device: .trackpad).contains($0) })
        // Nothing reserves three-finger left/right any more: all twelve survive on
        // both devices.
        for device in [GestureDevice.trackpad, .magicMouse] {
            let rules = threeDirections.map { direction -> GestureRule in
                var rule = GestureRule(fingers: 3, direction: direction, action: .showDesktop)
                rule.device = device
                return rule
            }
            Settings.shared.rules = rules
            let roundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(GlideConfig.fromSettings()))!.toRules()
            precondition(Set(roundtrip.map(\.direction)) == Set(threeDirections))
            precondition(roundtrip.allSatisfy { $0.device == device && $0.fingers == 3 })
            let recognition = MouseRuleBridge.recognitionSettings(rules: rules, device: device)
            for gesture in MagicMouseGesture.allCases where gesture.fingers == 3 {
                let shouldRecognize = threeDirections.contains(MouseRuleBridge.direction(gesture, device: device)) && (device == .magicMouse ? !gesture.trackpadOnly : gesture.usesSupplementalTrackpadRecognizer)
                precondition((recognition.action(for: gesture) != .none) == shouldRecognize, "Trackpad keeps existing three-finger click/swipe recognition without duplicating it")
            }
        }
        var scrollingConfig = GlideConfig()
        scrollingConfig.magicMouse.invertVerticalScrolling = true
        scrollingConfig.magicMouse.invertHorizontalScrolling = true
        let restoredScrolling = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(scrollingConfig))!.magicMouse
        precondition(restoredScrolling.invertVerticalScrolling && restoredScrolling.invertHorizontalScrolling)
        precondition(MagicMouseGesture.allCases.allSatisfy { restoredScrolling.action(for: $0) == scrollingConfig.magicMouse.action(for: $0) })
        precondition(!MagicMouseSettings().hasScrollInversion)
        for vertical in [false, true] {
            for horizontal in [false, true] {
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 3, wheel1: 23, wheel2: -7, wheel3: 2)!
                event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
                let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3]
                let before = fields.map { event.getDoubleValueField($0) }
                MagicMouseScrollFilter.invert(event, vertical: vertical, horizontal: horizontal)
                for (index, field) in fields.enumerated() {
                    let sign = (index < 3 ? vertical : (index < 6 ? horizontal : false)) ? -1.0 : 1.0
                    precondition(event.getDoubleValueField(field) == before[index] * sign)
                }
                precondition(event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 2 && event.getIntegerValueField(.scrollWheelEventScrollPhase) == 4)
            }
        }
        print("PASS: 12 three-finger menu entries on both devices, dedicated routing, configuration persistence, independent scroll inversion with native phases")
        var horizontalMouse = MagicMouseSettings()
        horizontalMouse.bindings[.swipeLeft] = .previousApp
        horizontalMouse.bindings[.swipeRight] = .nextApp
        let horizontalAxes = horizontalMouse.reservedScrollAxes(fingers: 2)
        precondition(horizontalAxes == .horizontal)
        precondition(horizontalMouse.reservedScrollAxes(fingers: 3).isEmpty)
        let verticalEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 24, wheel2: 0, wheel3: 0)!
        let verticalFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
        let verticalBefore = verticalFields.map { verticalEvent.getDoubleValueField($0) }
        precondition(!MagicMouseScrollFilter.filter(verticalEvent, reserving: horizontalAxes), "Horizontal gestures must preserve vertical scrolling")
        precondition(verticalFields.map { verticalEvent.getDoubleValueField($0) } == verticalBefore)
        let diagonalEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 20, wheel2: 2, wheel3: 0)!
        diagonalEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let diagonalVertical = verticalFields.map { diagonalEvent.getDoubleValueField($0) }
        precondition(!MagicMouseScrollFilter.filter(diagonalEvent, reserving: horizontalAxes), "Horizontal jitter must not swallow a vertical scroll event")
        precondition(verticalFields.map { diagonalEvent.getDoubleValueField($0) } == diagonalVertical)
        for field: CGEventField in [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2] {
            precondition(diagonalEvent.getDoubleValueField(field) == 0)
        }
        precondition(diagonalEvent.getIntegerValueField(.scrollWheelEventMomentumPhase) == 2)
        let horizontalEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -20, wheel3: 0)!
        precondition(MagicMouseScrollFilter.filter(horizontalEvent, reserving: horizontalAxes), "Assigned horizontal motion remains reserved for the custom gesture")
        let phaseEnd = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
        phaseEnd.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        precondition(!MagicMouseScrollFilter.filter(phaseEnd, reserving: horizontalAxes))
        precondition(phaseEnd.getIntegerValueField(.scrollWheelEventScrollPhase) == 4)
        horizontalMouse.bindings = [.swipeUp: .showDesktop]
        precondition(horizontalMouse.reservedScrollAxes(fingers: 2) == .vertical)
        let sideways = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: 20, wheel3: 0)!
        precondition(!MagicMouseScrollFilter.filter(sideways, reserving: .vertical))
        precondition(sideways.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 20)
        precondition(sideways.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == 0)
        horizontalMouse.enabled = false
        precondition(horizontalMouse.reservedScrollAxes(fingers: 2).isEmpty)
        print("PASS: horizontal gestures preserve vertical/diagonal scrolling, momentum and phase; vertical gestures preserve horizontal scrolling")

        var tuningFixture = GlideConfig()
        tuningFixture.deviceTuning.mouseSensitivity = 0.1
        tuningFixture.deviceTuning.trackpadSensitivity = 0.9
        tuningFixture.deviceTuning.mousePointerSpeed = 1.7
        tuningFixture.deviceTuning.trackpadPointerSpeed = 0.8
        let tuningRoundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(tuningFixture))!
        precondition(tuningRoundtrip.deviceTuning == tuningFixture.deviceTuning)
        Settings.shared.apply(tuningRoundtrip)
        precondition(GlideConfig.fromSettings().deviceTuning == tuningFixture.deviceTuning)
        precondition(GlideConfigParser.parse(yaml: "touchpad:\n  preferences:\n    haptic_feedback: false\n")!.deviceTuning == DeviceTuningSettings())
        let easy = tuningFixture.deviceTuning.applying(to: MagicMouseSettings(), device: .magicMouse)
        let hard = tuningFixture.deviceTuning.applying(to: MagicMouseSettings(), device: .trackpad)
        precondition(easy.swipeDistance < hard.swipeDistance && easy.tapMovement > hard.tapMovement)
        var defaultMouseTuning = MagicMouseSettings(); defaultMouseTuning.tipTap = .mouseDefaults
        defaultMouseTuning.tipTapSpacingGeometry = .magicMouse
        precondition(DeviceTuningSettings().applying(to: MagicMouseSettings(), device: .magicMouse) == defaultMouseTuning)
        precondition(DeviceTuningSettings().applying(to: defaultMouseTuning, device: .trackpad).tipTapSpacingGeometry == .surface)
        let reloadedMouse = tipRoundtrip.deviceTuning.applying(to: MagicMouseSettings(), device: .magicMouse)
        precondition(reloadedMouse.tipTapSpacingGeometry == .magicMouse)
        let wideMouseAnchors = [MouseContact(id: 1, x: 0.48, y: 0.7), MouseContact(id: 2, x: 0.88, y: 0.75)]
        let wideMouseTip = MouseContact(id: 3, x: 0.12, y: 0.12)
        precondition(reloadedMouse.tipTap.allowsSpacing(wideMouseTip, anchors: wideMouseAnchors, geometry: reloadedMouse.tipTapSpacingGeometry))
        precondition(NativePointerSpeed.acceleration(original: 45056, multiplier: 1) == 45056)
        precondition(NativePointerSpeed.acceleration(original: 45056, multiplier: 2) > 45056)
        precondition(NativePointerSpeed.acceleration(original: 45056, multiplier: 0.5) < 45056)
        print("PASS: independent device tuning, persistence, sensitivity direction, native speed reset math")
        var config = GlideConfig()
        config.magicMouse.enabled = false
        config.magicMouse.tapDuration = 0.31
        config.magicMouse.tapMovement = 0.04
        config.magicMouse.swipeDistance = 0.27
        for gesture in MagicMouseGesture.allCases { config.magicMouse.bindings[gesture] = .volumeDown }
        config.magicMouse.bindings[.twoFingerTap] = MagicMouseAction.none
        let serialized = GlideConfigSerializer.serialize(config)
        guard let decoded = GlideConfigParser.parse(yaml: serialized) else { fatalError("Cannot decode exported configuration") }
        precondition(decoded.magicMouse == config.magicMouse, "Mouse settings do not round-trip")
        Settings.shared.apply(decoded)
        precondition(GlideConfig.fromSettings().magicMouse == config.magicMouse, "Settings bridge lost mouse configuration")
        guard let legacy = GlideConfigParser.parse(yaml: "touchpad:\n  preferences:\n    haptic_feedback: false\n") else { fatalError("Legacy config failed") }
        precondition(legacy.magicMouse == MagicMouseSettings(), "Legacy configs need defaults")
        let unknown = GlideConfigParser.parse(yaml: "touchpad:\n  magic_mouse:\n    two_finger_tap: Unknown Action\n    swipe_distance: -8\n")!
        precondition(unknown.magicMouse.action(for: .twoFingerTap) == .none)
        precondition(unknown.magicMouse.swipeDistance == 0.1)
        let reordered = GlideConfigParser.parse(yaml: "touchpad:\n  magic_mouse:\n    enabled: false\n  edge_controls:\n    enabled: false\n")!
        precondition(!reordered.magicMouse.enabled && !reordered.edgeControls.enabled)
        precondition(MemoryLayout<GLDMTTouch>.stride == 96, "Unexpected multitouch ABI layout")
        precondition(MemoryLayout<GLDMTTouch>.offset(of: \.normalized) == 32)
        let trackpadRules = [GestureRule(fingers: 1, direction: .tap, action: .showDesktop),
                             GestureRule(fingers: 2, direction: .swipeRight, action: .missionControl)]
        var fixture = GlideConfigParser.parse(yaml: """
        touchpad:
          gestures:
            - type: tap
              fingers: 1
              action: "Show Desktop"
            - type: swipe
              direction: right
              fingers: 2
              action: "Mission Control"
        """)!
        fixture.magicMouse = config.magicMouse
        Settings.shared.apply(fixture)
        let exported = GlideConfig.fromSettings()
        let imported = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(exported))!
        let restored = imported.toRules()
        precondition(restored.contains { $0.fingers == 1 && $0.direction == .tap && $0.action == .showDesktop })
        precondition(restored.contains { $0.fingers == 2 && $0.direction == .swipeRight })
        precondition(imported.magicMouse == config.magicMouse, "Trackpad edits must not alter mouse bindings")
        let recognition = LowFingerTrackpadInput.recognitionSettings(rules: trackpadRules)
        precondition(recognition.enabled && recognition.action(for: .leftTap) != .none && recognition.action(for: .rightTap) != .none)
        precondition(recognition.hasSwipes(fingers: 2) && !recognition.hasSwipes(fingers: 1))
        precondition(!LowFingerTrackpadInput.recognitionSettings(rules: []).enabled)
        var draft = trackpadRules[0]; draft.isDraft = true
        precondition(!LowFingerTrackpadInput.recognitionSettings(rules: [draft]).enabled)
        var keyboard = trackpadRules[0]; keyboard.isKeyboardBinding = true
        precondition(!LowFingerTrackpadInput.recognitionSettings(rules: [keyboard]).enabled)
        precondition(Settings.normalizedRule(trackpadRules[0]).fingers == 1)
        precondition(PreferencesDevice.magicMouse.tabs == [.gestures, .tuning, .inputMonitoring])
        precondition(PreferencesDevice.trackpad.tabs.contains(.edgeControls) && PreferencesDevice.trackpad.tabs.contains(.inputMonitoring))
        var multi = trackpadRules[0]
        multi.appFilters = ["com.apple.Safari", "com.apple.finder"]
        precondition(multi.matchesApp("com.apple.Safari") && multi.matchesApp("com.apple.finder"))
        precondition(!multi.matchesApp("com.apple.Terminal") && !multi.matchesApp(nil))
        var mouse = multi; mouse.device = .magicMouse
        precondition(mouse.matchSignature != multi.matchSignature)
        var legacyRule = multi; legacyRule.appFilters = []; legacyRule.appFilter = "com.apple.Safari"
        precondition(legacyRule.matchesApp("com.apple.Safari") && !legacyRule.matchesApp("com.apple.finder"))
        var general = mouse; general.appFilters = []; general.action = .missionControl
        var scoped = mouse; scoped.action = .showDesktop
        let candidates = [scoped, general]
        let safariMatches = GestureRuleResolver.matchingRules(in: candidates, fingers: 1, direction: .tap,
            modifiers: CapturedModifiers([]), device: .magicMouse, bundleID: "com.apple.Safari")
        precondition(GestureRuleResolver.bestRuleMatch(in: safariMatches, speed: .normal)?.action == .showDesktop,
                     "App-specific rule must beat a later Any App rule")
        let otherMatches = GestureRuleResolver.matchingRules(in: candidates, fingers: 1, direction: .tap,
            modifiers: CapturedModifiers([]), device: .magicMouse, bundleID: "com.apple.Terminal")
        precondition(otherMatches.count == 1 && otherMatches[0].id == general.id)
        var scopedSwipe = scoped; scopedSwipe.direction = .swipeLeft
        let inactiveSettings = MouseRuleBridge.recognitionSettings(rules: [scopedSwipe], device: .magicMouse,
            base: MagicMouseSettings(), bundleID: "com.apple.Terminal")
        precondition(!inactiveSettings.enabled && !inactiveSettings.hasSwipes,
                     "An app-specific swipe must not capture scrolling in other apps")
        let activeSettings = MouseRuleBridge.recognitionSettings(rules: [scopedSwipe], device: .magicMouse,
            base: MagicMouseSettings(), bundleID: "com.apple.Safari")
        precondition(activeSettings.enabled && activeSettings.hasSwipes(fingers: 1))
        var doubleRule = scoped; doubleRule.fingers = 2; doubleRule.direction = .doubleTap
        var singleRule = general; singleRule.fingers = 2; singleRule.direction = .tap
        let outsideApp = MouseRuleBridge.recognitionSettings(rules: [singleRule, doubleRule], device: .magicMouse,
            base: MagicMouseSettings(), bundleID: "com.apple.Terminal")
        var appRecognizer = MagicMouseRecognizer()
        _ = appRecognizer.consume([MouseContact(id: 1, x: 0.3, y: 0.5), MouseContact(id: 2, x: 0.7, y: 0.5)], timestamp: 10, settings: outsideApp)
        precondition(appRecognizer.consume([], timestamp: 10.1, settings: outsideApp) == .twoFingerTap,
                     "A double-tap assigned to another app must not delay or swallow this app's single tap")
        precondition(appRecognizer.pendingTapDeadline == nil)
        print("PASS: app-specific precedence, Any App fallback, context-specific mouse recognition and tap arbitration")
        let json = try! JSONEncoder().encode(mouse)
        precondition(try! JSONDecoder().decode(GestureRule.self, from: json) == mouse)
        var mixed = GlideConfigParser.parse(yaml: """
        touchpad:
          gesture_schema_version: 1
          gestures:
            - type: double_tap
              device: magicMouse
              fingers: 2
              action: "Middle Click"
              app_filters:
                - com.apple.Safari
                - com.apple.finder
            - type: tip_tap_left
              device: trackpad
              fingers: 2
              action: "Show Desktop"
            - type: tip_tap_right
              device: magicMouse
              fingers: 2
              action: "Show Desktop"
            - type: click
              device: trackpad
              fingers: 2
              action: "Mission Control"
        """)!
        Settings.shared.apply(mixed)
        let roundtrip = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(GlideConfig.fromSettings()))!
        precondition(roundtrip.gestureSchemaVersion == 1)
        let mixedRules = roundtrip.toRules()
        precondition(mixedRules.count == 4)
        precondition(mixedRules[0].device == .magicMouse && mixedRules[0].direction == .doubleTap && mixedRules[0].effectiveAppFilters.count == 2)
        precondition(mixedRules[1].direction == .tipTapLeft && mixedRules[2].direction == .tipTapRight && mixedRules[3].direction == .click)
        mixed.gestures = []; Settings.shared.apply(mixed)
        precondition(!Settings.shared.rules.contains { $0.device == .magicMouse }, "Deleted mouse rules must not be resurrected")
        precondition(MouseRuleBridge.migrate(MagicMouseSettings()).contains { $0.device == .magicMouse && $0.action == .middleClick })
        precondition(!AccessibilityPermission.shouldAutomaticallyRequest(granted: true, previouslyRequested: false))
        precondition(!AccessibilityPermission.shouldAutomaticallyRequest(granted: false, previouslyRequested: true))
        precondition(AccessibilityPermission.shouldAutomaticallyRequest(granted: false, previouslyRequested: false))
        precondition(GestureDirection.doubleTap.title(fingers: 2) == "2 Finger Double-Tap")
        precondition(GestureDirection.tipTapLeft.title(fingers: 2) == "TipTap Left (1 Finger Fix)")
        print("PASS: shared mouse rules, multi-app matching, gesture migration, prompt gating")
        print("PASS: device separation, one/two-finger trackpad configuration, opt-in recognition")
        print("PASS: configuration round-trip, legacy import, unknown actions, normalization, reordered sections, shared ABI")
        ConfigAuditTests.run()
    }
}
