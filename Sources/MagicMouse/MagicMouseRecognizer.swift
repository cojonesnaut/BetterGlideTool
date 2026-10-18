import Foundation

struct MouseContact: Equatable {
    let id: Int32
    let x: Double
    let y: Double
    var size: Double = 1
}

/// A separate recognizer per physical mouse. No timers, UI, or system side effects.
/// A gesture is rearmed only after every contact lifts, preventing partial lifts
/// and resting fingers from turning a click or scroll into an extra tap.
private struct BasicTouchRecognizer {
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

    var tapLocation: MouseContact? {
        guard !origins.isEmpty else { return nil }
        return MouseContact(id: origins.values.first!.id,
            x: origins.values.map(\.x).reduce(0, +) / Double(origins.count),
            y: origins.values.map(\.y).reduce(0, +) / Double(origins.count))
    }
    var acceptsSwipe: Bool { isTouching && !cancelled && !lifting && (1...4).contains(peak) }

    mutating func cancelTap() { tapCancelled = true }
    mutating func cancel() { cancelled = true; suppressScroll = false }
    mutating func reset() { self = Self() }

    mutating func consume(_ contacts: [MouseContact], timestamp: Double,
                          settings: MagicMouseSettings, physicalButtonDown: Bool = false) -> MagicMouseGesture? {
        guard timestamp.isFinite, contacts.count <= 5,
              Set(contacts.map(\.id)).count == contacts.count,
              contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.size.isFinite && $0.size >= 0 && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
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
            case 4: return settings.action(for: .fourFingerTap) != .none || settings.action(for: .fourFingerDoubleTap) != .none ? .fourFingerTap : nil
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
        guard !cancelled, !emitted, !lifting, (1...4).contains(contacts.count), peak == contacts.count,
              timestamp - start <= 1.0, settings.hasSwipes(fingers: peak) else { return nil }
        dx /= Double(peak); dy /= Double(peak)
        let horizontal = abs(dx) > abs(dy) * MagicMouseSettings.swipeAxisDominance
        let vertical = abs(dy) > abs(dx) * MagicMouseSettings.swipeAxisDominance
        guard horizontal || vertical else { return nil }
        let distance = horizontal ? dx : dy
        guard abs(distance) >= settings.swipeDistance,
              deltas.allSatisfy({ (horizontal ? $0.0 : $0.1) * distance > 0 &&
                  abs(horizontal ? $0.0 : $0.1) >= settings.swipeDistance * 0.5 }) else { return nil }
        let gesture: MagicMouseGesture
        if peak == 1 {
            gesture = horizontal ? (dx < 0 ? .oneFingerSwipeLeft : .oneFingerSwipeRight) : (dy < 0 ? .oneFingerSwipeDown : .oneFingerSwipeUp)
        } else if peak == 4 {
            gesture = horizontal ? (dx < 0 ? .fourFingerSwipeLeft : .fourFingerSwipeRight) : (dy < 0 ? .fourFingerSwipeDown : .fourFingerSwipeUp)
        } else if peak == 3 {
            gesture = horizontal ? (dx < 0 ? .threeFingerSwipeLeft : .threeFingerSwipeRight) : (dy < 0 ? .threeFingerSwipeDown : .threeFingerSwipeUp)
        } else {
            gesture = horizontal ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeDown : .swipeUp)
        }
        guard settings.action(for: gesture) != .none else { return nil }
        emitted = true
        suppressScroll = true
        return gesture
    }
}


enum TipTapRejection: String {
    case anchorsMoved = "Resting fingers moved; let them settle before the next tap."
    case anchorLifted = "Resting contact changed; let the fingers settle, then tap again."
    case notSettled = "Resting fingers had not settled. Check TipTap anchor timing."
    case spacing = "Fingers were outside the TipTap spacing limits."
    case light = "Tap contact was too light. Lower TipTap sensitivity."
    case short = "Tap was too brief. Check TipTap minimum duration."
    case long = "Finger stayed down too long for a tap."
    case moved = "Tapping finger moved too far."
    case scrolling = "Scrolling or pointer movement cancelled this tap."
    case extraContact = "An extra contact interrupted the tap. Lift the tapping fingers, then tap again."
    case tipChanged = "Tapping contact changed. Lift the tapping finger, then tap again."
    case debounce = "Tap began before the previous release had settled."
}

/// Adds double-tap arbitration, fixed-finger TipTaps, and physical
/// clicks to the shared touch recognizer. Deadlines are serviced by one-shot
/// dispatches in the providers, never a repeating timer.
struct MagicMouseRecognizer {
    private(set) var tipTapFeedback: String?
    private(set) var lastTapLocation: MouseContact?
    private var basic = BasicTouchRecognizer()
    private var oneFixed = FixedFingerRecognizer(anchorCount: 1)
    private var twoFixed = FixedFingerRecognizer(anchorCount: 2)
    private var threeFixed = FixedFingerRecognizer(anchorCount: 3)
    private var circle = CirclePathRecognizer()
    private var pendingTapGesture: MagicMouseGesture = .twoFingerTap
    var ownsFixedFingerSession: Bool { oneFixed.claimed || twoFixed.claimed || threeFixed.claimed }

    /// How long after a TipTap tip lifts a trackpad button-down still counts as
    /// macOS's tap-to-click for that tip. Recorded sessions put it 30–90 ms after
    /// the lift, lasting 60–100 ms.
    static let tapClickEchoWindow = 0.25
    /// A tip that landed this recently has not had time to press the pad down.
    static let freshTipWindow = 0.10

    /// Whether a trackpad button-down at `time` (frame clock) is the tap-to-click
    /// macOS synthesises for the tip of a TipTap, rather than a physical press.
    ///
    /// The two are indistinguishable in the event itself — same fields, same
    /// device, same pressure. Timing tells them apart: the synthesised click
    /// arrives just after the tip lifts while the resting fingers stay down,
    /// whereas a physical press arrives while a finger is still pushing.
    /// What `isTapToClickEcho` saw at `time`, for diagnostics.
    func echoDiagnostics(at time: Double) -> String {
        let names = ["1-fix", "2-fix", "3-fix"]
        let parts = zip(names, [oneFixed, twoFixed, threeFixed]).map { name, s in
            let release = s.tipReleaseTime.map { String(format: "%+.3f", $0 - time) } ?? "none"
            let down = s.tipDownSince.map { String(format: "%+.3f", $0 - time) } ?? "none"
            return "\(name)[claimed=\(s.claimed) release=\(release) tipDown=\(down)]"
        }
        return "echo=\(isTapToClickEcho(at: time)) blocked=\(blocked) " + parts.joined(separator: " ")
    }

    func isTapToClickEcho(at time: Double) -> Bool {
        let sessions = [oneFixed, twoFixed, threeFixed].filter(\.claimed)
        guard !sessions.isEmpty,
              let release = sessions.compactMap(\.tipReleaseTime).max(),
              time >= release, time - release <= Self.tapClickEchoWindow else { return false }
        // With fast tapping the next tip can already be down. Only one that has
        // just landed is excused; one held longer could be pressing for real.
        if let down = sessions.compactMap(\.tipDownSince).max(), time - down > Self.freshTipWindow { return false }
        return true
    }
    /// Read-only diagnostic roles; never changes arbitration or timing.
    var liveContactRoles: [Int32: String] {
        if blocked { return Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, "Blocked") }) }
        let candidates = [oneFixed, twoFixed, threeFixed]
        let selected = candidates.first { $0.claimed } ?? candidates.max { $0.liveContactRoles.count < $1.liveContactRoles.count }
        let roles = selected?.liveContactRoles ?? [:]
        return roles.filter { id, _ in contacts.contains { $0.id == id } }
    }
    var liveTrackpadButtons: [Int] { trackpadButtons.sorted() }
    var reservesTipSwipe: Bool { !twoFixed.reservedAxes.isEmpty }
    var tipSwipeAxes: MouseScrollAxes { twoFixed.reservedAxes }
    private var contacts: [MouseContact] = []
    private var lastSettings = MagicMouseSettings()
    private var blocked = false
    private var trackpadButtonRecovery = false
    private var trackpadButtons: Set<Int> = []
    private var lastTime = 0.0
    private var center = MouseContact(id: 0, x: 0.5, y: 0.5)
    private var firstTapCenter = MouseContact(id: 0, x: 0.5, y: 0.5)
    private(set) var pendingTapDeadline: Double?
    var isRestingForTipTap: Bool {
        !blocked && (oneFixed.isResting || twoFixed.isResting || threeFixed.isResting)
    }
    // A stage switch can finish during the next stroke. Cancel that stroke,
    // but keep its anchors so a fresh tap works under the new app's rules.
    mutating func changeAppContext() {
        pendingTapDeadline = nil
        if ownsFixedFingerSession && !blocked {
            oneFixed.changeAppContext(); twoFixed.changeAppContext(); threeFixed.changeAppContext()
            basic.cancel(); circle.cancel()
        }
        else {
            let touching = isTouching
            reset()
            if touching { cancel() }
        }
    }
    var isTouching: Bool { basic.isTouching }
    var acceptsSwipe: Bool { basic.acceptsSwipe }
    var suppressScroll: Bool { basic.suppressScroll }
    mutating func reset() { self = Self() }
    mutating func cancel(reason: String = "Input cancelled the touch session. Lift all fingers, then try again.") {
        if isTouching || ownsFixedFingerSession { tipTapFeedback = reason }
        trackpadButtonRecovery = false
        blocked = true; basic.cancel(); pendingTapDeadline = nil; oneFixed.cancel(); twoFixed.cancel(); threeFixed.cancel(); circle.cancel()
    }
    mutating func cancelTap() {
        basic.cancelTap(); pendingTapDeadline = nil; oneFixed.cancelTaps(); twoFixed.cancelTaps(); threeFixed.cancelTaps()
    }
    mutating func flushPendingTap(at time: Double) -> MagicMouseGesture? {
        guard let deadline = pendingTapDeadline, time >= deadline else { return nil }
        pendingTapDeadline = nil
        return lastSettings.action(for: pendingTapGesture) != .none ? pendingTapGesture : nil
    }
    mutating func physicalClick(timestamp: Double) -> MagicMouseGesture? {
        let gesture: MagicMouseGesture
        switch contacts.count {
        case 1:
            let point = contacts[0]
            let corner: MagicMouseGesture? = point.x <= 0.2 ? (point.y <= 0.2 ? .cornerBottomLeft : (point.y >= 0.8 ? .cornerTopLeft : nil)) :
                (point.x >= 0.8 ? (point.y <= 0.2 ? .cornerBottomRight : (point.y >= 0.8 ? .cornerTopRight : nil)) : nil)
            gesture = corner.flatMap { lastSettings.action(for: $0) != .none ? $0 : nil } ?? .oneFingerMiddleClick
        case 3: gesture = .threeFingerClick
        case 4: gesture = .fourFingerClick
        default: gesture = .twoFingerClick
        }
        let inRegion = gesture.isCornerClick || contacts.count != 1 || MagicMouseTouchRegion.isMiddle(x: contacts[0].x)
        let configured = !blocked && (1...4).contains(contacts.count) && inRegion && !ownsFixedFingerSession && lastSettings.action(for: gesture) != .none
        cancel(reason: "Mouse-button event cancelled the touch session. Lift all fingers, then try again.")
        return configured ? gesture : nil
    }
    /// Track button lifetimes separately from touch lifetimes. A trackpad button
    /// cancels the pending stroke; only a fresh stroke after button-up may fire.
    mutating func trackpadButtonChanged(_ button: Int, isDown: Bool, timestamp: Double) -> MagicMouseGesture? {
        if !isDown {
            trackpadButtons.remove(button)
            // Button-up can arrive after the tip's final touch frame. Rearm
            // that already-observed resting chord now, before the next tip lands.
            if timestamp >= lastTime, timestamp - lastTime <= 1.5 {
                rearmTrackpadAfterButton(contacts, timestamp: timestamp, settings: lastSettings)
            }
            return nil
        }
        trackpadButtons.insert(button)
        let recover = ownsFixedFingerSession && (!blocked || trackpadButtonRecovery)
        let result: MagicMouseGesture?
        if button == 0 { result = physicalClick(timestamp: timestamp) }
        else { cancel(); result = nil }
        trackpadButtonRecovery = recover
        if recover { tipTapFeedback = "Mouse-button event interrupted the tap. Release the button and tapping finger, then tap again; resting fingers can stay down." }
        return result
    }

    private mutating func rearmTrackpadAfterButton(_ contacts: [MouseContact], timestamp: Double,
                                                   settings: MagicMouseSettings) {
        guard trackpadButtonRecovery, trackpadButtons.isEmpty,
              oneFixed.rearmAfterInterruption(contacts, timestamp: timestamp, settings: settings) ||
                twoFixed.rearmAfterInterruption(contacts, timestamp: timestamp, settings: settings, allowRotatedPair: true) ||
                threeFixed.rearmAfterInterruption(contacts, timestamp: timestamp, settings: settings) else { return }
        blocked = false; trackpadButtonRecovery = false
        tipTapFeedback = "Ready for the next TipTap; resting fingers can stay down."
    }

    mutating func consume(_ incoming: [MouseContact], timestamp: Double,
                          settings: MagicMouseSettings, physicalButtonDown: Bool = false,
                          allowsTrackpadButtonRecovery: Bool = false) -> MagicMouseGesture? {
        guard settings.enabled else { reset(); return nil }
        guard timestamp.isFinite, incoming.count <= 5, Set(incoming.map(\.id)).count == incoming.count,
              incoming.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.size.isFinite && $0.size >= 0 && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            cancel(reason: "Invalid touch frame cancelled the session. Lift all fingers, then try again."); contacts = []; return nil
        }
        if timestamp < lastTime || (!contacts.isEmpty && timestamp - lastTime > 1.5) { cancel(reason: "Touch input was interrupted. Lift all fingers, then try again.") }
        lastTime = timestamp
        lastSettings = settings
        contacts = incoming
        if blocked {
            _ = basic.consume(incoming, timestamp: timestamp, settings: settings)
            if !physicalButtonDown { rearmTrackpadAfterButton(incoming, timestamp: timestamp, settings: settings) }
            if incoming.isEmpty { blocked = false; trackpadButtonRecovery = false; oneFixed = FixedFingerRecognizer(anchorCount: 1); twoFixed = FixedFingerRecognizer(anchorCount: 2); threeFixed = FixedFingerRecognizer(anchorCount: 3); circle = CirclePathRecognizer() }
            return nil
        }
        let expired = flushPendingTap(at: timestamp)
        if (2...4).contains(incoming.count) {
            center = MouseContact(id: 0, x: incoming.map(\.x).reduce(0, +) / Double(incoming.count),
                                  y: incoming.map(\.y).reduce(0, +) / Double(incoming.count))
        }
        if physicalButtonDown || !trackpadButtons.isEmpty {
            let recover = allowsTrackpadButtonRecovery && ownsFixedFingerSession && settings.tipTapSpacingGeometry == .surface
            cancel(reason: recover ? "Mouse button interrupted the tap. Release the button and tapping finger, then tap again; resting fingers can stay down." : "Mouse button was down. Lift all fingers and release the button, then try again.")
            trackpadButtonRecovery = recover
            _ = basic.consume(incoming, timestamp: timestamp, settings: settings, physicalButtonDown: true)
            return nil
        }
        // A lower-finger TipTap can become the resting chord of a higher-finger
        // TipTap. Shadow only anchor-only frames; never execute two recognizers.
        if oneFixed.claimed, incoming.count == 2 {
            _ = twoFixed.consume(incoming, timestamp: timestamp, settings: settings)
        }
        if oneFixed.claimed || twoFixed.claimed, incoming.count == 3 {
            _ = threeFixed.consume(incoming, timestamp: timestamp, settings: settings)
        }
        if oneFixed.claimed, incoming.count == 3,
           oneFixed.canBecomeAnchors(at: timestamp, settings: settings) {
            _ = twoFixed.consume(incoming, timestamp: timestamp, settings: settings)
            if twoFixed.claimed {
                oneFixed = FixedFingerRecognizer(anchorCount: 1)
                oneFixed.cancel()
            }
        } else if twoFixed.claimed, incoming.count == 4,
                  twoFixed.canBecomeAnchors(at: timestamp, settings: settings) {
            _ = threeFixed.consume(incoming, timestamp: timestamp, settings: settings)
            if threeFixed.claimed {
                twoFixed = FixedFingerRecognizer(anchorCount: 2)
                twoFixed.cancel()
            }
        }
        // Once claimed, moving fingers stay exclusive unless the stable chord
        // deliberately promotes as above. Swipes/clicks never become TipTaps.
        let fixedGesture: MagicMouseGesture?
        if oneFixed.claimed {
            fixedGesture = oneFixed.consume(incoming, timestamp: timestamp, settings: settings)
        } else if twoFixed.claimed {
            fixedGesture = twoFixed.consume(incoming, timestamp: timestamp, settings: settings)
        } else if threeFixed.claimed {
            fixedGesture = threeFixed.consume(incoming, timestamp: timestamp, settings: settings)
        } else {
            let one = oneFixed.consume(incoming, timestamp: timestamp, settings: settings)
            let two = twoFixed.consume(incoming, timestamp: timestamp, settings: settings)
            let three = threeFixed.consume(incoming, timestamp: timestamp, settings: settings)
            fixedGesture = three ?? two ?? one
        }
        let rejection = oneFixed.claimed ? oneFixed.rejection :
            (twoFixed.claimed ? twoFixed.rejection :
                (threeFixed.claimed ? threeFixed.rejection : (threeFixed.rejection ?? twoFixed.rejection ?? oneFixed.rejection)))
        if let fixedGesture { tipTapFeedback = "Recognized: \(fixedGesture.title)" }
        else if let rejection { tipTapFeedback = rejection.rawValue }
        if incoming.isEmpty {
            oneFixed = FixedFingerRecognizer(anchorCount: 1)
            twoFixed = FixedFingerRecognizer(anchorCount: 2)
            threeFixed = FixedFingerRecognizer(anchorCount: 3)
        }
        let fixedSession = ownsFixedFingerSession
        let tapLocation = basic.tapLocation
        let circlesEnabled = settings.action(for: .circleClockwise) != .none || settings.action(for: .circleCounterClockwise) != .none
        var basicSettings = settings
        if circlesEnabled {
            for gesture in [MagicMouseGesture.oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown] { basicSettings.bindings[gesture] = MagicMouseAction.none }
        }
        let circleGesture = circlesEnabled ? circle.consume(incoming, timestamp: timestamp, settings: settings) : nil
        let basicGesture = basic.consume(incoming, timestamp: timestamp, settings: basicSettings)
        let recognized = circleGesture ?? basicGesture
        if let recognized, recognized.isOneFingerTap || [.threeFingerTap, .fourFingerTap].contains(recognized) { lastTapLocation = tapLocation }
        if fixedSession {
            basic.cancel(); pendingTapDeadline = nil
            return fixedGesture
        }
        let doubleGesture: MagicMouseGesture = recognized == .fourFingerTap ? .fourFingerDoubleTap : (recognized == .threeFingerTap ? .threeFingerDoubleTap : .twoFingerDoubleTap)
        guard let recognized, [.twoFingerTap, .threeFingerTap, .fourFingerTap].contains(recognized),
              settings.action(for: doubleGesture) != .none else {
            if let recognized, recognized.isSwipe { pendingTapDeadline = nil }
            return recognized ?? expired
        }
        if let deadline = pendingTapDeadline, timestamp <= deadline, pendingTapGesture == recognized,
           hypot(center.x - firstTapCenter.x, center.y - firstTapCenter.y) <= 0.15 {
            pendingTapDeadline = nil
            return doubleGesture
        }
        let earlier = pendingTapDeadline != nil && settings.action(for: pendingTapGesture) != .none ? pendingTapGesture : expired
        pendingTapGesture = recognized
        firstTapCenter = center
        pendingTapDeadline = timestamp + 0.30
        return earlier
    }

}

/// A tapping finger acts while one, two or three identified anchors remain down.
/// Each tip lift rearms the next deliberate tap without requiring the anchors to
/// lift. The session stays exclusive so its final release cannot become a tap.
private struct FixedFingerRecognizer {
    let anchorCount: Int
    private var anchors: [MouseContact] = []
    private var restingSince = 0.0
    private var moving: MouseContact?
    private var movingSince = 0.0
    private var maximumMotion = 0.0
    private var peakSize = 0.0
    private var tapAllowed = true
    private var strokeRejection: TipTapRejection?
    private var finished = false
    private var strokeFinished = false
    private var recovering = false
    private var anchorLossSince: Double?
    private var missingAnchorID: Int32?
    private var completedTap = false
    private var completedTip: MouseContact?
    private var rotationAnchor: MouseContact?
    private var heldChord: [MouseContact] = []
    private var heldChordSince = 0.0
    private var heldChordHadAnchors = false
    private var heldChordMotion = 0.0
    private var heldChordPeakSizes: [Int32: Double] = [:]
    private var needsAnchorRearm = false
    private var anchorJumpSince: Double?
    static let anchorJumpTolerance = 0.05
    private var interruptedTipID: Int32?
    private var rejectedContactID: Int32?
    private(set) var rejection: TipTapRejection?
    private var lastRelease: Double?
    private var tapGesture: MagicMouseGesture = .tipTapTwoLeft
    private(set) var claimed = false
    private(set) var reservedAxes: MouseScrollAxes = []

    var liveContactRoles: [Int32: String] {
        var roles: [Int32: String] = [:]
        if heldChord.count == 3 {
            for (index, contact) in heldChord.enumerated() {
                roles[contact.id] = index == 1 ? "Resting middle" : "Outer candidate"
            }
        } else {
            for contact in anchors { roles[contact.id] = claimed ? "Resting" : "Rest candidate" }
            if let moving { roles[moving.id] = "Tapping" }
        }
        if finished { roles = roles.mapValues { _ in "Cancelled" } }
        return roles
    }

    var isResting: Bool { claimed && !finished && moving == nil }
    /// When the most recent tapping finger lifted, and when the current one landed.
    var tipReleaseTime: Double? { lastRelease }
    var tipDownSince: Double? { moving == nil ? nil : movingSince }

    func canBecomeAnchors(at timestamp: Double, settings: MagicMouseSettings) -> Bool {
        claimed && !finished && !strokeFinished && tapAllowed && moving != nil &&
            timestamp - movingSince >= settings.tipTapAnchorDuration &&
            maximumMotion <= settings.tapMovement
    }

    mutating func cancel() { finished = true; reservedAxes = [] }
    mutating func changeAppContext() {
        // Releasing the pending tip rearms recognition without requiring the
        // resting fingers to lift. Never promote this cancelled stroke either.
        if moving != nil { tapAllowed = false; strokeFinished = true }
        completedTap = false; completedTip = nil; rotationAnchor = nil
        heldChord = []; heldChordPeakSizes = [:]
        reservedAxes = []
    }
    mutating func cancelTaps() { if moving != nil { tapAllowed = false; strokeRejection = .scrolling } }
    mutating func consume(_ contacts: [MouseContact], timestamp: Double, settings: MagicMouseSettings) -> MagicMouseGesture? {
        rejection = nil
        if contacts.isEmpty { self = Self(anchorCount: anchorCount); return nil }
        let baseMovement = settings.tapMovement * (settings.tipTapSpacingGeometry == .surface ? 1.5 : 1)
        let movement = anchorCount == 1 && settings.tipTap.allowFingerMovement ? max(baseMovement, 0.10) : baseMovement
        if finished {
            _ = rearmAfterInterruption(contacts, timestamp: timestamp, settings: settings)
            return nil
        }
        if let released = consumeOuterRelease(contacts, timestamp: timestamp, settings: settings, movement: movement) {
            return released
        }
        if let rejectedContactID, !contacts.contains(where: { $0.id == rejectedContactID }) {
            self.rejectedContactID = nil
        }
        guard contacts.count <= anchorCount + 1 else {
            if claimed { rejection = .extraContact }
            cancel(); return nil
        }
        if claimed, settings.tipTapSpacingGeometry == .surface || anchorCount == 2 {
            // A light resting contact can disappear for a frame or return with
            // a new sensor ID. Keep the chord exclusive during that short gap.
            if needsAnchorRearm {
                if moving != nil { rejection = .anchorLifted }
                rearmAnchorsIfPossible(contacts, timestamp: timestamp)
                return nil
            }
            let present = anchors.allSatisfy { a in contacts.contains { $0.id == a.id } }
            if !present || anchorLossSince != nil {
                if anchorLossSince == nil {
                    anchorLossSince = timestamp
                    let missing = anchors.filter { a in !contacts.contains { $0.id == a.id } }
                    missingAnchorID = missing.count == 1 ? missing[0].id : nil
                    // A completed outer tap can return as an anchor with a new
                    // sensor ID, even if no all-three-down frame was delivered.
                    let extras = contacts.filter { c in !anchors.contains { $0.id == c.id } }
                    rotationAnchor = nil
                    if completedTap, let completedTip, extras.count == 1,
                       moving == nil || moving?.id == extras[0].id,
                       hypot(extras[0].x - completedTip.x, extras[0].y - completedTip.y) <= movement {
                        rotationAnchor = extras[0]
                    }
                }
                if let candidate = rotationAnchor,
                   !contacts.contains(where: { $0.id == candidate.id && hypot($0.x - candidate.x, $0.y - candidate.y) <= movement }) {
                    rotationAnchor = nil
                }
                if settings.tipTapSpacingGeometry == .surface,
                   transferRestingPair(contacts, timestamp: timestamp, settings: settings, movement: movement) {
                    // Continue with the new anchors; the returned finger can
                    // begin the opposite tap in this same frame.
                } else if timestamp - anchorLossSince! <= 0.06,
                   let restored = restoredAnchors(contacts, tolerance: min(movement, 0.035),
                       allowSingleReplacement: settings.tipTapSpacingGeometry == .surface && anchorCount == 1) {
                    anchors = restored; anchorLossSince = nil; rotationAnchor = nil
                } else {
                    // Lifting a resting hand after a completed tap is normal;
                    // only report an interrupted stroke as a rejection.
                    if moving != nil || settings.tipTapSpacingGeometry == .magicMouse { rejection = .anchorLifted }
                    if timestamp - anchorLossSince! > 0.06 {
                        needsAnchorRearm = true; interruptedTipID = moving?.id
                        tapAllowed = false; strokeFinished = true; reservedAxes = []
                        if settings.tipTapSpacingGeometry == .surface {
                            rearmAnchorsIfPossible(contacts, timestamp: timestamp)
                        }
                    }
                    return nil
                }
            }
        }
        if anchors.count == anchorCount {
            let present = anchors.allSatisfy { anchor in contacts.contains { $0.id == anchor.id } }
            if !present {
                if claimed { rejection = .anchorLifted; cancel(); return nil }
                anchors = []
            } else {
                let stable = anchors.allSatisfy { anchor in
                    contacts.contains { $0.id == anchor.id && hypot($0.x - anchor.x, $0.y - anchor.y) <= movement }
                }
                // A finger landing beside a resting one can merge with it for a
                // frame: the resting contact jumps toward it and swells, then
                // returns. Measured on a Magic Mouse: 0.05 sideways at 1.7× size
                // for one 30 ms frame, just as the swiping finger arrived. A real
                // shift of the resting hand does not swell, and re-settles at once.
                let merged = !stable && !recovering && anchors.contains { anchor in
                    contacts.contains { $0.id == anchor.id && hypot($0.x - anchor.x, $0.y - anchor.y) > movement &&
                        anchor.size > 0 && $0.size >= anchor.size * 1.3 }
                }
                if merged {
                    if anchorJumpSince == nil { anchorJumpSince = timestamp }
                    if timestamp - anchorJumpSince! < Self.anchorJumpTolerance { return nil }
                } else if stable { anchorJumpSince = nil }
                if recovering || !stable {
                    anchorJumpSince = nil
                    // Preserve identity and exclusivity, but allow the same
                    // fingers to settle again instead of disabling the session.
                    if claimed { rejection = .anchorsMoved }
                    if contacts.count == anchorCount {
                        anchors = contacts.sorted { $0.x < $1.x }
                        restingSince = timestamp
                        moving = nil; reservedAxes = []; recovering = false
                        completedTap = false; completedTip = nil; rotationAnchor = nil
                        lastRelease = timestamp
                    } else if claimed {
                        tapAllowed = false; reservedAxes = []; recovering = true
                    } else { anchors = [] }
                    return nil
                }
            }
        }
        if contacts.count == anchorCount && moving == nil {
            if anchors.isEmpty { anchors = contacts.sorted { $0.x < $1.x }; restingSince = timestamp }
            return nil
        }
        guard anchors.count == anchorCount else { return nil }
        if let rejectedContactID {
            guard !contacts.contains(where: { $0.id == rejectedContactID }) else { return nil }
            self.rejectedContactID = nil
        }
        if contacts.count == anchorCount + 1, let extra = contacts.first(where: { c in !anchors.contains { $0.id == c.id } }) {
            if moving == nil {
                guard timestamp - restingSince >= settings.tipTapAnchorDuration,
                      settings.tipTap.allowsSpacing(extra, anchors: anchors, geometry: settings.tipTapSpacingGeometry) else {
                    if settings.bindings.contains(where: { $0.value != .none && $0.key.fingers == anchorCount + 1 && $0.key.rawValue.hasPrefix("tip_") }) {
                        rejection = timestamp - restingSince < settings.tipTapAnchorDuration ? .notSettled : .spacing
                    }
                    if !claimed { anchors = [] }
                    else { rejectedContactID = extra.id }
                    return nil
                }
                let candidateGesture: MagicMouseGesture
                if anchorCount == 1 {
                    candidateGesture = extra.x < anchors[0].x ? .tipTapLeft : .tipTapRight
                } else if settings.tipTapSpacingGeometry == .surface &&
                            (anchorCount == 3 || settings.action(for: .tipTapTwoMiddle) == .none) {
                    // Staggered fingers need not form a horizontal row. With
                    // left/right bindings, compare against the resting group's
                    // center; a configured middle gesture keeps its own region.
                    let centerX = anchors.map(\.x).reduce(0, +) / Double(anchorCount)
                    guard abs(extra.x - centerX) >= 0.005 else { return nil }
                    if anchorCount == 2 { candidateGesture = extra.x < centerX ? .tipTapTwoLeft : .tipTapTwoRight }
                    else { candidateGesture = extra.x < centerX ? .tipTapThreeLeft : .tipTapThreeRight }
                } else if anchorCount == 3 {
                    guard extra.x < anchors.first!.x || extra.x > anchors.last!.x else { return nil }
                    candidateGesture = extra.x < anchors.first!.x ? .tipTapThreeLeft : .tipTapThreeRight
                } else {
                    candidateGesture = extra.x < anchors[0].x ? .tipTapTwoLeft : (extra.x > anchors[1].x ? .tipTapTwoRight : .tipTapTwoMiddle)
                }
                // Opposite-side strokes are distinct intentional taps, not
                // same-side contact bounce. Keep normal debounce otherwise.
                let oppositeSide = (candidateGesture == .tipTapLeft && tapGesture == .tipTapRight) ||
                    (candidateGesture == .tipTapRight && tapGesture == .tipTapLeft) ||
                    (candidateGesture == .tipTapTwoLeft && tapGesture == .tipTapTwoRight) ||
                    (candidateGesture == .tipTapTwoRight && tapGesture == .tipTapTwoLeft) ||
                    (candidateGesture == .tipTapThreeLeft && tapGesture == .tipTapThreeRight) ||
                    (candidateGesture == .tipTapThreeRight && tapGesture == .tipTapThreeLeft)
                // A returned outer finger can immediately become the resting
                // finger for the opposite release. In paired trackpad mode,
                // qualify the complete contact duration at release instead of
                // rejecting that whole stroke for a quick landing.
                let pairedRelease = anchorCount == 2 && settings.tipTapSpacingGeometry == .surface &&
                    settings.action(for: .tipTapTwoLeft) != .none && settings.action(for: .tipTapTwoRight) != .none
                let debounce = pairedRelease ? 0 : (settings.tipTapSpacingGeometry == .surface && oppositeSide ? 0.008 : 0.03)
                guard lastRelease.map({ timestamp - $0 >= debounce }) ?? true else {
                    rejection = .debounce
                    rejectedContactID = extra.id
                    return nil
                }
                guard settings.action(for: candidateGesture) != .none ||
                      (candidateGesture == .tipTapTwoLeft && [.tipSwipeLeftUp, .tipSwipeLeftDown, .tipSwipeLeftLeft, .tipSwipeLeftRight].contains { settings.action(for: $0) != .none }) else { return nil }
                tapGesture = candidateGesture
                if tapGesture == .tipTapTwoLeft {
                    if [.tipSwipeLeftUp, .tipSwipeLeftDown].contains(where: { settings.action(for: $0) != .none }) { reservedAxes.insert(.vertical) }
                    if [.tipSwipeLeftLeft, .tipSwipeLeftRight].contains(where: { settings.action(for: $0) != .none }) { reservedAxes.insert(.horizontal) }
                }
                guard settings.action(for: tapGesture) != .none || !reservedAxes.isEmpty else { return nil }
                moving = extra; movingSince = timestamp; claimed = true; peakSize = extra.size
                maximumMotion = 0; tapAllowed = true; strokeFinished = false; strokeRejection = nil
            }
            guard let origin = moving, extra.id == origin.id else { rejection = .tipChanged; cancel(); return nil }
            guard !strokeFinished else { return nil }
            if !settings.tipTap.allowsSpacing(extra, anchors: anchors, geometry: settings.tipTapSpacingGeometry) { tapAllowed = false; strokeRejection = .spacing }
            peakSize = max(peakSize, extra.size)
            let dx = extra.x - origin.x, dy = extra.y - origin.y
            maximumMotion = max(maximumMotion, hypot(dx, dy))
            if !reservedAxes.isEmpty, timestamp - movingSince >= settings.tipTapMinimumDuration, timestamp - movingSince <= 1,
               peakSize >= settings.tipTap.requiredSize(anchors: anchorCount) {
                let gesture: MagicMouseGesture?
                if abs(dy) >= settings.swipeDistance, abs(dy) > abs(dx) * MagicMouseSettings.swipeAxisDominance { gesture = dy > 0 ? .tipSwipeLeftUp : .tipSwipeLeftDown }
                else if abs(dx) >= settings.swipeDistance, abs(dx) > abs(dy) * MagicMouseSettings.swipeAxisDominance { gesture = dx > 0 ? .tipSwipeLeftRight : .tipSwipeLeftLeft }
                else { gesture = nil }
                if let gesture, settings.action(for: gesture) != .none { strokeFinished = true; return gesture }
            }
            return nil
        }
        if claimed, moving != nil, contacts.count == anchorCount {
            defer {
                moving = nil; reservedAxes = []; lastRelease = timestamp
                anchors = contacts.sorted { $0.x < $1.x }
            }
            let duration = timestamp - movingSince
            guard !strokeFinished, settings.action(for: tapGesture) != .none else { return nil }
            if !tapAllowed { rejection = strokeRejection }
            else if maximumMotion > movement { rejection = .moved }
            else if peakSize < settings.tipTap.requiredSize(anchors: anchorCount) { rejection = .light }
            else if duration < settings.tipTapMinimumDuration { rejection = .short }
            else if duration > max(settings.tapDuration, settings.tipTapMinimumDuration + 0.12) { rejection = .long }
            if tapAllowed && rejection == nil { completedTap = true; completedTip = moving; return tapGesture }
            completedTap = false; completedTip = nil; rotationAnchor = nil
            return nil
        }
        if claimed { rejection = .anchorLifted; cancel() } else { anchors = [] }
        return nil
    }
    /// Paired trackpad Left/Right bindings support a resting three-finger hand.
    /// Classify the actual outer finger that lifts, rather than treating a lift
    /// on the other side only as preparation for one more tap. A held chord has
    /// no tap timeout: its fingers are resting until one deliberately releases.
    private mutating func consumeOuterRelease(_ contacts: [MouseContact], timestamp: Double,
                                              settings: MagicMouseSettings, movement: Double) -> MagicMouseGesture? {
        guard anchorCount == 2, settings.tipTapSpacingGeometry == .surface,
              settings.action(for: .tipTapTwoLeft) != .none,
              settings.action(for: .tipTapTwoRight) != .none else { return nil }
        if contacts.count == 3 {
            if Set(heldChord.map(\.id)) != Set(contacts.map(\.id)) {
                heldChord = contacts.sorted { $0.x < $1.x }; heldChordSince = timestamp
                heldChordHadAnchors = anchors.count == 2 && timestamp - restingSince >= settings.tipTapAnchorDuration &&
                    anchors.allSatisfy { a in contacts.contains { $0.id == a.id } }
                heldChordMotion = 0; heldChordPeakSizes = [:]
            }
            for contact in contacts {
                if let origin = heldChord.first(where: { $0.id == contact.id }) {
                    heldChordMotion = max(heldChordMotion, hypot(contact.x - origin.x, contact.y - origin.y))
                }
                heldChordPeakSizes[contact.id] = max(heldChordPeakSizes[contact.id] ?? 0, contact.size)
            }
            return nil
        }
        let chord = heldChord, peaks = heldChordPeakSizes
        let duration = timestamp - heldChordSince
        let minimum = heldChordHadAnchors ? settings.tipTapMinimumDuration : max(settings.tipTapAnchorDuration, settings.tipTapMinimumDuration)
        let motion = heldChordMotion
        heldChord = []; heldChordPeakSizes = [:]
        guard chord.count == 3, contacts.count == 2,
              duration >= minimum, motion <= movement,
              !recovering, !needsAnchorRearm, !strokeFinished, tapAllowed, reservedAxes.isEmpty, rejectedContactID == nil,
              contacts.allSatisfy({ c in chord.contains { $0.id == c.id && hypot($0.x - c.x, $0.y - c.y) <= movement } }) else { return nil }
        let released = chord.filter { a in !contacts.contains { $0.id == a.id } }
        guard released.count == 1, let tip = released.first,
              tip.id == chord.first?.id || tip.id == chord.last?.id,
              (peaks[tip.id] ?? 0) >= settings.tipTap.requiredSize(anchors: 2),
              settings.tipTap.allowsSpacing(tip, anchors: contacts, geometry: .surface) else { return nil }
        let gesture: MagicMouseGesture = tip.id == chord.first?.id ? .tipTapTwoLeft : .tipTapTwoRight
        // All state for the next tap starts with the two fingers actually down.
        // Neither a long preceding hold nor the old tapping side carries over.
        self = Self(anchorCount: anchorCount)
        anchors = contacts.sorted { $0.x < $1.x }
        restingSince = timestamp - settings.tipTapAnchorDuration - 0.000001
        lastRelease = timestamp; claimed = true; tapGesture = gesture
        completedTap = true; completedTip = tip
        return gesture
    }

    /// Recover after extra contacts lift. Button recovery can accept a rotated
    /// pair when its stationary middle contact survives; the replacement outer
    /// finger must lie across that middle from the old outer finger and settle.
    /// Recovery never emits an interrupted tap or bypasses a held button.
    mutating func rearmAfterInterruption(_ contacts: [MouseContact], timestamp: Double,
                                         settings: MagicMouseSettings, allowRotatedPair: Bool = false) -> Bool {
        guard finished, claimed, settings.tipTapSpacingGeometry == .surface,
              anchors.count == anchorCount, contacts.count == anchorCount else { return false }
        let sameAnchors = Set(contacts.map(\.id)) == Set(anchors.map(\.id))
        let baseMovement = settings.tapMovement * 1.5
        let movement = anchorCount == 1 && settings.tipTap.allowFingerMovement ? max(baseMovement, 0.10) : baseMovement
        if !sameAnchors {
            guard allowRotatedPair, anchorCount == 2,
                  settings.action(for: .tipTapTwoLeft) != .none, settings.action(for: .tipTapTwoRight) != .none else { return false }
            let shared = anchors.filter { a in contacts.contains { $0.id == a.id } }
            guard shared.count == 1, let middle = shared.first,
                  let currentMiddle = contacts.first(where: { $0.id == middle.id }),
                  hypot(currentMiddle.x - middle.x, currentMiddle.y - middle.y) <= movement,
                  let oldOuter = anchors.first(where: { $0.id != middle.id }),
                  let newOuter = contacts.first(where: { $0.id != middle.id }),
                  (oldOuter.x - middle.x) * (newOuter.x - currentMiddle.x) < 0,
                  settings.tipTap.allowsSpacing(newOuter, anchors: anchors, geometry: .surface) else { return false }
        }
        let stable = sameAnchors && anchors.allSatisfy { anchor in
            contacts.contains { $0.id == anchor.id && hypot($0.x - anchor.x, $0.y - anchor.y) <= movement }
        }
        let settledSince = stable ? restingSince : timestamp
        let previousGesture = tapGesture
        self = Self(anchorCount: anchorCount)
        anchors = contacts.sorted { $0.x < $1.x }; restingSince = settledSince
        claimed = true; lastRelease = timestamp; tapGesture = previousGesture
        return true
    }

    /// A successful outer tap supplies the returning finger's location. Keep
    /// the middle contact fixed while outer fingers exchange roles, including
    /// disjoint sensor frames and fresh IDs after lift. A handoff never fires.
    private mutating func transferRestingPair(_ contacts: [MouseContact], timestamp: Double,
                                              settings: MagicMouseSettings, movement: Double) -> Bool {
        guard anchorCount == 2, completedTap, !recovering, !strokeFinished, tapAllowed,
              tapGesture == .tipTapTwoLeft || tapGesture == .tipTapTwoRight,
              let loss = anchorLossSince,
              let missingID = missingAnchorID,
              let missing = anchors.first(where: { $0.id == missingID }),
              let candidate = rotationAnchor,
              maximumMotion <= movement,
              let heldTip = contacts.first(where: { $0.id == candidate.id }),
              hypot(heldTip.x - candidate.x, heldTip.y - candidate.y) <= movement else { return false }
        // Once the previously tapped outer finger has been held steadily long
        // enough, it is ready to rest. Do not swallow the opposite finger's
        // deliberate quick lift as sensor dropout and keep timing the held tip.
        // A newly arriving replacement still uses the normal dropout grace.
        let settledReplacement = moving?.id == candidate.id &&
            timestamp - movingSince >= settings.tipTapMinimumDuration
        guard settledReplacement || timestamp - loss > 0.06 else { return false }
        let remaining = anchors.filter { $0.id != missingID }
        guard remaining.count == 1,
              remaining.allSatisfy({ anchor in contacts.contains { $0.id == anchor.id && hypot($0.x - anchor.x, $0.y - anchor.y) <= movement } }),
              tapGesture == .tipTapTwoLeft ? missing.x > remaining[0].x : missing.x < remaining[0].x else { return false }
        let pair = contacts.filter { $0.id == remaining[0].id || $0.id == heldTip.id }
        guard pair.count == 2 else { return false }
        // If the opposite finger has already landed, accept a changed ID only
        // near its old location. The ordinary stroke checks then validate it.
        let returned = contacts.filter { c in !pair.contains { $0.id == c.id } }
        guard returned.count <= 1,
              returned.allSatisfy({ hypot($0.x - missing.x, $0.y - missing.y) <= movement }) else { return false }
        anchors = pair.sorted { $0.x < $1.x }
        restingSince = timestamp - settings.tipTapAnchorDuration - 0.000001
        moving = nil; reservedAxes = []; strokeFinished = false
        anchorLossSince = nil; missingAnchorID = nil; completedTap = false
        completedTip = nil; rotationAnchor = nil
        return true
    }

    private mutating func rearmAnchorsIfPossible(_ contacts: [MouseContact], timestamp: Double) {
        guard interruptedTipID.map({ id in !contacts.contains { $0.id == id } }) ?? true,
              contacts.count == anchorCount else { return }
        anchors = contacts.sorted { $0.x < $1.x }
        restingSince = timestamp; lastRelease = timestamp
        moving = nil; reservedAxes = []; recovering = false
        needsAnchorRearm = false; interruptedTipID = nil; anchorLossSince = nil
        completedTap = false; completedTip = nil; rotationAnchor = nil
    }

    private func restoredAnchors(_ contacts: [MouseContact], tolerance: Double,
                                 allowSingleReplacement: Bool) -> [MouseContact]? {
        let retained = anchors.filter { a in contacts.contains { $0.id == a.id } }
        // With one anchor, its independently tracked tapping finger must still
        // be present before a new anchor ID can inherit a pending stroke.
        let trackedTipPresent = moving.map { tip in contacts.contains { $0.id == tip.id } } ?? false
        guard !retained.isEmpty || (allowSingleReplacement && trackedTipPresent) else { return nil }
        var used = Set(retained.map(\.id))
        var restored: [MouseContact] = []
        for anchor in anchors {
            if contacts.contains(where: { $0.id == anchor.id }) { restored.append(anchor); continue }
            let nearby = contacts.filter {
                !used.contains($0.id) && $0.id != moving?.id &&
                hypot($0.x - anchor.x, $0.y - anchor.y) <= tolerance
            }
            // Ambiguous or distant replacements never inherit a pending stroke.
            guard nearby.count == 1 else { return nil }
            used.insert(nearby[0].id)
            restored.append(MouseContact(id: nearby[0].id, x: anchor.x, y: anchor.y, size: anchor.size))
        }
        return restored
    }
}

/// Bounded path history, evaluated on lift. When a circle and single-finger swipe
/// are both assigned, the path chooses one action after lift rather than firing
/// a swipe halfway around the circle. No timer or pointer interception is needed.
private struct CirclePathRecognizer {
    private var points: [MouseContact] = []
    private var started = 0.0
    private var invalid = false
    mutating func cancel() { invalid = true }
    mutating func consume(_ contacts: [MouseContact], timestamp: Double, settings: MagicMouseSettings) -> MagicMouseGesture? {
        if contacts.isEmpty {
            defer { self = Self() }
            guard !invalid, let first = points.first, let last = points.last, timestamp - started <= 3 else { return nil }
            let travel = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            let dx = last.x - first.x, dy = last.y - first.y
            let straight = hypot(dx, dy)
            if straight >= settings.swipeDistance, travel <= straight * 1.2 {
                let gesture: MagicMouseGesture?
                if abs(dx) > abs(dy) * MagicMouseSettings.swipeAxisDominance { gesture = dx > 0 ? .oneFingerSwipeRight : .oneFingerSwipeLeft }
                else if abs(dy) > abs(dx) * MagicMouseSettings.swipeAxisDominance { gesture = dy > 0 ? .oneFingerSwipeUp : .oneFingerSwipeDown }
                else { gesture = nil }
                return gesture.flatMap { settings.action(for: $0) != .none ? $0 : nil }
            }
            guard points.count >= 12 else { return nil }
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            let width = maxX - minX, height = maxY - minY
            guard min(width, height) >= 0.10, max(width, height) / min(width, height) <= 2.2,
                  straight <= min(width, height) * 0.35 else { return nil }
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            var signed = 0.0, total = 0.0
            for (a, b) in zip(points, points.dropFirst()) {
                let ax = (a.x - cx) / width, ay = (a.y - cy) / height
                let bx = (b.x - cx) / width, by = (b.y - cy) / height
                guard hypot(ax, ay) >= 0.2, hypot(bx, by) >= 0.2 else { return nil }
                let turn = atan2(ax * by - ay * bx, ax * bx + ay * by)
                guard abs(turn) <= .pi / 2 else { return nil }
                signed += turn; total += abs(turn)
            }
            guard abs(signed) >= .pi * 1.7, total <= abs(signed) * 1.15 else { return nil }
            let gesture: MagicMouseGesture = signed < 0 ? .circleClockwise : .circleCounterClockwise
            return settings.action(for: gesture) != .none ? gesture : nil
        }
        guard !invalid, contacts.count == 1 else { invalid = true; return nil }
        let point = contacts[0]
        if points.isEmpty { points = [point]; started = timestamp; return nil }
        guard point.id == points[0].id, timestamp - started <= 3 else { invalid = true; return nil }
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 0.003 {
            if points.count >= 256 { points = points.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil } }
            points.append(point)
        }
        return nil
    }
}
