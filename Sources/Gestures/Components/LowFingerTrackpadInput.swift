import Cocoa
import Combine

/// Opt-in one/two-finger and three-finger tap/Tip recognition on the existing trackpad stream. Recognition
/// stays on the callback thread; only completed gestures are sent to main.
final class LowFingerTrackpadInput: ObservableObject {
    @Published private(set) var inputStatus = "Waiting for trackpad contacts"
    @Published private(set) var contextStatus = "No active application"
    @Published private(set) var tipTapStatus = "No TipTap attempted yet"
    @Published private(set) var lastGesture = "None yet"
    @Published private(set) var actionStatus = "No action dispatched yet"
    private var contextName = "Unknown app"
    private var lastFeedback: String?
    private var lastContactCount: Int32 = -1
    private var lastInputReport = 0.0

    static let shared = LowFingerTrackpadInput()
    private let lock = NSLock()
    private var recognizer = MagicMouseRecognizer()
    private var settings = MagicMouseSettings()
    private var running = false
    private var generation = 0
    private var activationObserver: NSObjectProtocol?
    private var modifiers = CapturedModifiers([])
    /// Seconds to add to `systemUptime` to reach the multitouch frame clock, taken
    /// from the most recent frame. The two clocks have different origins (the frame
    /// clock keeps running through sleep) and different rates — measured at 0.989×
    /// on a MacBook Air — so a fixed offset drifts about 10 ms every second. Native
    /// events arrive within a few frames of the touch they belong to, so the latest
    /// frame's offset is accurate to its delivery lag, a few milliseconds.
    private var frameClockOffset: Double?
    /// Trackpad buttons whose tap-to-click down was swallowed, with when it was.
    /// The matching up is swallowed too, so apps never see half a click.
    private var swallowedButtons: [Int: Double] = [:]
    private init() {}

    static func direction(for gesture: MagicMouseGesture) -> GestureDirection? {
        gesture.usesSupplementalTrackpadRecognizer ? MouseRuleBridge.direction(gesture, device: .trackpad) : nil
    }

    static func recognitionSettings(rules: [GestureRule]) -> MagicMouseSettings {
        MouseRuleBridge.recognitionSettings(rules: rules, device: .trackpad)
    }

    func applySettings() {
        let app = NSWorkspace.shared.frontmostApplication
        let snapshot = Settings.shared.deviceTuning.applying(to: Self.recognitionSettings(rules: Settings.shared.rules.filter { $0.matchesApp(app?.bundleIdentifier) }), device: .trackpad)
        let name = app?.localizedName ?? app?.bundleIdentifier ?? "Unknown app"
        let tips = MagicMouseGesture.allCases.filter { $0.rawValue.hasPrefix("tip_") && snapshot.action(for: $0) != .none }
        contextStatus = tips.isEmpty ? "No TipTap binding for \(name)" : "\(name): \(tips.map(\.title).joined(separator: ", "))"
        lock.lock()
        settings = snapshot
        contextName = name
        generation += 1
        recognizer.changeAppContext() // Preserve only resting TipTap anchors, never a pending stroke.
        lock.unlock()
    }

    func start() {
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.applySettings()
            }
        applySettings()
        lock.lock(); running = true; recognizer.reset(); lock.unlock()
    }
    func stop() {
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        activationObserver = nil
        lock.lock(); running = false; generation += 1; recognizer.reset(); swallowedButtons = [:]; lock.unlock()
        LiveContactsMonitor.shared.inputStopped()
    }

    func observeNativeEvent(_ type: CGEventType, confirmedTrackpad: Bool) {
        lock.lock()
        guard running, settings.enabled, let now = frameTime(ofUptime: ProcessInfo.processInfo.systemUptime) else { lock.unlock(); return }
        let token = generation, captured = modifiers
        let gesture = Self.handleNativeEvent(type, confirmedTrackpad: confirmedTrackpad,
            timestamp: now, recognizer: &recognizer)
        lock.unlock()
        if let gesture { dispatch(gesture, token: token, modifiers: captured) }
    }

    /// Raw contacts already validate the tapping finger and every anchor. Native
    /// scroll events can overlap a valid fixed-finger chord (including momentum
    /// from the preceding scroll); they must not veto that independently checked
    /// gesture. Ordinary whole-hand taps still cancel on trackpad scrolling.
    static func handleNativeEvent(_ type: CGEventType, confirmedTrackpad: Bool,
                                  timestamp: Double, recognizer: inout MagicMouseRecognizer) -> MagicMouseGesture? {
        guard confirmedTrackpad else { return nil }
        if type == .scrollWheel {
            if !recognizer.ownsFixedFingerSession { recognizer.cancelTap() }
            return nil
        }
        let button: Int
        let down: Bool
        switch type {
        case .leftMouseDown: button = 0; down = true
        case .leftMouseUp: button = 0; down = false
        case .rightMouseDown: button = 1; down = true
        case .rightMouseUp: button = 1; down = false
        case .otherMouseDown: button = 2; down = true
        case .otherMouseUp: button = 2; down = false
        default: return nil
        }
        return recognizer.trackpadButtonChanged(button, isDown: down, timestamp: timestamp)
    }

    /// Decides, synchronously from the click event tap, whether a native button
    /// event must be swallowed: it is the tap-to-click macOS generates for a
    /// TipTap's tapping finger. Left through, it lands as a stray click on whatever
    /// is under the pointer, and the recognizer would read it as a physical press
    /// and cancel the next tap. `isTrackpad` is only consulted for candidates,
    /// since it costs a registry lookup.
    func claimsNativeClick(_ type: CGEventType, uptime: Double, isTrackpad: () -> Bool) -> Bool {
        let button: Int, down: Bool
        switch type {
        case .leftMouseDown: button = 0; down = true
        case .leftMouseUp: button = 0; down = false
        case .rightMouseDown: button = 1; down = true
        case .rightMouseUp: button = 1; down = false
        default: return false
        }
        lock.lock()
        // Never hold one back for long: a lost up must not leave a button "down".
        swallowedButtons = swallowedButtons.filter { uptime - $0.value < 1.0 }
        if !down {
            let claimed = swallowedButtons.removeValue(forKey: button) != nil
            lock.unlock()
            return claimed
        }
        guard running, settings.enabled, let now = frameTime(ofUptime: uptime),
              recognizer.isTapToClickEcho(at: now) else { lock.unlock(); return false }
        lock.unlock()
        guard isTrackpad() else { return false }
        lock.lock(); swallowedButtons[button] = uptime; lock.unlock()
        return true
    }

    private func frameTime(ofUptime uptime: Double) -> Double? { frameClockOffset.map { uptime + $0 } }

    /// How a button-down at `uptime` would be classified, for diagnostics.
    func echoDiagnostics(uptime: Double) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let now = frameTime(ofUptime: uptime) else { return "no frame clock yet" }
        return "running=\(running) enabled=\(settings.enabled) " + recognizer.echoDiagnostics(at: now)
    }

    func cancelCurrentGesture() {
        lock.lock(); generation += 1; recognizer.cancel(); lock.unlock()
    }

    @discardableResult
    func receive(_ points: UnsafePointer<GLDTouchPoint>?, count: Int32, timestamp: Double) -> Bool {
        lock.lock()
        guard running, count >= 0, count <= 32 else { lock.unlock(); return false }
        frameClockOffset = timestamp - ProcessInfo.processInfo.systemUptime
        if count != lastContactCount || timestamp - lastInputReport >= 0.5 {
            lastContactCount = count; lastInputReport = timestamp
            let token = generation
            publish(token: token) { $0.inputStatus = "Touch frames received · \(count) contacts" }
        }
        guard settings.enabled else {
            LiveContactsMonitor.shared.receive(points, count: count, timestamp: timestamp,
                appName: contextName, roles: [:], feedback: "No active low-finger binding in this app")
            lock.unlock(); return false
        }
        var contacts: [MouseContact] = []
        if let points {
            for index in 0..<Int(count) {
                let p = points[index]
                if p.state == 3 || p.state == 4 {
                    contacts.append(MouseContact(id: p.identifier, x: Double(p.x), y: Double(p.y), size: Double(p.size)))
                }
            }
        }
        if (!recognizer.isTouching || recognizer.isRestingForTipTap) && !contacts.isEmpty {
            modifiers = CapturedModifiers(NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue)))
        }
        if contacts.count > 4 { recognizer.cancel() }
        // A swallowed tap-to-click is not a held button, whatever the session state says.
        let pressed = swallowedButtons.isEmpty && (CGEventSource.buttonState(.combinedSessionState, button: .left) ||
            CGEventSource.buttonState(.combinedSessionState, button: .right))
        let previousDeadline = recognizer.pendingTapDeadline
        let gesture = recognizer.consume(contacts, timestamp: timestamp, settings: settings, physicalButtonDown: pressed, allowsTrackpadButtonRecovery: true)
        let feedback = pressed ? "Mouse button is down; lift it before attempting a TipTap." : recognizer.tipTapFeedback
        if let feedback, feedback != lastFeedback {
            lastFeedback = feedback
            let message = "\(contextName): \(feedback)"
            publish(token: generation) { $0.tipTapStatus = message }
        }
        LiveContactsMonitor.shared.receive(points, count: count, timestamp: timestamp,
            appName: contextName, roles: recognizer.liveContactRoles, feedback: feedback ?? "Waiting for a TipTap",
            sampledButtonDown: pressed, trackpadButtonsDown: recognizer.liveTrackpadButtons)
        let ownsSession = recognizer.ownsFixedFingerSession
        let token = generation, capturedModifiers = modifiers
        let configured = gesture.map { settings.action(for: $0) != .none } ?? false
        let deadline = recognizer.pendingTapDeadline, location = recognizer.lastTapLocation
        lock.unlock()
        if let deadline, deadline != previousDeadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - timestamp)) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let result = self.generation == token ? self.recognizer.flushPendingTap(at: deadline) : nil
                let location = self.recognizer.lastTapLocation
                self.lock.unlock()
                if let result { self.dispatch(result, token: token, modifiers: capturedModifiers, location: location) }
            }
        }
        if configured, let gesture { dispatch(gesture, token: token, modifiers: capturedModifiers, location: location) }
        return ownsSession
    }
    private func publish(token: Int, update: @escaping (LowFingerTrackpadInput) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let valid = self.running && self.generation == token; self.lock.unlock()
            if valid { update(self) }
        }
    }

    private func dispatch(_ gesture: MagicMouseGesture, token: Int, modifiers: CapturedModifiers, location: MouseContact? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = self.running && self.generation == token
            self.lock.unlock()
            guard valid else { return }
            self.lastGesture = gesture.title
            guard GestureEngine.shared.isRunning else { self.actionStatus = "Gestures are paused"; return }
            guard EdgeControlsController.shared.activeEdge == nil else {
                self.actionStatus = "An edge control is active"; return
            }
            guard let rule = MouseRuleBridge.resolve(gesture, device: .trackpad, modifiers: modifiers, location: location) else {
                self.actionStatus = "Recognized, but no rule matches this app, modifiers and window state"; return
            }
            self.actionStatus = "Dispatched \(rule.action.rawValue) in \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app")"
            GestureEngine.shared.executeGestureRuleAction(rule)
        }
    }
}
