import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeScrollSession
//
// Smooths a single edge-scroll gesture and carries it past the finger lift.
//
// Multitouch frames arrive at uneven intervals and each position carries a
// little sensor noise, so posting every frame's travel straight to the scroll
// wheel reads as judder even though the finger moved evenly. Travel is buffered
// here and released in step with the display's refresh instead, then the gesture
// coasts on whatever velocity the finger had at release so a flick keeps gliding
// the way native trackpad scrolling does.
//
// Output is shaped like a two-finger trackpad scroll rather than a mouse wheel:
// one began → changed → ended run while the finger is down, then a separate
// momentum run for the coast. See `ScrollDriver.scrollContinuous` for why.
//
// Total distance is preserved: smoothing only redistributes travel in time, so
// the Scroll Speed setting still means exactly what it says. Momentum is the one
// thing that adds distance, and it is optional.
//
// All methods run on the main thread.
// ─────────────────────────────────────────────────────────────────────────────

final class EdgeScrollSession {

    static let shared = EdgeScrollSession()
    private init() {}

    // MARK: - Tuning

    /// Ceiling on a single integration step, so a stalled main thread cannot
    /// discharge its whole backlog into one jump.
    private static let maxStep = 0.05

    /// Time constant for releasing buffered travel.
    ///
    /// Picked by sweeping it against simulated 90 Hz frames carrying ±45% position
    /// noise. Shorter is more responsive but rougher; longer is smoother but lags.
    /// RMS velocity error bottoms out around 45–55 ms — past that, output lags far
    /// enough behind the finger that accuracy gets worse again, not better. 45 ms
    /// sits at that minimum: roughly 8× less tick-to-tick judder than emitting
    /// frames raw, for about 22 ms of delay.
    private static let releaseTau = 0.045

    /// Time constant for the velocity estimate that seeds the coast.
    private static let velocityTau = 0.045

    /// Time constant for momentum decay once the finger is gone.
    ///
    /// A decay of time constant `tau` carries a flick `v * tau` further. At 0.25 s
    /// the coast was over before it registered as a glide; 0.4 s sits close to the
    /// distance a native two-finger flick travels.
    private static let momentumTau = 0.4

    /// Decay used instead of momentum — just long enough to hand over the buffered
    /// remainder without a visible step.
    private static let settleTau = 0.030

    /// Finger speed above which a lift counts as a flick worth coasting on.
    ///
    /// Momentum has to be earned. Coasting off any lift means a slow, deliberate
    /// drag keeps travelling after the finger stops, which overshoots exactly when
    /// the user was being careful. Thresholds are in millimetres of finger travel
    /// per second so they keep meaning the same thing when Scroll Speed changes.
    private static let flickThresholdMmPerSecond = 25.0

    /// Finger-speed equivalent at which a coast is close enough to stopped.
    private static let stopThresholdMmPerSecond = 1.0

    /// Below this the buffer counts as empty.
    private static let minPendingPoints = 0.05

    // MARK: - State

    private let clock = ScrollClock()
    private var lastTick: TimeInterval = 0

    /// Which phase run the posted events belong to, and whether that run has
    /// emitted its opening event yet. Apps track a scroll by these phases, so every
    /// run that opens is closed with its own end event.
    private enum Output: Equatable {
        case idle
        case scrolling(opened: Bool)
        case momentum(opened: Bool)
    }
    private var output = Output.idle

    /// Travel handed over but not yet emitted, in scroll points.
    private var pending = 0.0

    /// Smoothed emission rate in points/second, used to seed momentum.
    private var velocity = 0.0

    private var isCoasting = false

    /// Decay applied while coasting: momentum after a flick, or the shorter settle
    /// when momentum is switched off.
    private var coastTau = EdgeScrollSession.momentumTau

    /// Scroll gain in effect for this gesture, used to convert the mm/s thresholds
    /// into the points/second the loop actually works in.
    private var pointsPerMm = 26.0

    /// Whether the drive clock is running, either releasing travel or coasting.
    var isRunning: Bool { clock.isRunning }

    /// Whether the gesture is gliding on earned momentum, as opposed to the brief
    /// settle that hands over the buffered remainder. Both decay; only this one is
    /// the flick carrying on past the finger.
    var isFlickGlide: Bool { isCoasting && coastTau == Self.momentumTau }

    private var flickVelocity: Double { Self.flickThresholdMmPerSecond * pointsPerMm }
    private var stopVelocity: Double { Self.stopThresholdMmPerSecond * pointsPerMm }

    // MARK: - Lifecycle

    /// Starts a fresh gesture, dropping anything left over from the last one.
    func begin(pointsPerMm: Double) {
        stopTimer()
        closeOutput()
        output = .scrolling(opened: false)
        pending = 0
        velocity = 0
        isCoasting = false
        self.pointsPerMm = max(abs(pointsPerMm), 0.001)
        ScrollDriver.shared.begin()
    }

    /// Hands over one frame's worth of travel, already converted to points.
    func addTravel(points: Double) {
        guard points.isFinite, points != 0 else { return }
        // New input always wins over a coast still in flight — a finger back on
        // the edge is steering again, not watching the last flick play out.
        isCoasting = false
        if case .scrolling = output {} else {
            closeOutput()
            output = .scrolling(opened: false)
        }
        pending += points
        startTimer()
    }

    /// The finger is gone. Hands the remainder over as a decaying glide.
    ///
    /// The release lag leaves real distance sitting in the buffer at lift — about
    /// 70 points during a brisk slide — so it can neither be dropped (the gesture
    /// would come up short) nor emitted at once (a visible jump). Instead it is
    /// converted into starting velocity: a decay of time constant `tau` travels
    /// exactly `v * tau`, so seeding `pending / tau` delivers the leftover travel
    /// smoothly and lands the total in the right place either way.
    ///
    /// After a flick that boost rides on top of the finger's own velocity and
    /// decays slowly, giving the glide. Otherwise there is no carried velocity and
    /// a much shorter decay, so scrolling settles at once instead of coasting.
    func end(momentum: Bool) {
        guard clock.isRunning || abs(pending) > Self.minPendingPoints else {
            finish()
            return
        }

        let isFlick = momentum && abs(velocity) >= flickVelocity
        coastTau = isFlick ? Self.momentumTau : Self.settleTau
        velocity = (isFlick ? velocity : 0) + pending / coastTau
        pending = 0

        guard abs(velocity) >= stopVelocity else {
            finish()
            return
        }

        // The finger's run ends here; whatever is still travelling is momentum.
        // A run that never emitted still opens first, so the momentum that follows
        // belongs to a scroll the app has actually seen begin.
        if case .scrolling(let opened) = output {
            if !opened { post(0, .began) }
            post(0, .ended)
        }
        output = .momentum(opened: false)
        isCoasting = true
        startTimer()
    }

    /// Hard stop: drops momentum and any buffered travel.
    func cancel() {
        finish()
    }

    // MARK: - Drive loop

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - lastTick, Self.maxStep)
        lastTick = now
        guard elapsed > 0 else { return }

        if isCoasting {
            // Exact distance for this step, not `velocity * elapsed`. That
            // rectangle is a right-endpoint approximation of the decay, and once
            // the time constant approaches the tick interval it under-delivers
            // badly — over 10% at settle length, which reads as travel quietly
            // going missing off the end of every gesture.
            let decay = exp(-elapsed / coastTau)
            emit(velocity * coastTau * (1 - decay))
            velocity *= decay
            if abs(velocity) < stopVelocity { finish() }
            return
        }

        guard abs(pending) > Self.minPendingPoints else {
            // Finger still down but holding still. Nothing to release, so park the
            // clock instead of spinning at 120 Hz and let `addTravel` restart it.
            // Velocity goes with it: a finger that stopped should not coast.
            velocity = 0
            stopTimer()
            return
        }

        // Exponential release, expressed against elapsed time so the feel does not
        // change when a frame is late.
        let release = pending * (1 - exp(-elapsed / Self.releaseTau))
        pending -= release
        emit(release)

        let instant = release / elapsed
        velocity += (instant - velocity) * (1 - exp(-elapsed / Self.velocityTau))
    }

    private func emit(_ points: Double) {
        guard points != 0 else { return }
        switch output {
        case .idle, .scrolling(opened: false):
            output = .scrolling(opened: true)
            post(points, .began)
        case .scrolling(opened: true):
            post(points, .changed)
        case .momentum(opened: false):
            output = .momentum(opened: true)
            post(points, .momentumBegan)
        case .momentum(opened: true):
            post(points, .momentumChanged)
        }
    }

    private func post(_ points: Double, _ phase: ScrollDriver.Phase) {
        ScrollDriver.shared.scrollContinuous(vertical: points, horizontal: 0, phase: phase)
    }

    /// Ends whichever run is open with its terminating event.
    private func closeOutput() {
        switch output {
        case .scrolling(opened: true): post(0, .ended)
        case .momentum(opened: true):  post(0, .momentumEnded)
        case .idle, .scrolling(opened: false), .momentum(opened: false): break
        }
        output = .idle
    }

    private func finish() {
        stopTimer()
        closeOutput()
        pending = 0
        velocity = 0
        isCoasting = false
        coastTau = Self.momentumTau
    }

    // MARK: - Clock

    private func startTimer() {
        guard !clock.isRunning else { return }
        // Reset the integration clock on every restart, or the first step after a
        // pause would bill itself for the whole idle interval.
        lastTick = ProcessInfo.processInfo.systemUptime
        clock.start { [weak self] in self?.tick() }
    }

    private func stopTimer() {
        clock.stop()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ScrollClock
//
// Fires once per refresh of the display under the pointer.
//
// A fixed 120 Hz timer beats against any display that is not exactly 120 Hz: on
// a 60 Hz screen two ticks land in some frames and none in others, so content
// alternates between moving one step and two — the judder this whole session
// exists to remove. Ticking on the display's own refresh gives every frame one
// step. macOS 13 has no per-screen display link, so it keeps the timer.
// ─────────────────────────────────────────────────────────────────────────────

private final class ScrollClock: NSObject {

    private static let fallbackInterval = 1.0 / 120.0

    private var handler: (() -> Void)?
    private var displayLink: AnyObject?
    private var timer: DispatchSourceTimer?

    var isRunning: Bool { handler != nil }

    func start(_ handler: @escaping () -> Void) {
        stop()
        self.handler = handler

        if #available(macOS 14.0, *), let screen = Self.screenUnderPointer() {
            let link = screen.displayLink(target: self, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            displayLink = link
            return
        }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + Self.fallbackInterval,
                        repeating: Self.fallbackInterval,
                        leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.fire() }
        timer = source
        source.resume()
    }

    func stop() {
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
            link.invalidate()
        }
        displayLink = nil
        timer?.cancel()
        timer = nil
        handler = nil
    }

    @objc private func fire() {
        handler?()
    }

    private static func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}
