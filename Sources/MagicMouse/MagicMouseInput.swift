import AppKit
import ApplicationServices
import IOKit
import Darwin

private typealias MouseMTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// Runtime-resolved system APIs; unavailable symbols disable only mouse support.
/// The framework stays mapped because callback unregistering does not promise to
/// wait for already-running callbacks. Device arrays own their borrowed handles.
private final class MouseMultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias Register = @convention(c) (UnsafeMutableRawPointer, MouseMTCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias IsRunning = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Family = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let family: Family
    let isRunning: IsRunning?
    private static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL)
    init?() {
        guard let h = Self.handle,
              let a = dlsym(h, "MTDeviceCreateList"), let b = dlsym(h, "MTRegisterContactFrameCallback"),
              let c = dlsym(h, "MTUnregisterContactFrameCallback"), let d = dlsym(h, "MTDeviceStart"),
              let e = dlsym(h, "MTDeviceStop"), let f = dlsym(h, "MTDeviceGetFamilyID") else { return nil }
        createList = unsafeBitCast(a, to: CreateList.self)
        register = unsafeBitCast(b, to: Register.self)
        unregister = unsafeBitCast(c, to: Register.self)
        start = unsafeBitCast(d, to: Start.self)
        stop = unsafeBitCast(e, to: Stop.self)
        family = unsafeBitCast(f, to: Family.self)
        isRunning = dlsym(h, "MTDeviceIsRunning").map { unsafeBitCast($0, to: IsRunning.self) }
    }
}

/// Lifecycle and published state belong to main. Only recognizers, settings,
/// cancellation tokens, and click timestamps cross threads, under `lock`.
final class MagicMouseInput: ObservableObject {
    static let shared = MagicMouseInput()
    @Published private(set) var status = "Magic Mouse is paused"
    @Published private(set) var connectedCount = 0
    @Published private(set) var inputStatus = "Waiting for touch input"
    @Published private(set) var lastGesture = "None yet"
    @Published private(set) var tipTapStatus = "No TipTap attempted yet"
    private var receivedFrame = false
    private var activationObserver: NSObjectProtocol?
    private let api = MouseMultitouchAPI()
    private let lock = NSLock()
    private var settings = MagicMouseSettings()
    private var contextName = "Unknown app"
    private var generation = 0
    private var lastPhysicalClick = 0.0
    private var reservedClickSender: UInt64?
    private struct Session {
        var recognizer = MagicMouseRecognizer()
        var pointerOrigin: CGPoint?
        var contactCount = 0
        var modifiers = CapturedModifiers([])
        /// Axes of a swipe that fired, held through the lift. Fingers rarely
        /// leave together, and the one left behind starts a new native scroll;
        /// scroll events also trail touch frames by about 10 ms, so a scroll can
        /// begin just after the last finger lifts. Either would reach the app
        /// with its momentum.
        var firedSwipeAxes: MouseScrollAxes = []
        /// Uptime of the full lift after a fired swipe; the axes stay held
        /// for `firedSwipeGrace` after it, or until the next touch.
        var firedSwipeLift: Double?
        static let firedSwipeGrace = 0.25
        /// Scrolling is withheld while two or more fingers are down, as
        /// BetterTouchTool's "disable scrolling with 2+ fingers" does. A Tip
        /// swipe's resting fingers start a new native scroll about 60 ms after
        /// the swiping finger lifts, carrying that finger's momentum: measured
        /// at 1,400–3,800 points reaching the app after every Tip swipe.
        var multiFinger = false
        var multiFingerEnded: Double?
        func heldSwipeAxes(at uptime: Double) -> MouseScrollAxes {
            var axes: MouseScrollAxes = []
            if let lift = firedSwipeLift { if uptime - lift < Self.firedSwipeGrace { axes = firedSwipeAxes } }
            else { axes = firedSwipeAxes }
            if multiFinger, multiFingerEnded.map({ uptime - $0 < Self.firedSwipeGrace }) ?? true {
                axes.formUnion([.vertical, .horizontal])
            }
            return axes
        }
    }
    private var sessions: [UnsafeMutableRawPointer: Session] = [:]
    private var devices: [UnsafeMutableRawPointer] = []
    private var callbackDevices: [Int: UnsafeMutableRawPointer] = [:]
    private var deviceList: CFArray?
    private var running = false
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var reconnectWork: DispatchWorkItem?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private let eventIdentity = MouseEventIdentity()
    /// Keeps a swipe's scroll axes reserved through its lift and momentum.
    private var scrollReservation = ScrollSequenceReservation()
    private static let syntheticTag: Int64 = 0x42474D4F555345
    private init() {}

    func applySettings() {
        let enabled = MouseRuleBridge.recognitionSettings(rules: Settings.shared.rules, device: .magicMouse,
            base: MagicMouseSettings.normalized(Settings.shared.magicMouse)).enabled ||
            (Settings.shared.magicMouse.enabled && (Settings.shared.magicMouse.hasScrollInversion || LiveContactsMonitor.mouse.isEnabled))
        if GestureEngine.shared.isRunning && enabled {
            if running { refreshAppContext() } else { start() }
        } else { stop() }
    }

    /// Capture app context on main, never from the multitouch callback. Switching
    /// apps invalidates pending gestures so they cannot act on the new app.
    private func refreshAppContext() {
        let value = MouseRuleBridge.recognitionSettings(rules: Settings.shared.rules, device: .magicMouse,
            base: Settings.shared.deviceTuning.applying(to: MagicMouseSettings.normalized(Settings.shared.magicMouse), device: .magicMouse),
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        lock.lock()
        settings = value
        contextName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app"
        generation += 1
        receivedFrame = false
        for key in sessions.keys {
            sessions[key]?.recognizer.changeAppContext()
        }
        lock.unlock()
    }

    func start() {
        guard Settings.shared.magicMouse.enabled, AXIsProcessTrusted() else { return }
        guard !running else { return }
        guard api != nil else { status = "Magic Mouse input is unavailable on this macOS version"; return }
        refreshAppContext()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAppContext()
            }
        running = true
        observeConnections()
        rebuildDevices()
    }

    func stop() {
        running = false
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        activationObserver = nil
        reconnectWork?.cancel(); reconnectWork = nil
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notificationPort { IONotificationPortDestroy(port) }
        notificationPort = nil
        releaseDevices()
        status = Settings.shared.magicMouse.enabled ? "Magic Mouse is paused" : "Magic Mouse support is off"
    }

    func reconnect() {
        guard GestureEngine.shared.isRunning else { return }
        if running { rebuildDevices() } else { start() }
    }

    /// Called by the existing engine health check; adds no polling timer.
    func checkHealth() {
        guard running, !devices.isEmpty else { return }
        if let isRunning = api?.isRunning, devices.contains(where: { !isRunning($0) }) {
            rebuildDevices()
            return
        }
        if let tap = eventTap, CFMachPortIsValid(tap) { return }
        installEventTap()
    }

    private func releaseDevices() {
        lock.lock(); generation += 1; sessions.removeAll(); callbackDevices.removeAll(); receivedFrame = false; lock.unlock()
        for (slot, device) in devices.enumerated() { api?.unregister(device, mouseFrameCallbacks[slot]); api?.stop(device) }
        devices.removeAll()
        deviceList = nil
        connectedCount = 0
        LiveContactsMonitor.mouse.inputStopped()
        inputStatus = "Waiting for touch input"
        lastGesture = "None yet"
        tipTapStatus = "No TipTap attempted yet"
        removeEventTap()
        eventIdentity.reset()
    }

    private func rebuildDevices() {
        guard running, let api else { return }
        releaseDevices()
        guard let list = api.createList()?.takeRetainedValue() else {
            status = "No Magic Mouse connected"; return
        }
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            var family: Int32 = 0
            // Known Magic Mouse families. Never assume every external device is a
            // mouse: Magic Trackpads and Touch Bars are present in the same list.
            guard api.family(device, &family) == 0, family == 112 || family == 113 else { continue }
            guard devices.count < mouseFrameCallbacks.count else { continue }
            let slot = devices.count
            devices.append(device)
            lock.lock(); sessions[device] = Session(); callbackDevices[slot] = device; lock.unlock()
            api.register(device, mouseFrameCallbacks[slot])
            api.start(device, 0)
        }
        connectedCount = devices.count
        status = devices.isEmpty ? "No Magic Mouse connected" : "Magic Mouse connected"
        if !devices.isEmpty {
            if let isRunning = api.isRunning, devices.allSatisfy({ !isRunning($0) }) {
                status = "Magic Mouse detected; touch input did not start"
                inputStatus = "Reconnect the mouse, then click Reconnect"
            }
            installEventTap()
        }
    }

    private func observeConnections() {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for (name, added) in [(kIOFirstMatchNotification, true), (kIOTerminatedNotification, false)] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, name, IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    var changed = false
                    while case let service = IOIteratorNext(iterator), service != 0 {
                        IOObjectRelease(service); changed = true
                    }
                    guard changed, let context else { return }
                    Unmanaged<MagicMouseInput>.fromOpaque(context).takeUnretainedValue().connectionChanged()
                }, context, &iterator)
            if result == KERN_SUCCESS {
                // Drain to arm notifications without treating initial devices as changes.
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                if added { addedIterator = iterator } else { removedIterator = iterator }
            }
        }
    }

    private func connectionChanged() {
        guard running else { return }
        // Bluetooth enumerates in stages. One debounced rebuild plus one bounded
        // retry is sufficient; no timer wakes the app while the mouse is absent.
        lock.lock(); generation += 1; sessions.removeAll(); lock.unlock()
        scheduleReconnect(retry: true)
    }

    private func scheduleReconnect(retry: Bool) {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.rebuildDevices()
            if retry && self.devices.isEmpty { self.scheduleReconnect(retry: false) }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (retry ? 0.5 : 1.5), execute: work)
    }

    fileprivate func receive(slot: Int, raw: UnsafeMutableRawPointer?, count: Int32, timestamp: Double) {
        guard count >= 0, count <= 32, count == 0 || raw != nil else { return }
        let monitoring = LiveContactsMonitor.mouse.isEnabled
        var livePoints: [GLDTouchPoint] = []
        var contacts: [MouseContact] = []
        contacts.reserveCapacity(min(Int(count), 5))
        if let raw {
            let touches = raw.assumingMemoryBound(to: GLDMTTouch.self)
            for index in 0..<Int(count) {
                let touch = touches[index]
                if touch.state == 3 || touch.state == 4 {
                    contacts.append(MouseContact(id: touch.identifier, x: Double(touch.normalized.position.x), y: Double(touch.normalized.position.y), size: Double(touch.size)))
                    if monitoring {
                        var point = GLDTouchPoint()
                        point.identifier = touch.identifier; point.state = touch.state
                        point.x = touch.normalized.position.x; point.y = touch.normalized.position.y; point.size = touch.size
                        livePoints.append(point)
                    }
                }
            }
        }
        lock.lock()
        guard let device = callbackDevices[slot], var session = sessions[device] else { lock.unlock(); return }
        let token = generation
        let firstFrame = !receivedFrame
        receivedFrame = true
        if firstFrame {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.lock.lock(); let valid = self.generation == token; self.lock.unlock()
                if valid { self.inputStatus = "Touch frames received" }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if (!session.recognizer.isTouching || session.recognizer.isRestingForTipTap) && !contacts.isEmpty {
            session.pointerOrigin = CGEvent(source: nil)?.location
            session.modifiers = CapturedModifiers(NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue)))
        }
        if contacts.isEmpty, let start = session.pointerOrigin, let end = CGEvent(source: nil)?.location,
           hypot(end.x - start.x, end.y - start.y) > 6 { session.recognizer.cancelTap() }
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left) ||
            CGEventSource.buttonState(.combinedSessionState, button: .right) ||
            CGEventSource.buttonState(.combinedSessionState, button: .center)
        let previousDeadline = session.recognizer.pendingTapDeadline
        let previousTipTapFeedback = session.recognizer.tipTapFeedback
        let gesture = session.recognizer.consume(contacts, timestamp: timestamp, settings: settings, physicalButtonDown: pressed)
        session.contactCount = contacts.count
        let configured = gesture.map { settings.action(for: $0) != .none } ?? false
        if contacts.isEmpty {
            if !session.firedSwipeAxes.isEmpty && session.firedSwipeLift == nil { session.firedSwipeLift = now }
        } else if session.firedSwipeLift != nil {
            session.firedSwipeAxes = []; session.firedSwipeLift = nil
        }
        if contacts.count >= 2 && settings.holdsMultiFingerScroll {
            session.multiFinger = true; session.multiFingerEnded = nil
        } else if session.multiFinger {
            if session.multiFingerEnded == nil { session.multiFingerEnded = now }
            else if now - session.multiFingerEnded! >= Session.firedSwipeGrace { session.multiFinger = false; session.multiFingerEnded = nil }
        }
        if !contacts.isEmpty, configured, let gesture, gesture.isSwipe, !gesture.rawValue.hasPrefix("tip_") {
            session.firedSwipeAxes.formUnion(settings.reservedScrollAxes(fingers: gesture.fingers))
        }
        sessions[device] = session
        let modifiers = session.modifiers, deadline = session.recognizer.pendingTapDeadline
        let feedback = session.recognizer.tipTapFeedback
        if monitoring {
            livePoints.withUnsafeBufferPointer { buffer in
                LiveContactsMonitor.mouse.receive(buffer.baseAddress, count: Int32(buffer.count), timestamp: timestamp,
                    appName: contextName, roles: session.recognizer.liveContactRoles,
                    feedback: settings.enabled ? (feedback ?? "Waiting for a TipTap") : "No active Magic Mouse binding in this app",
                    sampledButtonDown: pressed, sourceID: slot)
            }
        }
        lock.unlock()
        if let feedback, feedback != previousTipTapFeedback {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.lock.lock(); let valid = self.generation == token; self.lock.unlock()
                if valid, self.tipTapStatus != feedback { self.tipTapStatus = feedback }
            }
        }
        if let deadline, deadline != previousDeadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - timestamp)) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let result = self.generation == token ? self.sessions[device]?.recognizer.flushPendingTap(at: deadline) : nil
                self.lock.unlock()
                if let result { self.dispatch(result, token: token, modifiers: modifiers, recognizedAt: now) }
            }
        }
        if configured, let gesture { dispatch(gesture, token: token, modifiers: modifiers, recognizedAt: now, location: session.recognizer.lastTapLocation) }
    }

    private func dispatch(_ gesture: MagicMouseGesture, token: Int, modifiers: CapturedModifiers, recognizedAt: Double, location: MouseContact? = nil) {
        // A physical click can land just after a whole-hand tap's release frame,
        // so those wait 40 ms for it. A TipTap keeps a finger resting, and its
        // click would arrive before the tip lifts: dispatch it at once.
        let wait = gesture.isSwipe || gesture.isPhysicalClick || gesture.rawValue.hasPrefix("tip_") ? 0 : 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = token == self.generation && (gesture.isPhysicalClick || self.lastPhysicalClick < recognizedAt - 0.08)
            self.lock.unlock()
            guard valid, self.running, AXIsProcessTrusted() else { return }
            self.lastGesture = gesture.title
            guard let rule = MouseRuleBridge.resolve(gesture, device: .magicMouse, modifiers: modifiers, location: location) else {
                self.inputStatus = "Gesture recognized; no matching rule in this app"
                return
            }
            self.lastGesture = rule.direction.title(fingers: rule.fingers)
            self.inputStatus = "Gesture matched: \(rule.action.rawValue)"
            GestureEngine.shared.executeGestureRuleAction(rule)
        }
    }

    private func installEventTap() {
        removeEventTap()
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(UInt64(0)) { $0 | (UInt64(1) << $1.rawValue) }
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<MagicMouseInput>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.eventTap, owner.running { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return owner.filter(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap = eventTap {
            eventSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else { status = "Magic Mouse needs Accessibility permission" }
    }

    private func removeEventTap() {
        reservedClickSender = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; eventSource = nil
    }

    private func filter(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag else { return false }
        // Scrolls from the trackpad/another mouse must not invalidate a TipTap
        // still in progress on the Magic Mouse.
        if type == .scrollWheel && !eventIdentity.isMagicMouse(event) { return false }
        if type == .leftMouseUp || type == .leftMouseDragged {
            let sender = eventIdentity.senderID(for: event)
            let reserved = reservedClickSender != nil && sender == reservedClickSender
            if type == .leftMouseUp && (reserved || sender == nil) { reservedClickSender = nil }
            return reserved
        }
        if type == .leftMouseDown { reservedClickSender = nil }
        lock.lock()
        if type != .scrollWheel {
            lastPhysicalClick = ProcessInfo.processInfo.systemUptime
            let confirmed = type == .leftMouseDown && eventIdentity.isMagicMouse(event)
            var candidate: (MagicMouseGesture, CapturedModifiers)?
            let token = generation
            for key in sessions.keys {
                if confirmed, let gesture = sessions[key]?.recognizer.physicalClick(timestamp: lastPhysicalClick), let modifiers = sessions[key]?.modifiers {
                    if gesture == .oneFingerMiddleClick || gesture == .fourFingerClick {
                        if candidate == nil { candidate = (gesture, modifiers) }
                    } else { dispatch(gesture, token: token, modifiers: modifiers, recognizedAt: lastPhysicalClick) }
                } else { sessions[key]?.recognizer.cancel() }
            }
            lock.unlock()
            guard running, AXIsProcessTrusted(), let (gesture, modifiers) = candidate,
                  let sender = eventIdentity.senderID(for: event),
                  let rule = MouseRuleBridge.resolve(gesture, device: .magicMouse, modifiers: modifiers) else { return false }
            reservedClickSender = sender
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.lock.lock(); let valid = self.generation == token; self.lock.unlock()
                guard valid else { return }
                self.lastGesture = gesture.title
                self.inputStatus = "Gesture matched: \(rule.action.rawValue)"
                GestureEngine.shared.executeGestureRuleAction(rule)
            }
            return true
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        let touchingAxes = sessions.values.reduce(into: MouseScrollAxes()) { axes, session in
            if session.recognizer.acceptsSwipe { axes.formUnion(settings.reservedScrollAxes(fingers: session.contactCount)) }
            axes.formUnion(session.recognizer.tipSwipeAxes)
            axes.formUnion(session.heldSwipeAxes(at: uptime))
        }
        let reservedAxes = scrollReservation.axes(
            touching: touchingAxes,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            timestamp: uptime)
        let moved = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0 ||
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) != 0
        if moved { for key in sessions.keys { sessions[key]?.recognizer.cancelTap() } }
        let inversion = settings
        lock.unlock()
        // Only suppress confirmed Magic Mouse events. Trackpad/other-mouse input
        // and unidentified senders always pass, even while mouse fingers rest.
        let consumed = MagicMouseScrollFilter.filter(event, reserving: reservedAxes)
        if !consumed {
            MagicMouseScrollFilter.invert(event, vertical: inversion.invertVerticalScrolling, horizontal: inversion.invertHorizontalScrolling)
        }
        return consumed
    }

}

// Bind each callback to its registration. The private callback's first argument
// is not a documented stable MTDeviceRef; treating it as the list handle can drop
// every frame. Dedicated trampolines also keep multiple mice isolated.
private let mouseFrameCallbacks: [MouseMTCallback] = [
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 0, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 1, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 2, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 3, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 4, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 5, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 6, raw: raw, count: count, timestamp: timestamp); return 0 },
    { _, raw, count, timestamp, _ in MagicMouseInput.shared.receive(slot: 7, raw: raw, count: count, timestamp: timestamp); return 0 }
]

/// Optional sender attribution keeps mouse swipe suppression off other devices.
/// Cache by HID sender, and clear on device changes. Unknown APIs/devices pass.
final class MouseEventIdentity {
    typealias CopyHID = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    typealias Sender = @convention(c) (CFTypeRef) -> UInt64
    private let copyHID: CopyHID?
    private let sender: Sender?
    private var cache: [UInt64: Bool] = [:]
    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        copyHID = dlsym(handle, "CGEventCopyIOHIDEvent").map { unsafeBitCast($0, to: CopyHID.self) }
        sender = dlsym(handle, "IOHIDEventGetSenderID").map { unsafeBitCast($0, to: Sender.self) }
    }
    func reset() { cache.removeAll() }
    func senderID(for event: CGEvent) -> UInt64? {
        guard let copyHID, let sender, let hid = copyHID(event)?.takeRetainedValue() else { return nil }
        let id = sender(hid)
        return id == 0 ? nil : id
    }
    func isTrackpad(_ event: CGEvent) -> Bool {
        guard let copyHID, let sender, let hid = copyHID(event)?.takeRetainedValue() else { return false }
        let id = sender(hid)
        guard id != 0 else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let product = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "Product" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
        return product?.localizedCaseInsensitiveContains("trackpad") == true
    }
    func isMagicMouse(_ event: CGEvent) -> Bool {
        guard let copyHID, let sender, let hid = copyHID(event)?.takeRetainedValue() else { return false }
        let id = sender(hid)
        guard id != 0 else { return false }
        if let known = cache[id] { return known }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        func property(_ name: String) -> Int? {
            (IORegistryEntrySearchCFProperty(service, kIOServicePlane, name as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? NSNumber)?.intValue
        }
        let vendor = property("VendorID"), product = property("ProductID")
        let mouse = (vendor == 0x05ac || vendor == 0x004c) && [0x030d, 0x0269, 0x0323].contains(product ?? -1)
        if cache.count >= 32 { cache.removeAll() }
        cache[id] = mouse
        return mouse
    }
}
