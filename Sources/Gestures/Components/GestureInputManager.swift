import Cocoa
import ApplicationServices

final class GestureInputManager {
    weak var engine: GestureEngine?
    private let eventIdentity = MouseEventIdentity()

    var suppressionTap: CFMachPort?
    var suppressionSource: CFRunLoopSource?
    private(set) var suppressionEnabled = false

    /// During the zoom double-tap window the tap stays active, but gesture-class
    /// events are passed through so macOS can recognize the tap. Scroll is always
    /// swallowed at 3+ fingers regardless, so a moving swipe can't scrub video.
    var tapWindowActive = false

    var clickObservationTap: CFMachPort?
    var clickObservationSource: CFRunLoopSource?
    var clickTapInstalled = false

    var pointerSuppressionTap: CFMachPort?
    var pointerSuppressionSource: CFRunLoopSource?
    private(set) var pointerSuppressionEnabled = false

    /// Features that currently need native pointer motion swallowed. Held as a
    /// set rather than a flag so a second feature can share the tap without one
    /// finishing first and switching it off underneath the other.
    private var pointerSuppressionOwners: Set<PointerSuppressionOwner> = []

    enum PointerSuppressionOwner: Hashable {
        case edgeControls
    }

    var interactionMonitors: [Any] = []
    var pressureMonitor: Any?
    var lastForceClickTime: TimeInterval = 0
    let forceCooldown: TimeInterval = 0.4

    init(engine: GestureEngine) {
        self.engine = engine
    }

    func setupTaps() {
        setupSuppressionTap()
        setupClickObservationTap()
        // The pointer-suppression tap is created the first time a feature claims
        // it — most users never own an event tap they never use.
    }

    func teardownTaps() {
        teardownSuppressionTap()
        teardownClickObservationTap()
        teardownPointerSuppressionTap()
    }

    func setupSuppressionTap() {
        let mask = UInt64(NSEvent.EventTypeMask.gesture.rawValue)
                 | UInt64(NSEvent.EventTypeMask.pressure.rawValue)
                 | UInt64(1 << CGEventType.scrollWheel.rawValue)
                 | UInt64(1 << CGEventType.leftMouseDown.rawValue)

        suppressionTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if GestureEngine.shared.inputManager.suppressionEnabled,
                       let tap = GestureEngine.shared.inputManager.suppressionTap {
                        AppLogger.debug("[Input] Suppression tap timed out — re-enabling")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                if type == .leftMouseDown {
                    if TouchTracker.glideActiveTouches >= 3 {
                        TouchTracker.glideClickFingerCount = TouchTracker.glideActiveTouches
                    }
                    return Unmanaged.passUnretained(cgEvent)
                }
                if TouchTracker.glideActiveTouches >= 3 {
                    let im = GestureEngine.shared.inputManager!
                    let isScroll = type.rawValue == CGEventType.scrollWheel.rawValue
                    // Deep-press events are gesture-class, so this tap swallows them
                    // while 3+ fingers are down — exactly when a force click can happen.
                    // The NSEvent pressure monitor would never see them; detect here first.
                    if !isScroll, let ns = NSEvent(cgEvent: cgEvent), ns.type == .pressure {
                        im.handleDeepPress(stage: ns.stage)
                    }
                    // Always swallow scroll at 3+ fingers so a 3-finger swipe can't
                    // reach apps (e.g. scrub a video). In the zoom tap window, still
                    // pass gesture-class events so the double-tap is recognized.
                    if isScroll { return nil }
                    return im.tapWindowActive ? Unmanaged.passUnretained(cgEvent) : nil
                }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: nil)

        if let tap = suppressionTap {
            suppressionSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            // The main run loop explicitly, not "the current one". Every caller is
            // already on main, so this changes nothing today — but a teardown that
            // resolved a different run loop than its setup would strand the source
            // on main forever, and `checkHealth` tears these down and rebuilds them.
            CFRunLoopAddSource(CFRunLoopGetMain(), suppressionSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func setSuppressionActive(_ active: Bool) {
        guard active != suppressionEnabled, let tap = suppressionTap else { return }
        suppressionEnabled = active
        CGEvent.tapEnable(tap: tap, enable: active)
    }

    func teardownSuppressionTap() {
        if let tap = suppressionTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = suppressionSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        // Dropping the last Swift reference is not enough to take the tap down: the
        // Mach port has to be invalidated or the tap stays registered with the
        // WindowServer, which keeps handing it events nobody reads. `checkHealth`
        // rebuilds these on every failure, so each rebuild leaked one live tap.
        if let tap = suppressionTap { CFMachPortInvalidate(tap) }
        suppressionTap    = nil
        suppressionSource = nil
        suppressionEnabled = false
    }

    // MARK: - Pointer suppression
    //
    // An edge control runs on a single finger, which macOS also reads as ordinary
    // pointer movement. While one is active this tap swallows native pointer
    // movement, passing only the events CursorDriver and ScrollDriver post
    // (identified by their source user data). Scroll is covered too, so native
    // momentum left over from a two-finger scroll cannot land on top of an edge
    // scroll.

    func setupPointerSuppressionTap() {
        let mask = UInt64(1 << CGEventType.mouseMoved.rawValue)
                 | UInt64(1 << CGEventType.leftMouseDragged.rawValue)
                 | UInt64(1 << CGEventType.rightMouseDragged.rawValue)
                 | UInt64(1 << CGEventType.otherMouseDragged.rawValue)
                 | UInt64(1 << CGEventType.scrollWheel.rawValue)

        pointerSuppressionTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if GestureEngine.shared.inputManager.pointerSuppressionEnabled,
                       let tap = GestureEngine.shared.inputManager.pointerSuppressionTap {
                        AppLogger.debug("[Input] Pointer suppression tap timed out — re-enabling")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                if cgEvent.getIntegerValueField(.eventSourceUserData) == CursorDriver.syntheticMarker {
                    return Unmanaged.passUnretained(cgEvent)
                }
                return nil
            },
            userInfo: nil)

        if let tap = pointerSuppressionTap {
            pointerSuppressionSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), pointerSuppressionSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    /// Claims or releases pointer suppression on behalf of one feature. The tap
    /// stays on as long as any owner still holds it.
    func setPointerSuppression(_ active: Bool, owner: PointerSuppressionOwner) {
        if active {
            pointerSuppressionOwners.insert(owner)
        } else {
            pointerSuppressionOwners.remove(owner)
        }
        applyPointerSuppression(!pointerSuppressionOwners.isEmpty)
    }

    private func applyPointerSuppression(_ active: Bool) {
        guard active != pointerSuppressionEnabled else { return }
        // Create on demand: the tap only exists once the feature is used.
        if active && pointerSuppressionTap == nil { setupPointerSuppressionTap() }
        guard let tap = pointerSuppressionTap else { return }
        pointerSuppressionEnabled = active
        CGEvent.tapEnable(tap: tap, enable: active)
    }

    func teardownPointerSuppressionTap() {
        if let tap = pointerSuppressionTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = pointerSuppressionSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let tap = pointerSuppressionTap { CFMachPortInvalidate(tap) }
        pointerSuppressionTap    = nil
        pointerSuppressionSource = nil
        pointerSuppressionEnabled = false
        pointerSuppressionOwners.removeAll()
    }

    func setupClickObservationTap() {
        guard !clickTapInstalled else { return }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        clickObservationTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = GestureEngine.shared.inputManager.clickObservationTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                guard event.getIntegerValueField(.eventSourceUserData) != SyntheticMouseInput.tag else { return Unmanaged.passUnretained(event) }
                LowFingerTrackpadInput.shared.observeNativeEvent(type, confirmedTrackpad: GestureEngine.shared.inputManager.eventIdentity.isTrackpad(event))
                guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
                let count = TouchTracker.getThreeFingerCount()
                let peak = TouchTracker.getSessionPeakActiveTouches()
                if TouchTracker.clickGestureMatchesFingerState(count: count, peak: peak) {
                    // No app haptic here: a physical click already gives native
                    // down/up feedback — adding one reads as a triple "crunch".
                    DispatchQueue.main.async { GestureEngine.shared.processClick(fingerCount: count) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)

        if let tap = clickObservationTap {
            clickObservationSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), clickObservationSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            clickTapInstalled = true
        }
    }

    func teardownClickObservationTap() {
        if let tap = clickObservationTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = clickObservationSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let tap = clickObservationTap { CFMachPortInvalidate(tap) }
        clickObservationTap    = nil
        clickObservationSource = nil
        clickTapInstalled      = false
    }

    func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.engine?.handleExternalInteraction()
        }) { interactionMonitors.append(m) }

        // Resolve a deferred click on release: if no deep press arrived before the
        // fingers lifted, it was a normal click. Dispatched async so it always runs
        // after the mouse-down's processClick has registered the pending click — the
        // flush itself stays inside the async for that ordering, since the pending
        // click can still be in flight at the instant the mouse-up fires. Skipping the
        // dispatch while the engine is stopped keeps every system-wide click from
        // scheduling a main-queue block that could have nothing to do.
        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            guard self?.engine?.isRunning == true else { return }
            DispatchQueue.main.async { self?.engine?.flushPendingClick() }
        }) { interactionMonitors.append(up) }

        // Fallback path only — while 3+ fingers are down the suppression tap consumes
        // pressure events before they reach this monitor, and calls handleDeepPress itself.
        let pressureMask = NSEvent.EventTypeMask(rawValue: 1 << NSEvent.EventType.pressure.rawValue)
        pressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: pressureMask) { [weak self] event in
            self?.handleDeepPress(stage: event.stage)
        }
        if let pm = pressureMonitor { interactionMonitors.append(pm) }
    }

    /// Deep-press (stage 2) → force click. Called from both the suppression tap and the
    /// NSEvent pressure monitor; the cooldown dedupes if both ever see the same press.
    func handleDeepPress(stage: Int) {
        guard stage >= 2, let engine = engine, engine.isRunning else { return }
        let count = TouchTracker.getThreeFingerCount()
        let peak = TouchTracker.getSessionPeakActiveTouches()
        guard TouchTracker.clickGestureMatchesFingerState(count: count, peak: peak) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastForceClickTime > forceCooldown else { return }
        lastForceClickTime = now
        DispatchQueue.main.async { engine.processForceClick(fingerCount: count) }
    }

    func removeMonitors() {
        interactionMonitors.forEach { NSEvent.removeMonitor($0) }
        interactionMonitors.removeAll()
        pressureMonitor = nil
    }

    func checkHealth() {
        if let tap = suppressionTap {
            if !CFMachPortIsValid(tap) {
                teardownSuppressionTap(); setupSuppressionTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) && suppressionEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        if let tap = clickObservationTap {
            if !CFMachPortIsValid(tap) {
                teardownClickObservationTap(); setupClickObservationTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        if let tap = pointerSuppressionTap {
            if !CFMachPortIsValid(tap) {
                // Teardown clears the owner set, so carry it across the rebuild —
                // otherwise a live edge control loses its claim and the native
                // pointer starts fighting the synthetic events again.
                let owners = pointerSuppressionOwners
                teardownPointerSuppressionTap(); setupPointerSuppressionTap()
                pointerSuppressionOwners = owners
                applyPointerSuppression(!owners.isEmpty)
            } else if !CGEvent.tapIsEnabled(tap: tap) && pointerSuppressionEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
}
