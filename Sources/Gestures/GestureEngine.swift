import Cocoa
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - GestureEngine
// ─────────────────────────────────────────────

final class GestureEngine {

    // MARK: - Components
    private(set) var inputManager: GestureInputManager!
    private(set) var processor: GestureProcessor!
    
    // MARK: - State
    private(set) var phase: GesturePhase = .idle
    private var reciprocalToken: ReciprocalToken?
    /// Direction + finger count of the most recently fired swipe rule.
    /// Used to detect back-to-back same-direction gestures (toggles) so we don't
    /// leave a stale reciprocal token pointing the other way.
    private var lastFiredSwipe: (fingers: Int, direction: GestureDirection)?
    private(set) var isRunning = false


    /// macOS accessibility zoom is "double-tap three fingers, then drag". A brief,
    /// motionless 3-finger tap followed by an immediate 3-finger re-touch is that
    /// zoom drag — the whole second touch session must not trigger any gesture.
    private var touchSessionStart: (time: TimeInterval, cx: Float, cy: Float)?
    private var touchSessionMovement: Float = 0
    private var lastThreeFingerTapEnd: TimeInterval = 0
    private var isSystemZoomSession = false
    /// Longest contact still considered a "tap" (system double-tap taps are ~0.1s).
    private let tapMaxDuration: TimeInterval = 0.25
    /// Max centroid travel (normalized) for a contact to count as a tap.
    private let tapMaxMovement: Float = 0.025
    /// Max gap between tap release and the zoom drag's re-touch.
    private let doubleTapWindow: TimeInterval = 0.4

    /// A normal click deferred until we know whether it's actually a force click.
    /// Resolved by either a mouse-up (→ normal click) or a deep press (→ force click).
    private var pendingClick: (rule: GestureRule, fingers: Int)?
    /// Safety net that flushes a pending click if a mouse-up event is ever missed.
    private var pendingClickTimeout: DispatchWorkItem?
    /// Upper bound before a deferred click is force-flushed as a normal click.
    private let pendingClickSafetyTimeout: TimeInterval = 0.7

    /// Pending Tap & Hold — fires when fingers rest motionless past tapHoldDuration.
    private var holdWorkItem: DispatchWorkItem?
    private var holdArmedFingerCount = 0
    private var holdStartCentroid: (x: Float, y: Float)?
    private var holdMaxMovement: Float = 0

    // MARK: - Observable state
    private(set) var currentPhaseName: String = "Idle"
    private(set) var currentFingerCount: Int = 0
    private(set) var isReciprocalActive: Bool = false
    private(set) var currentCentroidX: Float = 0.5
    private(set) var currentCentroidY: Float = 0.5

    var onStateChange: (() -> Void)?

    private init() {}
    
    static let shared: GestureEngine = {
        let instance = GestureEngine()
        instance.inputManager = GestureInputManager(engine: instance)
        instance.processor = GestureProcessor(engine: instance)
        return instance
    }()

    // MARK: - Lifecycle

    func start() {
        guard AXIsProcessTrusted() else { AppLogger.debug("[Engine] Not trusted"); return }
        guard !isRunning else { return }

        TouchTracker.resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastFiredSwipe = nil
        pendingClickTimeout?.cancel(); pendingClickTimeout = nil; pendingClick = nil
        cancelHoldTimer()
        touchSessionStart = nil; touchSessionMovement = 0
        lastThreeFingerTapEnd = 0; isSystemZoomSession = false

        TouchTracker.updateTuningCache(edgeMarginEnabled: Settings.shared.tuning.edgeMarginEnabled,
                                        edgeMargin: Settings.shared.tuning.edgeMargin)
        EdgeControlsController.shared.applySettings()
        LowFingerTrackpadInput.shared.start()
        MultitouchBridge.shared.updateMinimumContactCount()
        inputManager.setupTaps()
        MultitouchBridge.shared.start(callback: glideMTCallback)
        inputManager.installMonitors()
        AppActivationOrder.shared.startMRUTracking()

        isRunning = true
        MagicMouseInput.shared.start()
        NativePointerSpeed.shared.apply()
        updateObservableState()
        AppLogger.debug("[Engine] Started")
    }

    /// Backstop for the input paths macOS can take away without telling anyone: the
    /// event taps, and the multitouch device, which a sleep/wake cycle can leave
    /// stopped or holding a handle the hardware no longer answers.
    func checkHealth() {
        guard isRunning else { return }
        inputManager.checkHealth()
        MagicMouseInput.shared.checkHealth()
        NativePointerSpeed.shared.apply()
        guard !MultitouchBridge.shared.isDeviceRunning else { return }
        AppLogger.debug("[Engine] Multitouch device not running — rebuilding")
        MultitouchBridge.shared.restart(callback: glideMTCallback)
    }

    func stop() {
        guard isRunning else { return }

        finishIfNeeded()
        LowFingerTrackpadInput.shared.stop()
        MagicMouseInput.shared.stop()
        NativePointerSpeed.shared.apply(restoring: true)
        EdgeControlsController.shared.reset()
        MultitouchBridge.shared.stop()
        inputManager.teardownTaps()
        inputManager.removeMonitors()

        TouchTracker.resetGlobalMTState()
        reciprocalToken = nil
        pendingClickTimeout?.cancel(); pendingClickTimeout = nil; pendingClick = nil
        cancelHoldTimer()
        isRunning = false
        AppActivationOrder.shared.stopMRUTracking()
        updateObservableState()
        AppLogger.debug("[Engine] Stopped")
    }

    // MARK: - Touch update

    func onTouches(_ frame: TouchFrameData) {
        let now = ProcessInfo.processInfo.systemUptime

        if frame.count >= 3 {
            if touchSessionStart == nil {
                touchSessionStart = (time: now, cx: frame.cx, cy: frame.cy)
                touchSessionMovement = 0
                // Re-touch right after a 3-finger tap → system zoom drag.
                isSystemZoomSession = now - lastThreeFingerTapEnd < doubleTapWindow
                if isSystemZoomSession { phase = .ignored }
            } else if let start = touchSessionStart {
                let dx = frame.cx - start.cx, dy = frame.cy - start.cy
                touchSessionMovement = max(touchSessionMovement, (dx * dx + dy * dy).squareRoot())
            }
        } else if let start = touchSessionStart {
            // Session ended — was it a tap (short + motionless)?
            let wasTap = now - start.time < tapMaxDuration && touchSessionMovement < tapMaxMovement
            lastThreeFingerTapEnd = wasTap ? now : 0
            touchSessionStart = nil
            isSystemZoomSession = false
        }

        // Leave events untouched while a contact could still be a zoom double-tap
        // (short + motionless) and during the zoom drag itself — suppressing the
        // taps starves the system recognizer and native zoom never triggers.
        let couldBeTap: Bool = {
            guard let start = touchSessionStart else { return false }
            return now - start.time < tapMaxDuration && touchSessionMovement < tapMaxMovement
        }()
        // Tap stays active whenever 3+ fingers are down EXCEPT during the native
        // zoom drag, where every event must reach the system. In the initial
        // tap-detection window we keep the tap on but pass gesture-class events
        // (tapWindowActive) so the zoom double-tap is still recognized — while
        // scroll stays suppressed, so a swipe can't scrub video at gesture onset.
        inputManager.tapWindowActive = couldBeTap
        inputManager.setSuppressionActive(frame.count >= 3 && !isSystemZoomSession)
        currentFingerCount = Int(frame.count)

        // Tap & Hold: (re)arm whenever the resting finger count changes, cancel on lift.
        if frame.count >= 3 {
            if Int(frame.count) != holdArmedFingerCount {
                if TouchTracker.areClickTouchesSimultaneous() {
                    armHoldTimer(fingerCount: Int(frame.count), cx: frame.cx, cy: frame.cy)
                } else {
                    cancelHoldTimer()
                }
            } else if holdArmedFingerCount > 0, let start = holdStartCentroid {
                let dx = frame.cx - start.x
                let dy = frame.cy - start.y
                holdMaxMovement = max(holdMaxMovement, (dx * dx + dy * dy).squareRoot())
                if holdMaxMovement >= tapMaxMovement {
                    cancelHoldTimer()
                }
            }
        } else {
            cancelHoldTimer()
        }

        if frame.count < 3 {
            TouchTracker.glideClickFingerCount = 0
            finishIfNeeded()
            updateObservableState()
            return
        }

        currentCentroidX = frame.cx
        currentCentroidY = frame.cy

        if TouchTracker.glideClickFingerCount >= 3 { return }

        var tuning = Settings.shared.tuning
        tuning.initialThreshold *= Float(Settings.shared.deviceTuning.thresholdScale(for: .trackpad))
        if let nextPhase = processor.handleTouches(frame, phase: phase, tuning: tuning) {
            phase = nextPhase
            updateObservableState()
        }
    }

    // MARK: - Tap & Hold

    private func armHoldTimer(fingerCount n: Int, cx: Float, cy: Float) {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdArmedFingerCount = n
        holdStartCentroid = (x: cx, y: cy)
        holdMaxMovement = 0
        guard GestureRuleResolver.hasHoldRule(fingers: n) else { return }
        let work = DispatchWorkItem { [weak self] in self?.fireHoldIfStillValid(fingerCount: n) }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Settings.shared.tuning.tapHoldDuration, execute: work)
    }

    private func cancelHoldTimer() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdArmedFingerCount = 0
        holdStartCentroid = nil
    }

    private func fireHoldIfStillValid(fingerCount n: Int) {
        holdWorkItem = nil
        guard isRunning,
              TouchTracker.glideActiveTouches == Int32(n),
              TouchTracker.glideClickFingerCount == 0,
              NSEvent.pressedMouseButtons & 1 == 0,   // physical press → click/force-click path
              !isSystemZoomSession,
              holdMaxMovement < tapMaxMovement else { return }
        switch phase {
        case .fired, .continuousSwipe, .lockedSwipe: return
        default: break
        }
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .tapHold,
                                                      modifiers: captureModifiers()) else { return }
        Haptic.forRule(rule)   // the instant the hold is recognized
        fireClickRule(rule, label: "Hold", fingerCount: n)
    }

    // MARK: - Actions

    func processClick(fingerCount n: Int) {
        guard TouchTracker.areClickTouchesSimultaneous() else { return }

        let modifiers = captureModifiers()
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .click, modifiers: modifiers) else { return }

        // A Force Touch trackpad emits this normal click (stage 1) *before* the deep
        // press (stage 2). If a force-click rule is also configured for this finger
        // count, we can't yet tell whether this is a normal or force click. Defer it
        // and resolve on whichever happens first:
        //   • mouse-up  → it was a normal click  (flushPendingClick)
        //   • deep press → it was a force click  (processForceClick cancels this)
        // With no force rule, fire instantly (no added latency).
        let hasForceRule = GestureRuleResolver.bestRule(fingers: n, direction: .forceClick, modifiers: modifiers) != nil
        // Haptic at the moment the click is recognized (mouse-down), even when the
        // action itself is deferred until force-click resolution — feedback should
        // track the gesture, not the outcome.
        Haptic.forRule(rule)
        if hasForceRule {
            pendingClickTimeout?.cancel()
            pendingClick = (rule: rule, fingers: n)
            armPendingClickSafetyTimeout()
        } else {
            fireClickRule(rule, label: "Click", fingerCount: n)
        }
    }

    /// Safety net for a missed mouse-up. While the left button is still physically
    /// held, resolving now would fire a click mid-hold (the user may still be heading
    /// for a force click) — so keep re-arming until the button is actually released.
    private func armPendingClickSafetyTimeout() {
        pendingClickTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingClick != nil else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.armPendingClickSafetyTimeout()
            } else {
                self.flushPendingClick()
            }
        }
        pendingClickTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + pendingClickSafetyTimeout, execute: timeout)
    }

    /// Called when a left mouse-up is observed. If a click is pending (no deep press
    /// arrived before release), it was a normal click — fire it now.
    func flushPendingClick() {
        pendingClickTimeout?.cancel()
        pendingClickTimeout = nil
        guard let pc = pendingClick else { return }
        pendingClick = nil
        fireClickRule(pc.rule, label: "Click", fingerCount: pc.fingers)
    }

    func processForceClick(fingerCount n: Int) {
        guard TouchTracker.areClickTouchesSimultaneous() else { return }

        // Resolve against the corner the fingers rest in (centroid is fresh — the
        // fingers are still down at the deep press). No match (e.g. a center press
        // when only corner rules exist) → leave any pending normal click alone so
        // the mouse-up flushes it as an ordinary click.
        let modifiers = captureModifiers()
        guard let rule = GestureRuleResolver.forceClickRule(
                fingers: n, cx: currentCentroidX, cy: currentCentroidY,
                margin: Settings.shared.tuning.forceClickMargin, modifiers: modifiers) else { return }

        // Matched — the deep press supersedes any pending normal click.
        pendingClickTimeout?.cancel()
        pendingClickTimeout = nil
        pendingClick = nil

        Haptic.forRule(rule)   // at the deep press itself
        fireClickRule(rule, label: "Force Click", fingerCount: n)
    }

    private func fireClickRule(_ rule: GestureRule, label: String, fingerCount n: Int) {
        LowFingerTrackpadInput.shared.cancelCurrentGesture()
        AppLogger.debug("[Engine] \(label) — \(n) fingers → \(rule.action.rawValue)")
        clearReciprocalToken()
        phase = .fired

        if logIfBlocked(rule.direction.title(fingers: rule.fingers), action: rule.action, device: rule.device) {
            updateObservableState(); return
        }
        let monitoring = recordMonitoredGesture(rule)
        if rule.action == .quitApp {
            WindowTargeting.shared.quitAppAtCursor(NSEvent.mouseLocation)
        } else {
            ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                          menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                          customShortcut: rule.customShortcut,
                                          advancedKeyboard: rule.advancedKeyboard,
                                          shortcutName: rule.shortcutName, script: rule.script, desktopOptions: rule.desktopOptions, monitoring: monitoring)
        }
        updateObservableState()
    }

    func handleExternalInteraction() {
        guard TouchTracker.glideActiveTouches < 3 else { return }
        if case .fired = phase { return }
        // Don't clear the reciprocal token while idle — mouse movement between
        // two gestures is normal and would otherwise kill a pending reciprocal.
        // The token already has a TTL (1.5s) so it expires on its own.
        if case .idle = phase { return }
        clearReciprocalToken()
    }

    private func finishIfNeeded() {
        if case .continuousSwipe(let data) = phase { executeContinuousEndAction(for: data) }
        phase = .idle
    }

    private func recordMonitoredGesture(_ rule: GestureRule) -> LiveActionContext? {
        LiveContactsMonitor.forDevice(rule.device).recordGesture(rule.direction.title(fingers: rule.fingers),
            action: rule.action.rawValue, appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app")
    }

    /// With Block Real Gesture Triggering on, log the gesture as blocked and
    /// report true so the caller skips its action.
    private func logIfBlocked(_ gesture: String, action: GestureAction, device: GestureDevice) -> Bool {
        guard GestureActionBlock.shared.blocksActions else { return false }
        _ = LiveContactsMonitor.forDevice(device).recordGesture(gesture, action: "Blocked · \(action.rawValue)",
            appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app")
        return true
    }

    func executeGestureRuleAction(_ rule: GestureRule) {
        if logIfBlocked(rule.direction.title(fingers: rule.fingers), action: rule.action, device: rule.device) { return }
        let monitoring = recordMonitoredGesture(rule)
        if rule.device == .trackpad { Haptic.forRule(rule) }
        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                      menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                      customShortcut: rule.customShortcut,
                                      advancedKeyboard: rule.advancedKeyboard,
                                      shortcutName: rule.shortcutName, script: rule.script, desktopOptions: rule.desktopOptions, monitoring: monitoring)
    }

    func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureDirection) {
        LowFingerTrackpadInput.shared.cancelCurrentGesture()
        if logIfBlocked(rule.direction.title(fingers: rule.fingers), action: rule.action, device: rule.device) { return }
        executeGestureRuleAction(rule)

        // Track what just fired so we can detect back-to-back same-direction toggles.
        let previousFired = lastFiredSwipe
        lastFiredSwipe = (fingers: fingers, direction: direction)

        if rule.reciprocalEnabled {
            // If the user just fired the same direction twice in a row (e.g. swipe-up
            // to open Mission Control, then swipe-up again to close it), that second
            // gesture consumed the toggle — don't leave a token pointing the other way
            // or the very next gesture in that direction gets hijacked.
            let isToggle = previousFired?.fingers == fingers && previousFired?.direction == direction
            if isToggle {
                clearReciprocalToken()
                // Toggle pair consumed (open → close). The next same-direction swipe
                // re-opens, so it must arm a fresh token — reset tracking to alternate.
                lastFiredSwipe = nil
            } else {
                reciprocalToken = makeReciprocalToken(rule: rule, direction: direction)
            }
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    func consumeReciprocalToken(fingers: Int, direction: GestureDirection, now: TimeInterval) -> Bool {
        guard let token = reciprocalToken,
              now <= token.expiresAt,
              token.fingers == fingers,
              token.direction == direction else {
            // Don't clear the token on a miss — it may still be valid for the next gesture.
            // It will expire on its own via the TTL, or get replaced when a new rule fires.
            return false
        }
        clearReciprocalToken()
        lastFiredSwipe = nil   // reciprocal consumed — reset toggle tracking
        LowFingerTrackpadInput.shared.cancelCurrentGesture()
        if logIfBlocked(direction.title(fingers: fingers), action: token.inverseAction, device: .trackpad) { return true }
        Haptic.reciprocal()
        let monitoring = LiveContactsMonitor.shared.recordGesture(direction.title(fingers: fingers), action: token.inverseAction.rawValue,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app")
        ActionExecutor.shared.execute(token.inverseAction, desktopOptions: token.desktopOptions, monitoring: monitoring)
        return true
    }

    private func makeReciprocalToken(rule: GestureRule, direction: GestureDirection) -> ReciprocalToken? {
        let rev: GestureDirection
        switch direction {
        case .swipeLeft: rev = .swipeRight; case .swipeRight: rev = .swipeLeft
        case .swipeUp:   rev = .swipeDown;  case .swipeDown:  rev = .swipeUp
        default: return nil
        }
        let inverse = rule.reciprocalAction ?? rule.action.inverseAction ?? .doNothing
        return ReciprocalToken(inverseAction: inverse, desktopOptions: rule.desktopOptions,
                               fingers: rule.fingers, direction: rev, sourceRuleID: rule.id,
                               expiresAt: ProcessInfo.processInfo.systemUptime + 1.5)
    }

    func clearReciprocalToken() { reciprocalToken = nil; isReciprocalActive = false }

    func executeContinuousAction(_ action: GestureAction, shortcut: KeyboardShortcut? = nil, keyboard: [KeyboardInputStep] = [], gesture: String = "Continuous gesture") {
        if logIfBlocked(gesture, action: action, device: .trackpad) { return }
        let monitoring = LiveContactsMonitor.shared.recordGesture(gesture, action: action.rawValue, appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app")
        LowFingerTrackpadInput.shared.cancelCurrentGesture()
        Haptic.forAction(action)
        ActionExecutor.shared.execute(action, customShortcut: shortcut, advancedKeyboard: keyboard, monitoring: monitoring)
    }

    func executeContinuousEndAction(for data: SwipeTrackData) {
        guard let rule = data.continuousRule else { return }
        executeContinuousAction(rule.continuousEndAction, shortcut: rule.continuousEndShortcut, keyboard: rule.continuousEndKeyboard, gesture: "\(rule.direction.title(fingers: rule.fingers)) · End")
    }

    func continuousUpdateAction(for dir: GestureDirection, in rule: GestureRule) -> GestureAction {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeAction : rule.continuousPositiveAction
    }
    func continuousUpdateKeyboard(for dir: GestureDirection, in rule: GestureRule) -> [KeyboardInputStep] {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeKeyboard : rule.continuousPositiveKeyboard
    }
    func continuousUpdateShortcut(for dir: GestureDirection, in rule: GestureRule) -> KeyboardShortcut? {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeShortcut : rule.continuousPositiveShortcut
    }

    // MARK: - Helpers

    func captureModifiers() -> CapturedModifiers { CapturedModifiers(NSEvent.modifierFlags) }

    private func updateObservableState() {
        let newPhaseName: String
        switch phase {
        case .idle: newPhaseName = "Idle"; case .candidate: newPhaseName = "Candidate"
        case .lockedSwipe: newPhaseName = "Locked (Swipe)"; case .ignored: newPhaseName = "Ignored"
        case .fired: newPhaseName = "Fired"; case .continuousSwipe: newPhaseName = "Continuous"
        }
        let newReciprocal = (reciprocalToken != nil)
        let stateChanged = (newPhaseName != currentPhaseName) || (newReciprocal != isReciprocalActive)
        currentPhaseName = newPhaseName
        isReciprocalActive = newReciprocal
        if stateChanged {
            onStateChange?()
        }
    }
}
