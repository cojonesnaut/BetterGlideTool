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
    typealias Family = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let family: Family
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
    }
}

/// Lifecycle and published state belong to main. Only recognizers, settings,
/// cancellation tokens, and click timestamps cross threads, under `lock`.
final class MagicMouseInput: ObservableObject {
    static let shared = MagicMouseInput()
    @Published private(set) var status = "Magic Mouse is paused"
    @Published private(set) var connectedCount = 0
    private let api = MouseMultitouchAPI()
    private let lock = NSLock()
    private var settings = MagicMouseSettings()
    private var generation = 0
    private var lastPhysicalClick = 0.0
    private struct Session {
        var recognizer = MagicMouseRecognizer()
        var pointerOrigin: CGPoint?
        var contactCount = 0
    }
    private var sessions: [UnsafeMutableRawPointer: Session] = [:]
    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?
    private var running = false
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var reconnectWork: DispatchWorkItem?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private let eventIdentity = MouseEventIdentity()
    private static let syntheticTag: Int64 = 0x42474D4F555345
    private init() {}

    func applySettings() {
        lock.lock()
        settings = MagicMouseSettings.normalized(Settings.shared.magicMouse)
        generation += 1
        for key in sessions.keys {
            var reset = Session(); reset.recognizer.cancel()
            sessions[key] = reset
        }
        let enabled = settings.enabled
        lock.unlock()
        if GestureEngine.shared.isRunning && enabled { start() } else { stop() }
    }

    func start() {
        guard Settings.shared.magicMouse.enabled, AXIsProcessTrusted() else { return }
        guard !running else { return }
        guard api != nil else { status = "Magic Mouse input is unavailable on this macOS version"; return }
        lock.lock(); settings = Settings.shared.magicMouse; lock.unlock()
        running = true
        observeConnections()
        rebuildDevices()
    }

    func stop() {
        running = false
        reconnectWork?.cancel(); reconnectWork = nil
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notificationPort { IONotificationPortDestroy(port) }
        notificationPort = nil
        releaseDevices()
        status = Settings.shared.magicMouse.enabled ? "Magic Mouse is paused" : "Magic Mouse support is off"
    }

    func reconnect() {
        guard running else { return }
        rebuildDevices()
    }

    /// Called by the existing engine health check; adds no polling timer.
    func checkHealth() {
        guard running, !devices.isEmpty else { return }
        if let tap = eventTap, CFMachPortIsValid(tap) { return }
        installEventTap()
    }

    private func releaseDevices() {
        lock.lock(); generation += 1; sessions.removeAll(); lock.unlock()
        for device in devices { api?.unregister(device, mouseFrameCallback); api?.stop(device) }
        devices.removeAll()
        deviceList = nil
        connectedCount = 0
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
            devices.append(device)
            lock.lock(); sessions[device] = Session(); lock.unlock()
            api.register(device, mouseFrameCallback)
            api.start(device, 0)
        }
        connectedCount = devices.count
        status = devices.isEmpty ? "No Magic Mouse connected" : "Magic Mouse connected"
        if !devices.isEmpty { installEventTap() }
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

    fileprivate func receive(device: UnsafeMutableRawPointer, raw: UnsafeMutableRawPointer?, count: Int32, timestamp: Double) {
        guard count >= 0, count <= 32, count == 0 || raw != nil else { return }
        var contacts: [MouseContact] = []
        contacts.reserveCapacity(min(Int(count), 5))
        if let raw {
            let touches = raw.assumingMemoryBound(to: GLDMTTouch.self)
            for index in 0..<Int(count) {
                let touch = touches[index]
                if touch.state == 3 || touch.state == 4 {
                    contacts.append(MouseContact(id: touch.identifier, x: Double(touch.normalized.position.x), y: Double(touch.normalized.position.y)))
                }
            }
        }
        lock.lock()
        guard var session = sessions[device] else { lock.unlock(); return }
        let token = generation
        let now = ProcessInfo.processInfo.systemUptime
        if !session.recognizer.isTouching && !contacts.isEmpty { session.pointerOrigin = CGEvent(source: nil)?.location }
        if contacts.isEmpty, let start = session.pointerOrigin, let end = CGEvent(source: nil)?.location,
           hypot(end.x - start.x, end.y - start.y) > 6 { session.recognizer.cancelTap() }
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left) ||
            CGEventSource.buttonState(.combinedSessionState, button: .right) ||
            CGEventSource.buttonState(.combinedSessionState, button: .center)
        let gesture = session.recognizer.consume(contacts, timestamp: timestamp, settings: settings, physicalButtonDown: pressed)
        session.contactCount = contacts.count
        sessions[device] = session
        let action = gesture.map { settings.action(for: $0) } ?? .none
        lock.unlock()
        guard let gesture, action != .none else { return }
        // A physical click can arrive just after its touch-release frame. Give it
        // one short cancellation window instead of synthesizing a second click.
        DispatchQueue.main.asyncAfter(deadline: .now() + (gesture.isSwipe ? 0 : 0.04)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = token == self.generation && self.lastPhysicalClick < now - 0.08
            self.lock.unlock()
            guard valid, self.running, AXIsProcessTrusted() else { return }
            self.execute(action)
        }
    }

    private func installEventTap() {
        removeEventTap()
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
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
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; eventSource = nil
    }

    private func filter(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag else { return false }
        lock.lock()
        if type != .scrollWheel {
            lastPhysicalClick = ProcessInfo.processInfo.systemUptime
            for key in sessions.keys { sessions[key]?.recognizer.cancel() }
            lock.unlock(); return false
        }
        let reserveTwoFingerScroll = settings.hasSwipes && sessions.values.contains { $0.contactCount == 2 && $0.recognizer.acceptsSwipe }
        let moved = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0 ||
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) != 0
        if moved { for key in sessions.keys { sessions[key]?.recognizer.cancelTap() } }
        lock.unlock()
        // Only suppress confirmed Magic Mouse events. Trackpad/other-mouse input
        // and unidentified senders always pass, even while mouse fingers rest.
        return reserveTwoFingerScroll && eventIdentity.isMagicMouse(event)
    }

    private func execute(_ action: MagicMouseAction) {
        let mapped: GestureAction
        switch action {
        case .none: return
        case .leftClick, .rightClick, .middleClick:
            let button: CGMouseButton = action == .leftClick ? .left : action == .rightClick ? .right : .center
            let down: CGEventType = button == .left ? .leftMouseDown : button == .right ? .rightMouseDown : .otherMouseDown
            let up: CGEventType = button == .left ? .leftMouseUp : button == .right ? .rightMouseUp : .otherMouseUp
            guard let position = CGEvent(source: nil)?.location else { return }
            for type in [down, up] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { continue }
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.post(tap: .cghidEventTap)
            }
            return
        case .missionControl: mapped = .missionControl
        case .showDesktop: mapped = .showDesktop
        case .nextApp: mapped = .switchAppNext
        case .previousApp: mapped = .switchAppPrev
        case .snapLeft: mapped = .snapLeft
        case .snapRight: mapped = .snapRight
        case .maximize: mapped = .maximizeWindow
        case .restore: mapped = .restoreWindow
        case .minimize: mapped = .minimizeWindow
        case .playPause: mapped = .playPause
        case .nextTrack: mapped = .nextTrack
        case .previousTrack: mapped = .previousTrack
        case .volumeUp: mapped = .volumeUp
        case .volumeDown: mapped = .volumeDown
        case .mute: mapped = .muteToggle
        }
        ActionExecutor.shared.execute(mapped)
    }
}

private let mouseFrameCallback: MouseMTCallback = { device, raw, count, timestamp, _ in
    if let device { MagicMouseInput.shared.receive(device: device, raw: raw, count: count, timestamp: timestamp) }
    return 0
}

/// Optional sender attribution keeps mouse swipe suppression off other devices.
/// Cache by HID sender, and clear on device changes. Unknown APIs/devices pass.
private final class MouseEventIdentity {
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
