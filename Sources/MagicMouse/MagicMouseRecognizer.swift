import Foundation

struct MouseContact: Equatable {
    let id: Int32
    let x: Double
    let y: Double
}

/// A separate recognizer per physical mouse. No timers, UI, or system side effects.
/// A gesture is rearmed only after every contact lifts, preventing partial lifts
/// and resting fingers from turning a click or scroll into an extra tap.
struct MagicMouseRecognizer {
    private var origins: [Int32: MouseContact] = [:]
    private var previousIDs: Set<Int32> = []
    private var start = 0.0
    private var lastTimestamp = 0.0
    private var peak = 0
    private var maxMovement = 0.0
    private var tapX = 0.5
    private var cancelled = false
    private var tapCancelled = false
    private var emitted = false
    private var lifting = false
    private(set) var isTouching = false
    private(set) var suppressScroll = false

    var acceptsSwipe: Bool { isTouching && !cancelled && !lifting && peak == 2 }

    mutating func cancelTap() { tapCancelled = true }
    mutating func cancel() { cancelled = true; suppressScroll = false }
    mutating func reset() { self = Self() }

    mutating func consume(_ contacts: [MouseContact], timestamp: Double,
                          settings: MagicMouseSettings, physicalButtonDown: Bool = false) -> MagicMouseGesture? {
        guard timestamp.isFinite, contacts.count <= 5,
              Set(contacts.map(\.id)).count == contacts.count,
              contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            cancel(); return nil
        }
        if timestamp < lastTimestamp || (isTouching && timestamp - lastTimestamp > 1.5) {
            // Never act on an incomplete session after a device reset or missing release.
            reset(); cancelled = !contacts.isEmpty
        }
        lastTimestamp = timestamp
        guard settings.enabled else { reset(); return nil }
        if contacts.isEmpty {
            defer { reset() }
            guard isTouching, !cancelled, !tapCancelled, !emitted, !physicalButtonDown,
                  timestamp - start >= 0.025, timestamp - start <= settings.tapDuration,
                  maxMovement <= settings.tapMovement else { return nil }
            switch peak {
            case 1: return tapX < 0.5 ? .leftTap : .rightTap
            case 2: return .twoFingerTap
            case 3: return .threeFingerTap
            default: return nil
            }
        }
        if !isTouching {
            isTouching = true
            start = timestamp
            tapX = contacts[0].x
        }
        if physicalButtonDown { cancel() }
        let ids = Set(contacts.map(\.id))
        if !previousIDs.isSubset(of: ids) { lifting = true }
        if lifting && !ids.isSubset(of: previousIDs) { cancel() }
        for contact in contacts where origins[contact.id] == nil {
            // Fingers should land together. Adding one to a resting finger is not a tap.
            if timestamp - start > 0.10 { cancel() }
            origins[contact.id] = contact
        }
        previousIDs = ids
        peak = max(peak, contacts.count)
        var dx = 0.0, dy = 0.0
        var deltas: [(Double, Double)] = []
        for contact in contacts {
            guard let origin = origins[contact.id] else { continue }
            let x = contact.x - origin.x, y = contact.y - origin.y
            maxMovement = max(maxMovement, hypot(x, y))
            dx += x; dy += y; deltas.append((x, y))
        }
        guard !cancelled, !emitted, !lifting, contacts.count == 2, peak == 2,
              timestamp - start <= 1.0, settings.hasSwipes else { return nil }
        dx /= 2; dy /= 2
        let horizontal = abs(dx) > abs(dy) * 1.5
        let vertical = abs(dy) > abs(dx) * 1.5
        guard horizontal || vertical else { return nil }
        let distance = horizontal ? dx : dy
        guard abs(distance) >= settings.swipeDistance,
              deltas.allSatisfy({ (horizontal ? $0.0 : $0.1) * distance > 0 &&
                  abs(horizontal ? $0.0 : $0.1) >= settings.swipeDistance * 0.5 }) else { return nil }
        let gesture: MagicMouseGesture = horizontal ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeDown : .swipeUp)
        guard settings.action(for: gesture) != .none else { return nil }
        emitted = true
        suppressScroll = true
        return gesture
    }
}
