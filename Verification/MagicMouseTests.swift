import Foundation

@main
struct MagicMouseTests {
    static var checks = 0
    static func expect(_ truth: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard truth() else { fatalError(message) }
    }
    static func points(_ n: Int, x: Double = 0.2, y: Double = 0.4) -> [MouseContact] {
        (0..<n).map { MouseContact(id: Int32($0), x: x + Double($0) * 0.15, y: y) }
    }
    static func main() {
        var settings = MagicMouseSettings()
        for (n, expected) in [(1, MagicMouseGesture.leftTap), (2, .twoFingerTap), (3, .threeFingerTap)] {
            var r = MagicMouseRecognizer()
            expect(r.consume(points(n), timestamp: 1, settings: settings) == nil, "No action on landing")
            expect(r.consume([], timestamp: 1.12, settings: settings) == expected, "Tap \(n)")
            expect(r.consume([], timestamp: 1.15, settings: settings) == nil, "No repeated tap")
        }
        var r = MagicMouseRecognizer()
        _ = r.consume(points(1, x: 0.8), timestamp: 1, settings: settings)
        expect(r.consume([], timestamp: 1.15, settings: settings) == .rightTap, "Right tap")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume(points(1), timestamp: 1.1, settings: settings)
        expect(r.consume([], timestamp: 1.15, settings: settings) == .twoFingerTap, "Staggered lift preserves peak count")
        r.reset()
        _ = r.consume(points(1), timestamp: 1, settings: settings)
        _ = r.consume(points(2), timestamp: 1.16, settings: settings)
        expect(r.consume([], timestamp: 1.2, settings: settings) == nil, "Adding a finger to a rest is not a tap")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume(points(2, x: 0.35), timestamp: 1.1, settings: settings)
        _ = r.consume(points(2), timestamp: 1.15, settings: settings)
        expect(r.consume([], timestamp: 1.2, settings: settings) == nil, "Out-and-back movement is not a tap")
        for cancelKind in 0..<3 {
            r.reset()
            _ = r.consume(points(2), timestamp: 1, settings: settings)
            if cancelKind == 0 { r.cancel() }
            if cancelKind == 1 { r.cancelTap() }
            if cancelKind == 2 { _ = r.consume(points(2), timestamp: 1.1, settings: settings, physicalButtonDown: true) }
            expect(r.consume([], timestamp: 1.2, settings: settings) == nil, "Click/scroll/cancel suppresses tap")
        }
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        expect(r.consume([], timestamp: 2, settings: settings) == nil, "Rest is not a tap")
        r.reset()
        _ = r.consume(points(2), timestamp: 2, settings: settings)
        expect(r.consume([], timestamp: 1, settings: settings) == nil, "Timestamp rollback is not a tap")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume([MouseContact(id: 9, x: .nan, y: 0)], timestamp: 1.1, settings: settings)
        expect(r.consume([], timestamp: 1.2, settings: settings) == nil, "Malformed frame cancels session")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        expect(r.consume(points(2, x: 0.5), timestamp: 1.2, settings: settings) == nil, "Swipes disabled by default")
        let swipes: [(MagicMouseGesture, Double, Double)] = [(.swipeRight, 0.25, 0), (.swipeLeft, -0.25, 0), (.swipeUp, 0, 0.25), (.swipeDown, 0, -0.25)]
        for (gesture, dx, dy) in swipes {
            r.reset(); settings.bindings[gesture] = .snapLeft
            _ = r.consume(points(2, x: 0.4, y: 0.5), timestamp: 1, settings: settings)
            expect(r.consume(points(2, x: 0.4 + dx, y: 0.5 + dy), timestamp: 1.2, settings: settings) == gesture, "Directional swipe \(gesture)")
            expect(r.consume(points(2, x: 0.4 + dx, y: 0.5 + dy), timestamp: 1.3, settings: settings) == nil, "Swipe fires once")
            expect(r.consume([], timestamp: 1.4, settings: settings) == nil, "Swipe cannot also tap")
        }
        var holdCheck = MagicMouseSettings(); holdCheck.bindings = [.oneFingerSwipeLeft: .snapLeft]
        expect(!holdCheck.holdsMultiFingerScroll, "One-finger bindings leave two-finger scrolling alone")
        holdCheck.bindings[.tipSwipeLeftUp] = .missionControl
        expect(holdCheck.holdsMultiFingerScroll, "A Tip swipe binding withholds scrolling under two or more fingers")
        holdCheck.enabled = false
        expect(!holdCheck.holdsMultiFingerScroll, "Disabled input withholds nothing")
        // Recorded thumb-arc swipe: up and to the right at 55° (ratio 1.42).
        r.reset()
        _ = r.consume(points(2, x: 0.4, y: 0.45), timestamp: 1, settings: settings)
        expect(r.consume(points(2, x: 0.54, y: 0.65), timestamp: 1.12, settings: settings) == .swipeUp, "Diagonal thumb-arc swipe still reads as up")
        r.reset()
        _ = r.consume(points(2, x: 0.4, y: 0.45), timestamp: 1, settings: settings)
        expect(r.consume(points(2, x: 0.58, y: 0.65), timestamp: 1.12, settings: settings) == nil, "A 48° swipe is too ambiguous to fire")
        r.reset()
        _ = r.consume(points(2, x: 0.4), timestamp: 1, settings: settings)
        expect(r.consume([MouseContact(id: 0, x: 0.15, y: 0.4), MouseContact(id: 1, x: 0.8, y: 0.4)], timestamp: 1.2, settings: settings) == nil, "Pinch cannot swipe")
        r.reset()
        _ = r.consume(points(1), timestamp: 1, settings: settings)
        expect(r.consume(points(1, x: 0.6), timestamp: 1.2, settings: settings) == nil, "One-finger scrolling cannot swipe")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        settings.enabled = false
        expect(r.consume([], timestamp: 1.1, settings: settings) == nil, "Disabling cancels active gesture")
        settings.tapDuration = .nan; settings.tapMovement = .infinity; settings.swipeDistance = -9
        let normalized = MagicMouseSettings.normalized(settings)
        expect(normalized.tapDuration == 0.25 && normalized.tapMovement == 0.035 && normalized.swipeDistance == 0.1, "Invalid config values normalize")
        // Separate recognizers cannot combine fingers from different devices.
        var other = MagicMouseRecognizer(); r.reset(); settings = MagicMouseSettings()
        _ = r.consume(points(1), timestamp: 1, settings: settings)
        _ = other.consume(points(1, x: 0.8), timestamp: 1, settings: settings)
        expect(r.consume([], timestamp: 1.1, settings: settings) == .leftTap, "First device independent")
        expect(other.consume([], timestamp: 1.1, settings: settings) == .rightTap, "Second device independent")
        // Single-finger swipes are opt-in and never borrow a two-finger binding.
        for (gesture, dx, dy) in [(MagicMouseGesture.oneFingerSwipeRight, 0.25, 0.0), (.oneFingerSwipeLeft, -0.25, 0.0), (.oneFingerSwipeUp, 0.0, 0.25), (.oneFingerSwipeDown, 0.0, -0.25)] {
            r.reset(); settings = MagicMouseSettings(); settings.bindings[gesture] = .showDesktop
            _ = r.consume(points(1, x: 0.4, y: 0.5), timestamp: 1, settings: settings)
            expect(r.consume(points(1, x: 0.4 + dx, y: 0.5 + dy), timestamp: 1.2, settings: settings) == gesture, "Single-finger swipe direction")
            expect(r.consume(points(1, x: 0.4 + dx, y: 0.5 + dy), timestamp: 1.3, settings: settings) == nil, "Single swipe fires once")
            expect(r.consume([], timestamp: 1.4, settings: settings) == nil, "Single swipe cannot also tap")
        }
        r.reset(); settings.bindings[.oneFingerSwipeRight] = .showDesktop
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume(points(1), timestamp: 1.1, settings: settings)
        expect(r.consume(points(1, x: 0.6), timestamp: 1.2, settings: settings) == nil, "Partial lift cannot turn two fingers into a single swipe")
        _ = r.consume([], timestamp: 1.3, settings: settings)
        _ = r.consume(points(1), timestamp: 2, settings: settings)
        expect(r.consume(points(1, x: 0.6), timestamp: 2.2, settings: settings) == .oneFingerSwipeRight, "All fingers lifted rearms single swipe")
        settings = MagicMouseSettings()
        settings.bindings[.twoFingerDoubleTap] = .showDesktop
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        expect(r.consume([], timestamp: 1.1, settings: settings) == nil, "Single tap waits when double-tap is assigned")
        expect(r.flushPendingTap(at: 1.2) == nil, "Single tap cannot fire before double-tap deadline")
        _ = r.consume(points(2), timestamp: 1.22, settings: settings)
        expect(r.consume([], timestamp: 1.32, settings: settings) == .twoFingerDoubleTap, "Two taps become one double-tap")
        expect(r.flushPendingTap(at: 2) == nil, "Double-tap consumes pending single tap")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume([], timestamp: 1.1, settings: settings)
        expect(r.flushPendingTap(at: 1.41) == .twoFingerTap, "Unmatched tap fires after deadline")
        expect(r.flushPendingTap(at: 2) == nil, "Deadline fires once")
        r.reset()
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        _ = r.consume([], timestamp: 1.1, settings: settings)
        r.cancel()
        expect(r.flushPendingTap(at: 2) == nil, "Cancellation clears delayed tap")
        for (x, expected) in [(0.2, MagicMouseGesture.tipTapLeft), (0.8, .tipTapRight)] {
            r.reset(); settings.bindings[expected] = .showDesktop
            let anchor = MouseContact(id: 10, x: 0.5, y: 0.5)
            let tapping = MouseContact(id: 20, x: x, y: 0.5)
            _ = r.consume([anchor], timestamp: 1, settings: settings)
            _ = r.consume([anchor, tapping], timestamp: 1.3, settings: settings)
            expect(r.consume([anchor], timestamp: 1.4, settings: settings) == expected, "TipTap side follows tapping finger relative to fixed finger")
            expect(r.consume([], timestamp: 1.45, settings: settings) == nil, "TipTap cannot also tap on final lift")
        }
        r.reset()
        let anchor = MouseContact(id: 10, x: 0.5, y: 0.5)
        _ = r.consume([anchor], timestamp: 1, settings: settings)
        _ = r.consume([anchor, MouseContact(id: 20, x: 0.2, y: 0.5)], timestamp: 1.2, settings: settings)
        expect(r.consume([], timestamp: 1.3, settings: settings) == nil, "TipTap requires fixed finger to remain down")
        r.reset(); settings.bindings[.twoFingerClick] = .showDesktop
        _ = r.consume(points(2), timestamp: 1, settings: settings)
        expect(r.physicalClick(timestamp: 1.1) == .twoFingerClick, "Confirmed physical click uses two contacts")
        expect(r.consume([], timestamp: 1.2, settings: settings) == nil, "Physical click cancels tap")
        r.reset()
        _ = r.consume(points(1), timestamp: 1, settings: settings)
        expect(r.physicalClick(timestamp: 1.1) == nil, "One contact cannot trigger two-finger click")
        // TipTap should require deliberate anchor rest and reject contact bounce.
        let fixedFinger = MouseContact(id: 10, x: 0.5, y: 0.5)
        let tipFinger = MouseContact(id: 20, x: 0.2, y: 0.5)
        settings = MagicMouseSettings(); settings.bindings[.tipTapLeft] = .showDesktop
        r.reset()
        _ = r.consume([fixedFinger], timestamp: 20, settings: settings)
        _ = r.consume([fixedFinger, tipFinger], timestamp: 20.15, settings: settings)
        expect(r.consume([fixedFinger], timestamp: 20.25, settings: settings) == nil, "TipTap does not arm before fixed finger settles")
        r.reset()
        _ = r.consume([fixedFinger], timestamp: 30, settings: settings)
        _ = r.consume([fixedFinger, tipFinger], timestamp: 30.3, settings: settings)
        expect(r.consume([fixedFinger], timestamp: 30.34, settings: settings) == nil, "TipTap rejects a 40 ms brush")
        r.reset(); settings.tipTapMinimumDuration = 0.16
        _ = r.consume([fixedFinger], timestamp: 40, settings: settings)
        _ = r.consume([fixedFinger, tipFinger], timestamp: 40.3, settings: settings)
        expect(r.consume([fixedFinger], timestamp: 40.4, settings: settings) == nil, "Configured longer minimum prevents an early TipTap")
        r.reset()
        _ = r.consume([fixedFinger], timestamp: 50, settings: settings)
        _ = r.consume([fixedFinger, tipFinger], timestamp: 50.3, settings: settings)
        expect(r.consume([fixedFinger], timestamp: 50.5, settings: settings) == .tipTapLeft, "A deliberate TipTap still fires on lift")
        // Three-finger tap arbitration, physical click, and coherent swipes.
        settings = MagicMouseSettings()
        settings.bindings[.threeFingerDoubleTap] = .showDesktop
        r.reset()
        _ = r.consume(points(3), timestamp: 100, settings: settings)
        expect(r.consume([], timestamp: 100.1, settings: settings) == nil, "Three-finger single tap waits for a possible double")
        _ = r.consume(points(3), timestamp: 100.2, settings: settings)
        expect(r.consume([], timestamp: 100.3, settings: settings) == .threeFingerDoubleTap, "Three-finger double tap fires exactly once")
        expect(r.flushPendingTap(at: 101) == nil, "Three-finger double consumes the single")
        r.reset()
        _ = r.consume(points(3), timestamp: 110, settings: settings)
        _ = r.consume([], timestamp: 110.1, settings: settings)
        expect(r.flushPendingTap(at: 110.5) == .threeFingerTap, "Three-finger single survives timeout")
        settings.bindings[.twoFingerDoubleTap] = .showDesktop
        r.reset()
        _ = r.consume(points(2), timestamp: 120, settings: settings)
        _ = r.consume([], timestamp: 120.1, settings: settings)
        _ = r.consume(points(3), timestamp: 120.2, settings: settings)
        expect(r.consume([], timestamp: 120.3, settings: settings) == .twoFingerTap, "Different finger counts cannot form a double tap")
        expect(r.flushPendingTap(at: 121) == .threeFingerTap, "Mixed finger counts retain both singles")
        settings.bindings[.threeFingerClick] = .middleClick
        r.reset()
        _ = r.consume(points(3), timestamp: 130, settings: settings)
        expect(r.physicalClick(timestamp: 130.05) == .threeFingerClick, "Three-finger physical click routes correctly")
        expect(r.physicalClick(timestamp: 130.06) == nil, "Physical click cannot repeat before release")
        expect(r.consume([], timestamp: 130.1, settings: settings) == nil, "Physical click cannot also trigger a tap")
        for (dx, dy, gesture) in [(0.25, 0.0, MagicMouseGesture.threeFingerSwipeRight), (-0.25, 0.0, .threeFingerSwipeLeft), (0.0, 0.25, .threeFingerSwipeUp), (0.0, -0.25, .threeFingerSwipeDown)] {
            settings.bindings[gesture] = .showDesktop
            let start = [MouseContact(id: 1, x: 0.35, y: 0.5), MouseContact(id: 2, x: 0.5, y: 0.5), MouseContact(id: 3, x: 0.65, y: 0.5)]
            let end = start.map { MouseContact(id: $0.id, x: $0.x + dx, y: $0.y + dy) }
            r.reset()
            _ = r.consume(start, timestamp: 140, settings: settings)
            expect(r.consume(end.reversed(), timestamp: 140.2, settings: settings) == gesture, "Three-finger swipe follows the whole hand, independent of frame order")
            expect(r.consume(end, timestamp: 140.3, settings: settings) == nil, "Three-finger swipe fires once")
            expect(r.consume([], timestamp: 140.4, settings: settings) == nil, "Swipe release cannot also tap")
        }
        let anchors = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.7, y: 0.5)]
        for (x, gesture) in [(0.2, MagicMouseGesture.tipTapTwoLeft), (0.55, .tipTapTwoMiddle), (0.9, .tipTapTwoRight)] {
            settings = MagicMouseSettings(); settings.bindings[gesture] = .showDesktop
            let third = MouseContact(id: 3, x: x, y: 0.5)
            r.reset()
            _ = r.consume(anchors, timestamp: 150, settings: settings)
            _ = r.consume([third] + anchors.reversed(), timestamp: 150.3, settings: settings)
            expect(r.ownsFixedFingerSession, "Two fixed fingers claim only a configured gesture")
            expect(r.consume(anchors.reversed(), timestamp: 150.4, settings: settings) == gesture, "TipTap recognizes left, middle and right by position, not contact order")
            _ = r.consume(anchors + [third], timestamp: 150.6, settings: settings)
            expect(r.consume(anchors, timestamp: 150.7, settings: settings) == gesture, "Fixed-finger gesture repeats while its anchors remain down")
            expect(r.consume([], timestamp: 150.8, settings: settings) == nil, "Final anchor release never becomes a tap")
            r.reset()
            _ = r.consume(anchors, timestamp: 160, settings: settings)
            _ = r.consume(anchors + [third], timestamp: 160.1, settings: settings)
            expect(r.consume(anchors, timestamp: 160.2, settings: settings) == nil, "Two anchors need the configured rest time")
            r.reset()
            _ = r.consume(anchors, timestamp: 170, settings: settings)
            _ = r.consume(anchors + [third], timestamp: 170.3, settings: settings)
            expect(r.consume(anchors, timestamp: 170.33, settings: settings) == nil, "Two-anchor TipTap rejects quick brushes")
            r.reset()
            _ = r.consume(anchors, timestamp: 180, settings: settings)
            _ = r.consume(anchors + [third], timestamp: 180.3, settings: settings)
            expect(r.consume([anchors[0]], timestamp: 180.4, settings: settings) == nil, "Both anchors must remain down")
        }
        for (dy, gesture) in [(0.25, MagicMouseGesture.tipSwipeLeftUp), (-0.25, .tipSwipeLeftDown)] {
            settings = MagicMouseSettings(); settings.bindings[gesture] = .showDesktop
            settings.bindings[.tipTapTwoLeft] = .middleClick
            let third = MouseContact(id: 3, x: 0.2, y: 0.5)
            let moved = MouseContact(id: 3, x: 0.2, y: 0.5 + dy)
            r.reset()
            _ = r.consume(anchors, timestamp: 190, settings: settings)
            _ = r.consume(anchors + [third], timestamp: 190.3, settings: settings)
            expect(r.reservesTipSwipe, "TipSwipe reserves vertical motion with two fixed fingers")
            r.cancelTap() // Native scrolling must cancel taps without cancelling a TipSwipe.
            expect(r.consume(anchors + [moved], timestamp: 190.5, settings: settings) == gesture, "Only the left finger moves for TipSwipe")
            expect(r.consume(anchors, timestamp: 190.6, settings: settings) == nil, "TipSwipe cannot also TipTap")
            expect(r.consume([], timestamp: 190.7, settings: settings) == nil, "TipSwipe rearms only after full release")
            r.reset()
            _ = r.consume(anchors, timestamp: 200, settings: settings)
            _ = r.consume(anchors + [third], timestamp: 200.3, settings: settings)
            let shiftedAnchor = MouseContact(id: 1, x: 0.5, y: 0.6)
            expect(r.consume([shiftedAnchor, anchors[1], moved], timestamp: 200.5, settings: settings) == nil, "Moving an anchor cancels TipSwipe")
            expect(r.ownsFixedFingerSession, "A cancelled fixed-finger session cannot become a whole-hand swipe")
            r.cancel()
            expect(r.consume(anchors + [moved], timestamp: 200.6, settings: settings) == nil, "Context cancellation blocks held TipSwipe")
        }
        settings = MagicMouseSettings()
        settings.bindings = [.oneFingerMiddleClick: .middleClick, .fourFingerClick: .showDesktop]
        for x in [0.2, 0.39, 0.4, 0.5, 0.6, 0.61, 0.8] {
            r.reset()
            _ = r.consume(points(1, x: x), timestamp: 210, settings: settings)
            let expected: MagicMouseGesture? = (0.4...0.6).contains(x) ? .oneFingerMiddleClick : nil
            expect(r.physicalClick(timestamp: 210.05) == expected, "Middle Click requires one contact in the centre")
            expect(r.consume([], timestamp: 210.1, settings: settings) == nil, "A physical press cannot also tap")
        }
        r.reset()
        _ = r.consume(points(4), timestamp: 220, settings: settings)
        expect(r.physicalClick(timestamp: 220.05) == .fourFingerClick, "Four contacts and a physical press trigger Four Finger Click")
        expect(r.physicalClick(timestamp: 220.06) == nil, "Four-finger click fires once per touch session")
        expect(r.consume([], timestamp: 220.1, settings: settings) == nil, "Four-finger click release cannot tap")
        r.reset()
        _ = r.consume(points(4), timestamp: 221, settings: settings)
        expect(r.consume([], timestamp: 221.1, settings: settings) == nil, "Four-finger tap does not substitute for click")
        r.reset()
        _ = r.consume(points(3), timestamp: 222, settings: settings)
        expect(r.physicalClick(timestamp: 222.05) == nil, "Three contacts cannot trigger Four Finger Click")
        r.reset()
        _ = r.consume(points(5), timestamp: 223, settings: settings)
        expect(r.physicalClick(timestamp: 223.05) == nil, "Five contacts cannot trigger Four Finger Click")
        for (dx, dy, gesture) in [(0.25, 0.0, MagicMouseGesture.fourFingerSwipeRight), (-0.25, 0.0, .fourFingerSwipeLeft), (0.0, 0.25, .fourFingerSwipeUp), (0.0, -0.25, .fourFingerSwipeDown)] {
            settings.bindings[gesture] = .showDesktop
            let start = points(4, x: 0.3, y: 0.5)
            let end = start.map { MouseContact(id: $0.id, x: $0.x + dx, y: $0.y + dy) }
            r.reset()
            _ = r.consume(start, timestamp: 230, settings: settings)
            expect(r.consume(end.reversed(), timestamp: 230.2, settings: settings) == gesture, "Four-finger swipe is independent of frame order")
            expect(r.consume(end, timestamp: 230.3, settings: settings) == nil, "Four-finger swipe fires once")
            expect(r.consume([], timestamp: 230.4, settings: settings) == nil, "Four-finger swipe release cannot tap")
            r.reset()
            _ = r.consume(start, timestamp: 231, settings: settings)
            expect(r.consume([end[0]] + Array(start.dropFirst()), timestamp: 231.2, settings: settings) == nil, "One moving finger cannot trigger Four Finger Swipe")
            r.reset()
            _ = r.consume(start, timestamp: 232, settings: settings)
            expect(r.consume(Array(end.dropLast()), timestamp: 232.2, settings: settings) == nil, "Partial lift cannot become a four- or three-finger swipe")
        }
        settings = MagicMouseSettings()
        r.reset()
        for (x, y) in [(0.48, 0.25), (0.8, 0.7), (0.2, 0.5)] {
            let origin = MouseContact(id: 1, x: x, y: y)
            _ = r.consume([origin], timestamp: 240 + x, settings: settings)
            let rawTap = r.consume([], timestamp: 240.1 + x, settings: settings)
            expect(rawTap == (x < 0.5 ? .leftTap : .rightTap), "Raw one-finger tap preserves its side")
            expect(r.lastTapLocation == origin, "Regional tap retains current landing position after release")
            r.reset()
        }
        // Trackpad additions use the same tested pure recognizer, separate bindings.
        settings = MagicMouseSettings(); settings.bindings = [.fourFingerTap: .showDesktop, .fourFingerDoubleTap: .missionControl]
        r.reset()
        _ = r.consume(points(4), timestamp: 300, settings: settings)
        expect(r.consume([], timestamp: 300.1, settings: settings) == nil, "Four-finger tap waits when double-tap is assigned")
        expect(r.flushPendingTap(at: 300.41) == .fourFingerTap, "Four-finger single tap fires after double window")
        r.reset()
        _ = r.consume(points(4), timestamp: 301, settings: settings)
        _ = r.consume([], timestamp: 301.1, settings: settings)
        _ = r.consume(points(4).reversed(), timestamp: 301.2, settings: settings)
        expect(r.consume([], timestamp: 301.3, settings: settings) == .fourFingerDoubleTap, "Four-finger double-tap recognizes reordered frames")
        expect(r.flushPendingTap(at: 302) == nil, "Four-finger double-tap does not also single-tap")
        for (x, y, gesture) in [(0.1, 0.1, MagicMouseGesture.cornerBottomLeft), (0.9, 0.1, .cornerBottomRight), (0.1, 0.9, .cornerTopLeft), (0.9, 0.9, .cornerTopRight)] {
            settings = MagicMouseSettings(); settings.bindings = [gesture: .showDesktop]
            r.reset(); _ = r.consume(points(1, x: x, y: y), timestamp: 310, settings: settings)
            expect(r.physicalClick(timestamp: 310.05) == gesture, "Each trackpad corner requires its configured physical click")
            expect(r.consume([], timestamp: 310.1, settings: settings) == nil, "Corner click release cannot tap")
            r.reset(); _ = r.consume(points(1, x: 0.5, y: 0.5), timestamp: 311, settings: settings)
            expect(r.physicalClick(timestamp: 311.05) == nil, "Centre click cannot trigger a corner")
        }
        let tripleAnchors = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.55, y: 0.5), MouseContact(id: 3, x: 0.7, y: 0.5)]
        for (x, gesture) in [(0.2, MagicMouseGesture.tipTapThreeLeft), (0.9, .tipTapThreeRight)] {
            for size in [0.2, 0.6] {
                settings = MagicMouseSettings(); settings.bindings = [gesture: .showDesktop]
                let extra = MouseContact(id: 4, x: x, y: 0.5, size: size)
                r.reset(); _ = r.consume(tripleAnchors, timestamp: 320, settings: settings)
                _ = r.consume([extra] + tripleAnchors.reversed(), timestamp: 320.3, settings: settings)
                expect(r.ownsFixedFingerSession, "Three anchors claim the four-contact session")
                expect(r.consume(tripleAnchors, timestamp: 320.4, settings: settings) == (size >= 0.35 ? gesture : nil), "Three-fixed-finger sensitivity uses actual contact size")
                expect(r.consume([], timestamp: 320.5, settings: settings) == nil, "Three anchors cannot turn release into a tap")
            }
            settings.tipTap.threeFingerSensitivity = 0.1
            r.reset(); _ = r.consume(tripleAnchors, timestamp: 321, settings: settings)
            _ = r.consume(tripleAnchors + [MouseContact(id: 4, x: x, y: 0.5, size: 0.2)], timestamp: 321.3, settings: settings)
            expect(r.consume(Array(tripleAnchors.dropLast()), timestamp: 321.4, settings: settings) == nil, "Lifting any of three anchors cancels TipTap")
        }
        for (dx, gesture) in [(-0.18, MagicMouseGesture.tipSwipeLeftLeft), (0.18, .tipSwipeLeftRight)] {
            settings = MagicMouseSettings(); settings.bindings = [gesture: .showDesktop]
            let extra = MouseContact(id: 3, x: 0.2, y: 0.5)
            r.reset(); _ = r.consume(anchors, timestamp: 330, settings: settings)
            _ = r.consume(anchors + [extra], timestamp: 330.3, settings: settings)
            expect(r.tipSwipeAxes == .horizontal, "Horizontal TipSwipe reserves only its horizontal axis")
            r.cancelTap()
            expect(r.consume(anchors + [MouseContact(id: 3, x: 0.2 + dx, y: 0.5)], timestamp: 330.5, settings: settings) == gesture, "Horizontal TipSwipe survives native tap cancellation")
            expect(r.consume(anchors, timestamp: 330.6, settings: settings) == nil, "Horizontal TipSwipe cannot also tap")
        }
        func oneAnchorTap(_ profile: TipTapTuning, size: Double = 0.4, movement: Double = 0, spacing: Double = 0.2) -> MagicMouseGesture? {
            var test = MagicMouseRecognizer(), config = MagicMouseSettings()
            config.tipTap = profile; config.bindings = [.tipTapLeft: .showDesktop]
            let anchor = MouseContact(id: 1, x: 0.6, y: 0.5)
            let tip = MouseContact(id: 2, x: 0.6 - spacing, y: 0.5, size: size)
            _ = test.consume([anchor], timestamp: 340, settings: config)
            _ = test.consume([anchor, tip], timestamp: 340.3, settings: config)
            _ = test.consume([anchor, MouseContact(id: 2, x: tip.x + movement, y: tip.y, size: size)], timestamp: 340.35, settings: config)
            return test.consume([anchor], timestamp: 340.4, settings: config)
        }
        var profile = TipTapTuning()
        expect(oneAnchorTap(profile) == .tipTapLeft, "Default TipTap contact-size threshold accepts firmer touch")
        profile.sensitivity = 0.6
        expect(oneAnchorTap(profile) == nil, "Harder TipTap slider rejects lighter contact")
        profile.allowSensitiveTipTaps = true
        expect(oneAnchorTap(profile) == .tipTapLeft, "Sensitive mouse option lowers the size threshold")
        profile = TipTapTuning()
        expect(oneAnchorTap(profile, movement: 0.07) == nil, "Movement is rejected by default")
        profile.allowFingerMovement = true
        expect(oneAnchorTap(profile, movement: 0.07) == .tipTapLeft, "Allow Finger Movement permits bounded movement")
        profile.twoFingerMinimumDistance = 0.25
        expect(oneAnchorTap(profile) == nil, "Minimum spacing rejects close fingers")
        profile.twoFingerMinimumDistance = 0.03; profile.maximumDistance = 0.15
        expect(oneAnchorTap(profile) == nil, "Maximum spacing rejects far fingers")
        profile.sensitivity = .nan; profile.threeFingerMinimumDistance = 0.9
        let normalizedProfile = TipTapTuning.normalized(profile)
        expect(normalizedProfile.sensitivity.isFinite && normalizedProfile.threeFingerMinimumDistance <= normalizedProfile.maximumDistance, "TipTap settings normalize invalid ranges")
        for (sign, gesture) in [(-1.0, MagicMouseGesture.circleClockwise), (1.0, .circleCounterClockwise)] {
            settings = MagicMouseSettings(); settings.bindings = [gesture: .showDesktop, .oneFingerSwipeLeft: .snapLeft, .oneFingerSwipeRight: .snapRight]
            r.reset()
            for index in 0...48 {
                let angle = Double(index) / 48 * .pi * 2 * sign
                let result = r.consume([MouseContact(id: 1, x: 0.5 + cos(angle) * 0.15, y: 0.5 + sin(angle) * 0.13)], timestamp: 350 + Double(index) * 0.02, settings: settings)
                expect(result == nil, "Circle cannot prematurely fire a swipe or tap")
            }
            expect(r.consume([], timestamp: 351, settings: settings) == gesture, "Closed circle follows its winding direction")
            expect(r.consume([], timestamp: 351.1, settings: settings) == nil, "Circle only fires once")
            r.reset()
            for index in 0...20 {
                let angle = Double(index) / 40 * .pi * 2 * sign
                _ = r.consume([MouseContact(id: 1, x: 0.5 + cos(angle) * 0.15, y: 0.5 + sin(angle) * 0.13)], timestamp: 352 + Double(index) * 0.02, settings: settings)
            }
            expect(r.consume([], timestamp: 352.5, settings: settings) == nil, "Open arc is neither circle nor straight swipe")
        }
        r.reset()
        _ = r.consume(points(1, x: 0.2), timestamp: 360, settings: settings)
        _ = r.consume(points(1, x: 0.5), timestamp: 360.2, settings: settings)
        expect(r.consume([], timestamp: 360.3, settings: settings) == .oneFingerSwipeRight, "Straight swipe still works when a circle is assigned")
        // Repeated strokes keep their anchors, including when the previous
        // action switches applications. No timing/sensitivity defaults change.
        for anchorCount in 1...3 {
            let anchors = (0..<anchorCount).map { MouseContact(id: Int32($0 + 1), x: 0.4 + Double($0) * 0.15, y: 0.5) }
            let gesture: MagicMouseGesture = anchorCount == 1 ? .tipTapLeft : (anchorCount == 2 ? .tipTapTwoLeft : .tipTapThreeLeft)
            settings = MagicMouseSettings(); settings.bindings = [gesture: .showDesktop]
            r.reset()
            _ = r.consume(anchors, timestamp: 400, settings: settings)
            for index in 0..<4 {
                let start = 400.3 + Double(index) * 0.2
                let tip = MouseContact(id: Int32(20 + index), x: 0.2, y: 0.5)
                expect(r.consume(anchors + [tip], timestamp: start, settings: settings) == nil, "TipTap never fires on touchdown")
                expect(r.consume(anchors.reversed(), timestamp: start + 0.10, settings: settings) == gesture, "Repeated TipTap works with stable anchors and new tip IDs")
                expect(r.isRestingForTipTap, "Only the anchor-only interval can survive an app change")
                r.changeAppContext()
                expect(r.consume(anchors, timestamp: start + 0.11, settings: settings) == nil, "An app change cannot replay the previous stroke")
            }
            expect(r.consume([], timestamp: 401.2, settings: settings) == nil, "Final anchor release never becomes a regular tap")
            r.reset()
            _ = r.consume(anchors, timestamp: 410, settings: settings)
            let tip = MouseContact(id: 20, x: 0.2, y: 0.5)
            _ = r.consume(anchors + [tip], timestamp: 410.3, settings: settings)
            r.changeAppContext()
            expect(r.consume(anchors, timestamp: 410.4, settings: settings) == nil, "Mid-stroke app changes cancel the pending TipTap")
            _ = r.consume(anchors + [tip], timestamp: 410.5, settings: settings)
            expect(r.consume(anchors, timestamp: 410.6, settings: settings) == gesture, "An app change during a tap must not block the next tap on the same anchors")
            _ = r.consume([], timestamp: 410.7, settings: settings)
            _ = r.consume(anchors, timestamp: 411, settings: settings)
            _ = r.consume(anchors + [tip], timestamp: 411.3, settings: settings)
            r.cancelTap()
            expect(r.consume(anchors, timestamp: 411.4, settings: settings) == nil, "Native scroll cancels the current tap")
            _ = r.consume(anchors + [tip], timestamp: 411.5, settings: settings)
            expect(r.consume(anchors, timestamp: 411.6, settings: settings) == gesture, "A cancelled tap does not permanently disable resting anchors")
            _ = r.consume(anchors + [tip], timestamp: 411.61, settings: settings)
            expect(r.consume(anchors, timestamp: 411.62, settings: settings) == nil, "Brief contact bounce after a tap is rejected")
            _ = r.consume(anchors + [tip], timestamp: 411.8, settings: settings)
            settings.bindings = [:] // New app has no matching TipTap.
            r.changeAppContext()
            expect(r.consume(anchors, timestamp: 411.9, settings: settings) == nil, "Changing to an unassigned app never fires an old action")
        }
        // A browser's one-anchor tab bindings must coexist with global
        // two-anchor Stage Manager bindings when resting fingers land in order.
        for x in [0.15, 0.85] {
            settings = MagicMouseSettings()
            settings.tipTapAnchorDuration = 0.16
            settings.bindings = [.tipTapLeft: .showDesktop, .tipTapRight: .showDesktop,
                                 .tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let first = MouseContact(id: 1, x: 0.4, y: 0.5)
            let second = MouseContact(id: 2, x: 0.6, y: 0.5)
            let third = MouseContact(id: 3, x: x, y: 0.5)
            let expected: MagicMouseGesture = x < 0.4 ? .tipTapTwoLeft : .tipTapTwoRight
            r.reset()
            _ = r.consume([first], timestamp: 500, settings: settings)
            _ = r.consume([first, second], timestamp: 500.2, settings: settings)
            expect(r.consume([first, second, third], timestamp: 500.4, settings: settings) == nil, "Settled two-finger chord promotes without firing the one-anchor binding")
            expect(r.consume([first, second], timestamp: 500.5, settings: settings) == expected, "Higher-finger TipTap wins after sequential anchor landing")
            _ = r.consume([first, second, third], timestamp: 500.6, settings: settings)
            expect(r.consume([first, second], timestamp: 500.7, settings: settings) == expected, "Promoted chord still supports repeat taps")
            expect(r.consume([], timestamp: 500.8, settings: settings) == nil, "Promoted anchors never emit the lower-finger action on release")
        }
        for promoteAt in [0.10, 0.20] {
            settings = MagicMouseSettings(); settings.tipTapAnchorDuration = 0.16
            settings.bindings = [.tipTapRight: .showDesktop, .tipTapTwoLeft: .missionControl]
            let a = MouseContact(id: 1, x: 0.4, y: 0.5)
            let b = MouseContact(id: 2, x: 0.6, y: 0.5)
            let c = MouseContact(id: 3, x: 0.15, y: 0.5)
            r.reset()
            _ = r.consume([a], timestamp: 510, settings: settings)
            _ = r.consume([a, b], timestamp: 510.2, settings: settings)
            _ = r.consume([a, b, c], timestamp: 510.2 + promoteAt, settings: settings)
            expect(r.consume([a, b], timestamp: 510.3 + promoteAt, settings: settings) == (promoteAt >= 0.16 ? .tipTapTwoLeft : nil), "Promotion still requires the complete anchor chord to settle")
        }
        settings = MagicMouseSettings(); settings.tipTapAnchorDuration = 0.16
        settings.bindings = [.tipTapRight: .showDesktop, .tipTapTwoLeft: .missionControl, .tipTapThreeLeft: .snapLeft]
        let chord = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.55, y: 0.5)]
        r.reset()
        _ = r.consume([chord[0]], timestamp: 520, settings: settings)
        _ = r.consume(chord, timestamp: 520.2, settings: settings)
        expect(r.consume([chord[0]], timestamp: 520.3, settings: settings) == .tipTapRight, "Lower-finger action remains usable")
        let replacement = MouseContact(id: 12, x: 0.55, y: 0.5)
        _ = r.consume([chord[0], replacement], timestamp: 520.4, settings: settings)
        let third = MouseContact(id: 13, x: 0.2, y: 0.5)
        _ = r.consume([chord[0], replacement, third], timestamp: 520.6, settings: settings)
        expect(r.consume([chord[0], replacement], timestamp: 520.7, settings: settings) == .tipTapTwoLeft, "A completed lower-finger tap does not leave stale anchor IDs behind")
        r.reset()
        _ = r.consume(chord, timestamp: 530, settings: settings)
        let left = MouseContact(id: 3, x: 0.25, y: 0.5)
        _ = r.consume(chord + [left], timestamp: 530.2, settings: settings)
        let fourth = MouseContact(id: 4, x: 0.1, y: 0.5)
        _ = r.consume(chord + [left, fourth], timestamp: 530.4, settings: settings)
        expect(r.consume(chord + [left], timestamp: 530.5, settings: settings) == .tipTapThreeLeft, "Trackpad can promote two anchors into three stationary anchors")
        // Resting fingers naturally reposition between taps. Movement during a
        // tap still rejects that stroke, but must not poison later settled taps.
        for count in 1...3 {
            settings = MagicMouseSettings()
            let gesture: MagicMouseGesture = count == 1 ? .tipTapLeft : (count == 2 ? .tipTapTwoLeft : .tipTapThreeLeft)
            settings.bindings = [gesture: .missionControl]
            let rest = (0..<count).map { MouseContact(id: Int32($0 + 1), x: 0.4 + Double($0) * 0.1, y: 0.5) }
            let shifted = rest.map { MouseContact(id: $0.id, x: $0.x, y: $0.y + 0.06) }
            let tip = MouseContact(id: 10, x: 0.2, y: 0.5)
            for duringTap in [false, true] {
                r.reset()
                _ = r.consume(rest, timestamp: 600, settings: settings)
                _ = r.consume(rest + [tip], timestamp: 600.3, settings: settings)
                expect(r.consume(rest, timestamp: 600.4, settings: settings) == gesture, "Initial TipTap before resting-finger movement")
                if duringTap { _ = r.consume(rest + [tip], timestamp: 600.5, settings: settings) }
                expect(r.consume(shifted + (duringTap ? [tip] : []), timestamp: 600.55, settings: settings) == nil, "Moving resting fingers cannot trigger a tap")
                expect(r.consume(shifted, timestamp: 600.65, settings: settings) == nil, "Rejected stroke cannot fire on release")
                _ = r.consume(shifted, timestamp: 600.95, settings: settings)
                _ = r.consume(shifted + [tip], timestamp: 601, settings: settings)
                expect(r.consume(shifted, timestamp: 601.1, settings: settings) == gesture, "TipTap recovers after resting fingers settle without lifting all fingers")
                expect(r.consume([], timestamp: 601.2, settings: settings) == nil, "Recovery cannot turn final lift into a normal tap")
            }
        }
        settings = MagicMouseSettings()
        settings.tipTap = .mouseDefaults
        settings.tipTapMinimumDuration = 0.06
        settings.tipTapAnchorDuration = 0.16
        settings.bindings = [.tipTapTwoLeft: .missionControl]
        let stablePair = [MouseContact(id: 1, x: 0.45, y: 0.5), MouseContact(id: 2, x: 0.65, y: 0.5)]
        let tapping = MouseContact(id: 3, x: 0.2, y: 0.5)
        let shiftedPair = stablePair.map { MouseContact(id: $0.id, x: $0.x, y: 0.57) }
        r.reset()
        _ = r.consume(stablePair, timestamp: 700, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 700.2, settings: settings)
        expect(r.consume(stablePair, timestamp: 700.3, settings: settings) == .tipTapTwoLeft, "User timing accepts a deliberate three-finger TipTap")
        _ = r.consume(shiftedPair, timestamp: 700.4, settings: settings)
        _ = r.consume(shiftedPair + [tapping], timestamp: 700.45, settings: settings)
        _ = r.consume(shiftedPair + [tapping], timestamp: 700.65, settings: settings)
        expect(r.consume(shiftedPair, timestamp: 700.75, settings: settings) == nil, "A finger arriving before anchors settle cannot arm later while held")
        expect(r.tipTapFeedback == TipTapRejection.notSettled.rawValue, "Anchor timing rejection is visible")
        _ = r.consume(shiftedPair + [tapping], timestamp: 700.9, settings: settings)
        expect(r.consume(shiftedPair, timestamp: 701, settings: settings) == .tipTapTwoLeft, "Fresh tap after rejected held contact works")
        for reason in [TipTapRejection.short, .long, .light, .moved, .scrolling, .spacing, .anchorLifted] {
            r.reset()
            _ = r.consume(stablePair, timestamp: 710, settings: settings)
            let tip = MouseContact(id: 3, x: reason == .spacing ? 0.04 : 0.2, y: 0.5, size: reason == .light ? 0.1 : 1)
            _ = r.consume(stablePair + [tip], timestamp: 710.2, settings: settings)
            if reason == .scrolling { r.cancelTap() }
            if reason == .moved { _ = r.consume(stablePair + [MouseContact(id: 3, x: 0.28, y: 0.5)], timestamp: 710.25, settings: settings) }
            let remaining = reason == .anchorLifted ? [stablePair[0], tip] : stablePair
            let end = reason == .short ? 710.23 : (reason == .long ? 710.6 : 710.3)
            expect(r.consume(remaining, timestamp: end, settings: settings) == nil, "Rejected TipTap cannot execute: \(reason)")
            expect(r.tipTapFeedback == reason.rawValue, "TipTap feedback explains rejection: \(reason)")
        }
        r.reset()
        _ = r.consume(stablePair, timestamp: 720, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 720.2, settings: settings)
        _ = r.consume([stablePair[0], tapping], timestamp: 720.3, settings: settings)
        _ = r.consume(stablePair, timestamp: 720.6, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 720.9, settings: settings)
        expect(r.consume(stablePair, timestamp: 721, settings: settings) == .tipTapTwoLeft, "Trackpad rearms a fresh settled chord after losing an anchor")
        r.reset()
        _ = r.consume(stablePair, timestamp: 730, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 730.2, settings: settings)
        _ = r.consume(stablePair, timestamp: 730.3, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 730.31, settings: settings)
        _ = r.consume(stablePair + [tapping], timestamp: 730.4, settings: settings)
        expect(r.consume(stablePair, timestamp: 730.5, settings: settings) == nil, "Debounced contact cannot become a tap by remaining held")
        // Magic Mouse two-anchor TipTaps survive brief contact dropout/ID churn.
        // Longer loss discards the stroke and rearms, never turns a tip into an anchor.
        for right in [false, true] {
            let gesture: MagicMouseGesture = right ? .tipTapTwoRight : .tipTapTwoLeft
            settings = MagicMouseSettings()
            settings.tipTap = .mouseDefaults
            settings.tipTapSpacingGeometry = .magicMouse
            settings.tipTapAnchorDuration = 0.16
            settings.tipTapMinimumDuration = 0.06
            settings.bindings = [gesture: .missionControl]
            let rest = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.6, y: 0.5)]
            let tip = MouseContact(id: 3, x: right ? 0.8 : 0.2, y: 0.5)
            for replaceID in [false, true] {
                r.reset()
                _ = r.consume(rest, timestamp: 800, settings: settings)
                _ = r.consume(rest + [tip], timestamp: 800.2, settings: settings)
                expect(r.consume([rest[0], tip], timestamp: 800.23, settings: settings) == nil, "Dropout cannot emit while an anchor is missing")
                let restored = [rest[0], MouseContact(id: replaceID ? 20 : 2, x: 0.605, y: 0.5)]
                expect(r.consume(restored + [tip], timestamp: 800.25, settings: settings) == nil, "Restoring an anchor does not fire on touchdown")
                expect(r.consume(restored, timestamp: 800.3, settings: settings) == gesture, "Brief mouse anchor loss preserves a deliberate tap")
                _ = r.consume(restored + [tip], timestamp: 800.4, settings: settings)
                expect(r.consume(restored, timestamp: 800.5, settings: settings) == gesture, "Recovered anchors support the next tap without full release")
            }
            r.reset()
            _ = r.consume(rest, timestamp: 810, settings: settings)
            _ = r.consume(rest + [tip], timestamp: 810.2, settings: settings)
            _ = r.consume([rest[0], tip], timestamp: 810.23, settings: settings)
            expect(r.consume([rest[0], tip], timestamp: 810.4, settings: settings) == nil, "A real anchor lift cancels the pending tap")
            expect(r.consume(rest + [tip], timestamp: 810.5, settings: settings) == nil, "The old held tip cannot rearm the chord")
            expect(r.consume(rest, timestamp: 810.6, settings: settings) == nil, "Rearming on two resting fingers emits no action")
            _ = r.consume(rest + [tip], timestamp: 810.8, settings: settings)
            expect(r.consume(rest, timestamp: 810.9, settings: settings) == gesture, "After a real lift, a settled chord can repeat without every finger lifting")
            // Distant replacements cannot inherit the interrupted stroke.
            r.reset()
            _ = r.consume(rest, timestamp: 820, settings: settings)
            _ = r.consume(rest + [tip], timestamp: 820.2, settings: settings)
            let distant = [rest[0], MouseContact(id: 22, x: 0.6, y: 0.8)]
            _ = r.consume(distant + [tip], timestamp: 820.23, settings: settings)
            _ = r.consume(distant + [tip], timestamp: 820.4, settings: settings)
            expect(r.consume(distant, timestamp: 820.5, settings: settings) == nil, "A distant replacement never completes the pending tap")
            // A physical click remains a hard cancel, even with anchor recovery.
            r.reset()
            _ = r.consume(rest, timestamp: 830, settings: settings)
            _ = r.consume(rest + [tip], timestamp: 830.2, settings: settings)
            _ = r.physicalClick(timestamp: 830.22)
            _ = r.consume([rest[0], tip], timestamp: 830.23, settings: settings)
            _ = r.consume(rest + [tip], timestamp: 830.25, settings: settings)
            expect(r.consume(rest, timestamp: 830.3, settings: settings) == nil, "Recovery never revives a physically cancelled gesture")
        }
        // Three fingers can span most of the narrow mouse while the tapping
        // finger remains close to its neighbouring resting finger.
        for right in [false, true] {
            for staggered in [false, true] {
                settings = MagicMouseSettings()
                settings.tipTap = .mouseDefaults
                settings.tipTapSpacingGeometry = .magicMouse
                let gesture: MagicMouseGesture = right ? .tipTapTwoRight : .tipTapTwoLeft
                settings.bindings = [gesture: .missionControl]
                let rest = [MouseContact(id: 1, x: right ? 0.12 : 0.48, y: 0.7),
                            MouseContact(id: 2, x: right ? 0.52 : 0.88, y: 0.75)]
                let tip = MouseContact(id: 3, x: right ? 0.88 : 0.12, y: staggered ? 0.12 : 0.7)
                r.reset()
                _ = r.consume(rest, timestamp: 740, settings: settings)
                _ = r.consume(rest + [tip], timestamp: 740.3, settings: settings)
                expect(r.consume(rest, timestamp: 740.4, settings: settings) == gesture, "Magic Mouse accepts a wide three-finger chord with a nearby tapping finger")
                _ = r.consume(rest + [tip], timestamp: 740.6, settings: settings)
                expect(r.consume(rest, timestamp: 740.7, settings: settings) == gesture, "Wide Magic Mouse chord supports repeated TipTaps")
            }
        }
        let mouseProfile = TipTapTuning.mouseDefaults
        let wideRest = [MouseContact(id: 1, x: 0.48, y: 0.7), MouseContact(id: 2, x: 0.88, y: 0.75)]
        let wideTip = MouseContact(id: 3, x: 0.12, y: 0.12)
        expect(!mouseProfile.allowsSpacing(wideTip, anchors: wideRest, geometry: .surface), "Trackpad retains its configured surface-distance limit")
        expect(mouseProfile.allowsSpacing(wideTip, anchors: wideRest, geometry: .magicMouse), "Mouse spacing uses the nearest sideways gap")
        expect(!mouseProfile.allowsSpacing(MouseContact(id: 3, x: 0.47, y: 0.2), anchors: wideRest, geometry: .magicMouse), "Mouse still rejects indistinguishably close sideways contacts")
        expect(!mouseProfile.allowsSpacing(MouseContact(id: 3, x: 0.02, y: 0.7), anchors: [MouseContact(id: 1, x: 0.8, y: 0.7)], geometry: .magicMouse), "Mouse still enforces maximum neighbour gap")
        var restrictedSpacing = mouseProfile
        restrictedSpacing.maximumDistance = 0.25
        expect(!restrictedSpacing.allowsSpacing(wideTip, anchors: wideRest, geometry: .magicMouse), "Custom maximum mouse spacing remains effective")
        restrictedSpacing = mouseProfile; restrictedSpacing.threeFingerMinimumDistance = 0.4
        expect(!restrictedSpacing.allowsSpacing(wideTip, anchors: wideRest, geometry: .magicMouse), "Custom minimum mouse spacing remains effective")
        expect(!mouseProfile.allowsSpacing(wideTip, anchors: [], geometry: .magicMouse), "Mouse spacing cannot accept missing anchors")
        // Trackpad resting contacts may disappear for a sample or return with
        // a nearby new ID. This must not permanently disable the chord.
        for gesture in [MagicMouseGesture.tipTapLeft, .tipTapRight, .tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight, .tipTapThreeLeft, .tipTapThreeRight] {
            let count = gesture.fingers - 1
            let anchors = (0..<count).map { MouseContact(id: Int32($0 + 1), x: 0.4 + Double($0) * 0.1, y: 0.5) }
            let x = gesture == .tipTapTwoMiddle ? 0.45 : (gesture.rawValue.hasSuffix("left") ? 0.2 : 0.8)
            let tip = MouseContact(id: 40, x: x, y: 0.5)
            var tuning = MagicMouseSettings()
            tuning.tipTap = TipTapTuning(); tuning.tipTapSpacingGeometry = .surface
            tuning.bindings = [gesture: .missionControl]
            for newID in [false, true] {
                var trackpad = MagicMouseRecognizer()
                _ = trackpad.consume(anchors, timestamp: 900, settings: tuning)
                _ = trackpad.consume(anchors + [tip], timestamp: 900.3, settings: tuning)
                expect(trackpad.consume(Array(anchors.dropLast()) + [tip], timestamp: 900.33, settings: tuning) == nil, "Anchor loss cannot trigger on its own")
                var restored = anchors
                restored[count - 1] = MouseContact(id: newID ? 30 : anchors[count - 1].id, x: anchors[count - 1].x + 0.004, y: 0.5)
                expect(trackpad.consume(restored + [tip], timestamp: 900.36, settings: tuning) == nil, "Recovered trackpad anchor cannot trigger on touchdown")
                expect(trackpad.consume(restored, timestamp: 900.42, settings: tuning) == gesture, "Brief trackpad anchor loss preserves the tap: \(gesture)")
                _ = trackpad.consume(restored + [tip], timestamp: 900.55, settings: tuning)
                expect(trackpad.consume(restored, timestamp: 900.67, settings: tuning) == gesture, "Recovered trackpad chord repeats without lifting all fingers")
                let feedback = trackpad.tipTapFeedback
                _ = trackpad.consume(Array(restored.dropLast()), timestamp: 900.7, settings: tuning)
                _ = trackpad.consume([], timestamp: 900.72, settings: tuning)
                expect(trackpad.tipTapFeedback == feedback, "Ordinary hand release preserves the successful result")
            }
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(anchors, timestamp: 910, settings: tuning)
            _ = trackpad.consume(anchors + [tip], timestamp: 910.3, settings: tuning)
            _ = trackpad.consume(Array(anchors.dropLast()) + [tip], timestamp: 910.33, settings: tuning)
            expect(trackpad.consume(anchors + [tip], timestamp: 910.5, settings: tuning) == nil, "Long anchor loss cancels the old stroke")
            expect(trackpad.consume(anchors, timestamp: 910.6, settings: tuning) == nil, "Rearming after a real lift never fires")
            _ = trackpad.consume(anchors + [tip], timestamp: 910.9, settings: tuning)
            expect(trackpad.consume(anchors, timestamp: 911.02, settings: tuning) == gesture, "A fresh settled trackpad chord can tap again after a real lift")
            trackpad.reset()
            _ = trackpad.consume(anchors, timestamp: 920, settings: tuning)
            _ = trackpad.consume(anchors + [tip], timestamp: 920.3, settings: tuning)
            var distant = anchors
            distant[count - 1] = MouseContact(id: 30, x: anchors[count - 1].x, y: 0.8)
            _ = trackpad.consume(distant + [tip], timestamp: 920.33, settings: tuning)
            expect(trackpad.consume(distant, timestamp: 920.42, settings: tuning) == nil, "A distant replacement cannot inherit a trackpad stroke")
            trackpad.reset()
            _ = trackpad.consume(anchors, timestamp: 930, settings: tuning)
            _ = trackpad.consume(anchors + [tip], timestamp: 930.3, settings: tuning)
            _ = trackpad.physicalClick(timestamp: 930.32)
            _ = trackpad.consume(Array(anchors.dropLast()) + [tip], timestamp: 930.33, settings: tuning)
            _ = trackpad.consume(anchors + [tip], timestamp: 930.36, settings: tuning)
            expect(trackpad.consume(anchors, timestamp: 930.42, settings: tuning) == nil, "Recovery cannot revive a physically cancelled trackpad gesture")
        }
        // Alternate on a staggered trackpad chord. The tip can fall inside the
        // anchors' horizontal span and fingers can roll slightly during a tap.
        for count in 1...3 {
            let left: MagicMouseGesture = count == 1 ? .tipTapLeft : (count == 2 ? .tipTapTwoLeft : .tipTapThreeLeft)
            let right: MagicMouseGesture = count == 1 ? .tipTapRight : (count == 2 ? .tipTapTwoRight : .tipTapThreeRight)
            var tuning = MagicMouseSettings()
            tuning.tipTap = .trackpadDefaults; tuning.tipTapSpacingGeometry = .surface
            tuning.bindings = [left: .missionControl, right: .missionControl]
            var rest = (0..<count).map { MouseContact(id: Int32($0 + 1), x: count == 1 ? 0.5 : 0.4 + Double($0) * 0.2 / Double(count - 1), y: 0.4 + Double($0) * 0.15) }
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(rest, timestamp: 950, settings: tuning)
            for tap in 0..<6 {
                let isLeft = tap % 2 == 0
                let time = 950.4 + Double(tap) * 0.22
                let tip = MouseContact(id: Int32(40 + tap), x: isLeft ? 0.41 : 0.59, y: isLeft ? 0.75 : 0.25, size: 0.3)
                _ = trackpad.consume(rest + [tip], timestamp: time, settings: tuning)
                rest = rest.map { MouseContact(id: $0.id, x: $0.x, y: $0.y + (isLeft ? 0.04 : -0.04)) }
                _ = trackpad.consume(rest + [MouseContact(id: tip.id, x: tip.x, y: tip.y + 0.04, size: 0.3)], timestamp: time + 0.05, settings: tuning)
                expect(trackpad.consume(rest, timestamp: time + 0.12, settings: tuning) == (isLeft ? left : right), "Staggered trackpad placement supports alternating sides and modest finger roll")
            }
        }
        // A fresh finger on the opposite side is not bounce from the tap that
        // just lifted. Short alternating gaps should still produce one action.
        for count in 1...3 {
            let left: MagicMouseGesture = count == 1 ? .tipTapLeft : (count == 2 ? .tipTapTwoLeft : .tipTapThreeLeft)
            let right: MagicMouseGesture = count == 1 ? .tipTapRight : (count == 2 ? .tipTapTwoRight : .tipTapThreeRight)
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [left: .missionControl, right: .missionControl]
            let rest = (0..<count).map { MouseContact(id: Int32($0 + 1), x: 0.4 + Double($0) * 0.1, y: 0.5) }
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(rest, timestamp: 970, settings: tuning)
            for tap in 0..<8 {
                let expected = tap % 2 == 0 ? left : right
                let tip = MouseContact(id: Int32(50 + tap), x: tap % 2 == 0 ? 0.2 : 0.8, y: 0.5, size: 0.3)
                let time = 970.4 + Double(tap) * 0.135
                _ = trackpad.consume(rest + [tip], timestamp: time, settings: tuning)
                expect(trackpad.consume(rest, timestamp: time + 0.12, settings: tuning) == expected, "Rapid alternating TipTaps each fire once")
            }
            // Paired trackpad releases validate the full contact duration, even after a quick return.
            // Other fixed-finger modes retain their landing debounce.
            let bounced = MouseContact(id: 70, x: 0.8, y: 0.5, size: 0.3)
            _ = trackpad.consume(rest + [bounced], timestamp: 971.475, settings: tuning)
            expect(trackpad.consume(rest, timestamp: 971.6, settings: tuning) == (count == 2 ? right : nil), "Paired trackpad mode accepts a full-duration return; other modes retain debounce")
            if count == 2 {
                _ = trackpad.consume(rest + [bounced], timestamp: 971.61, settings: tuning)
                expect(trackpad.consume(rest, timestamp: 971.63, settings: tuning) == nil, "A 20 ms contact bounce is still rejected")
            }
        }
        // Video reference: a settled three-finger hand, then alternating outer
        // releases. Each release itself is the action, not preparation for an
        // additional landing-and-lift cycle. These are synthetic contact traces;
        // the camera footage does not provide sensor IDs or exact contact times.
        for startsRight in [false, true] {
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let left = MouseContact(id: 1, x: 0.25, y: 0.5, size: 0.4)
            let middle = MouseContact(id: 2, x: 0.5, y: 0.6, size: 0.4)
            let right = MouseContact(id: 3, x: 0.75, y: 0.52, size: 0.4)
            var r = MagicMouseRecognizer()
            _ = r.consume([left,middle,right], timestamp: 1500, settings: tuning)
            _ = r.consume([left,middle,right], timestamp: 1500.25, settings: tuning)
            for index in 0..<8 {
                let time = 1500.5 + Double(index) * 0.75
                if index > 0 {
                    expect(r.consume([left,middle,right], timestamp: time - 0.4, settings: tuning) == nil, "Replacing the outer finger does not fire")
                    expect(r.consume([left,middle,right], timestamp: time - 0.15, settings: tuning) == nil, "Holding all three does not fire")
                }
                let releaseRight = (index % 2 == 0) == startsRight
                let remaining = releaseRight ? [left,middle] : [middle,right]
                expect(r.consume(remaining, timestamp: time, settings: tuning) == (releaseRight ? .tipTapTwoRight : .tipTapTwoLeft), "Alternating outer release fires immediately without an extra tap cycle")
                expect(r.consume(remaining, timestamp: time + 0.05, settings: tuning) == nil, "Resting after an outer release never repeats the action")
            }
            expect(r.consume([], timestamp: 1506, settings: tuning) == nil, "Final whole-hand release does not add an action")
        }
        // A resting chord is not permission to reinterpret clicks, movement,
        // middle-finger release, insufficient contact or other-device gestures.
        for invalid in 0..<8 {
            var settings = MagicMouseSettings(); settings.tipTap = .trackpadDefaults
            settings.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            if invalid == 6 { settings.tipTapSpacingGeometry = .magicMouse }
            let left = MouseContact(id: 1, x: 0.25, y: 0.5, size: invalid == 2 ? 0.01 : 0.4)
            let middle = MouseContact(id: 2, x: 0.5, y: 0.6, size: 0.4)
            let right = MouseContact(id: 3, x: 0.75, y: 0.52, size: 0.4)
            var r = MagicMouseRecognizer()
            _ = r.consume([left,middle,right], timestamp: 1600, settings: settings)
            if invalid == 0 {
                _ = r.consume([MouseContact(id: 1, x: 0.25, y: 0.8),middle,right], timestamp: 1600.2, settings: settings)
            }
            if invalid == 3 { _ = r.physicalClick(timestamp: 1600.2) }
            if invalid == 5 { r.changeAppContext() }
            if invalid == 7 { _ = r.consume([left,middle,right,MouseContact(id: 4, x: 0.9, y: 0.9)], timestamp: 1600.2, settings: settings) }
            let remaining = invalid == 1 ? [left,right] : [middle,right]
            expect(r.consume(remaining, timestamp: invalid == 4 ? 1600.1 : 1600.4, settings: settings) == nil, "Resting-chord rejection guard \(invalid)")
        }
        // Alternate the outer fingers of one hand: the previous tapping finger
        // becomes an anchor while the opposite finger lifts and taps again.
        for reverse in [false, true] {
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let a = MouseContact(id: 1, x: reverse ? 0.8 : 0.2, y: 0.5, size: 0.3)
            let b = MouseContact(id: 2, x: 0.5, y: 0.55, size: 0.3)
            let c = MouseContact(id: 3, x: reverse ? 0.2 : 0.8, y: 0.6, size: 0.3)
            let first: MagicMouseGesture = reverse ? .tipTapTwoLeft : .tipTapTwoRight
            let opposite: MagicMouseGesture = reverse ? .tipTapTwoRight : .tipTapTwoLeft
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume([a,b], timestamp: 980, settings: tuning)
            _ = trackpad.consume([a,b,c], timestamp: 980.3, settings: tuning)
            expect(trackpad.consume([a,b], timestamp: 980.42, settings: tuning) == first, "Initial tap before changing resting fingers")
            _ = trackpad.consume([a,b,c], timestamp: 980.5, settings: tuning)
            _ = trackpad.consume([b,c], timestamp: 980.62, settings: tuning)
            expect(trackpad.consume([a,b,c], timestamp: 980.72, settings: tuning) == nil, "Changing the tapping finger never fires on landing")
            expect(trackpad.consume([b,c], timestamp: 980.84, settings: tuning) == opposite, "Previously tapping finger becomes an anchor for the opposite TipTap")
            _ = trackpad.consume([a,b,c], timestamp: 980.92, settings: tuning)
            _ = trackpad.consume([a,b], timestamp: 981.04, settings: tuning)
            _ = trackpad.consume([a,b,c], timestamp: 981.14, settings: tuning)
            expect(trackpad.consume([a,b], timestamp: 981.26, settings: tuning) == first, "Same hand alternates back without a full release")
        }
        // The middle finger stays down while the outer fingers rotate. Sensor
        // IDs can change on each landing, and there need not be a three-contact
        // overlap frame before the other outer finger lifts.
        for reverse in [false, true] {
            for overlap in [0.0, 0.02, 0.12] {
                var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
                tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
                let middle = MouseContact(id: 2, x: 0.5, y: 0.55, size: 0.3)
                func outer(_ id: Int32, _ right: Bool) -> MouseContact {
                    MouseContact(id: id, x: right ? 0.8 : 0.2, y: right ? 0.6 : 0.5, size: 0.3)
                }
                var resting = outer(1, reverse)
                var tapping = outer(3, !reverse)
                var r = MagicMouseRecognizer()
                _ = r.consume([resting, middle], timestamp: 1100, settings: tuning)
                _ = r.consume([resting, middle, tapping], timestamp: 1100.3, settings: tuning)
                expect(r.consume([resting, middle], timestamp: 1100.42, settings: tuning) == (reverse ? .tipTapTwoLeft : .tipTapTwoRight), "First tap before same-hand rotation")
                for cycle in 0..<6 {
                    let time = 1100.6 + Double(cycle) * 0.5
                    let nextRest = outer(Int32(20 + cycle * 2), tapping.x > 0.5)
                    let nextTip = outer(Int32(21 + cycle * 2), resting.x > 0.5)
                    if overlap > 0 { _ = r.consume([resting, middle, nextRest], timestamp: time - overlap, settings: tuning) }
                    expect(r.consume([middle, nextRest], timestamp: time, settings: tuning) == (overlap >= tuning.tipTapMinimumDuration ? (nextTip.x < 0.5 ? MagicMouseGesture.tipTapTwoLeft : .tipTapTwoRight) : nil), "A settled chord fires on the actual outer lift; a newly arriving replacement does not")
                    expect(r.consume([middle, nextRest, nextTip], timestamp: time + 0.09, settings: tuning) == nil, "Returning outer finger starts a fresh tap")
                    expect(r.consume([middle, nextRest], timestamp: time + 0.21, settings: tuning) == (nextTip.x < 0.5 ? .tipTapTwoLeft : .tipTapTwoRight), "Rotating outer fingers fires the opposite TipTap without re-settling")
                    resting = nextRest; tapping = nextTip
                }
            }
        }
        // Keep the completed tap's finger down as a new anchor, then briefly
        // lift the opposite outer finger. The brief deliberate lift must not be
        // swallowed by anchor-dropout grace or inherit the held finger's timer.
        for reverse in [false, true] {
            for hold in [0.12, 0.5, 1.0, 3.0] {
                for lift in [0.025, 0.045, 0.09] {
                    for newID in [false, true] {
                        var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
                        tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
                        let middle = MouseContact(id: 2, x: 0.5, y: 0.55, size: 0.3)
                        let resting = MouseContact(id: 1, x: reverse ? 0.2 : 0.8, y: 0.5, size: 0.3)
                        let tapping = MouseContact(id: 3, x: reverse ? 0.8 : 0.2, y: 0.6, size: 0.3)
                        let returned = MouseContact(id: newID ? 11 : 1, x: resting.x, y: resting.y, size: 0.3)
                        let first: MagicMouseGesture = reverse ? .tipTapTwoRight : .tipTapTwoLeft
                        let opposite: MagicMouseGesture = reverse ? .tipTapTwoLeft : .tipTapTwoRight
                        var r = MagicMouseRecognizer()
                        _ = r.consume([resting,middle], timestamp: 1300, settings: tuning)
                        _ = r.consume([resting,middle,tapping], timestamp: 1300.3, settings: tuning)
                        expect(r.consume([resting,middle], timestamp: 1300.42, settings: tuning) == first, "Initial outer tap fires on lift")
                        let held = MouseContact(id: tapping.id, x: tapping.x, y: tapping.y, size: newID ? 0.1 : 0.3)
                        expect(r.consume([resting,middle,held], timestamp: 1300.5, settings: tuning) == nil, "Returning finger never fires on landing")
                        let exchange = 1300.5 + hold
                        var heartbeat = 1300.75
                        while heartbeat < exchange {
                            expect(r.consume([resting,middle,held], timestamp: heartbeat, settings: tuning) == nil, "A stationary held finger never fires an extra action")
                            heartbeat += 0.25
                        }
                        expect(r.consume([middle,held], timestamp: exchange, settings: tuning) == opposite, "The first opposite outer lift fires while the held finger becomes an anchor")
                        expect(r.consume([middle,held,returned], timestamp: exchange + lift, settings: tuning) == nil, "Opposite finger landing does not fire")
                        expect(r.consume([middle,held,returned], timestamp: exchange + lift + 0.12, settings: tuning) == nil, "Keeping the returned finger down does not add another action")
                        expect(r.consume([], timestamp: exchange + lift + 0.2, settings: tuning) == nil, "Whole-hand release after the switch does not add a tap")
                        expect(r.tipTapFeedback != TipTapRejection.long.rawValue, "A held resting finger cannot produce a stale tap timeout")
                    }
                }
            }
        }
        // Brief sensor dropout must preserve the current side; lifting the
        // middle finger, moving the replacement, or a failed first tap must not
        // grant an opposite-side handoff.
        for interruption in 0..<5 {
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let a = MouseContact(id: 1, x: 0.2, y: 0.5, size: 0.3)
            let b = MouseContact(id: 2, x: 0.5, y: 0.55, size: 0.3)
            let c = MouseContact(id: 3, x: 0.8, y: 0.6, size: interruption == 4 ? 0.01 : 0.3)
            var r = MagicMouseRecognizer()
            _ = r.consume([a,b], timestamp: 1200, settings: tuning)
            _ = r.consume([a,b,c], timestamp: 1200.3, settings: tuning)
            expect(r.consume([a,b], timestamp: 1200.42, settings: tuning) == (interruption == 4 ? nil : .tipTapTwoRight), "Only a successful outer tap grants rotation history")
            if interruption == 0 {
                _ = r.consume([a,b,c], timestamp: 1200.5, settings: tuning)
                _ = r.consume([b,c], timestamp: 1200.54, settings: tuning)
                _ = r.consume([a,b,c], timestamp: 1200.57, settings: tuning)
                expect(r.consume([a,b], timestamp: 1200.64, settings: tuning) == .tipTapTwoRight, "Brief anchor dropout cannot change a repeated tap's side")
            } else {
                let replacement = MouseContact(id: 10, x: 0.8, y: interruption == 2 ? 0.8 : 0.6, size: 0.3)
                let remaining = interruption == 1 ? a : b
                let returned = interruption == 1 ? b : a
                _ = r.consume([remaining, replacement], timestamp: 1200.6, settings: tuning)
                if interruption == 3 {
                    _ = r.consume([remaining, MouseContact(id: 10, x: 0.8, y: 0.8)], timestamp: 1200.64, settings: tuning)
                }
                _ = r.consume([remaining, replacement, returned], timestamp: 1200.69, settings: tuning)
                expect(r.consume([remaining, replacement], timestamp: 1200.81, settings: tuning) == nil, "Unrelated movement or a failed initial tap cannot rotate the resting chord")
            }
        }
        // An explicit Middle binding still wins inside the anchor span.
        do {
            let rest = [MouseContact(id: 1, x: 0.4, y: 0.4), MouseContact(id: 2, x: 0.6, y: 0.6)]
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoMiddle: .missionControl, .tipTapTwoRight: .missionControl]
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(rest, timestamp: 990, settings: tuning)
            _ = trackpad.consume(rest + [MouseContact(id: 3, x: 0.41, y: 0.75)], timestamp: 990.3, settings: tuning)
            expect(trackpad.consume(rest, timestamp: 990.42, settings: tuning) == .tipTapTwoMiddle, "Explicit Middle binding retains its region on a staggered chord")
            tuning.bindings[.tipTapTwoMiddle] = nil
            trackpad.reset()
            _ = trackpad.consume(rest, timestamp: 991, settings: tuning)
            _ = trackpad.consume(rest + [MouseContact(id: 3, x: 0.5, y: 0.75)], timestamp: 991.3, settings: tuning)
            expect(trackpad.consume(rest, timestamp: 991.42, settings: tuning) == nil, "An exactly centered tap does not guess a left/right action")
            expect(!tuning.tipTap.allowsSpacing(MouseContact(id: 3, x: 0.401, y: 0.401), anchors: rest), "Surface spacing still rejects overlapping contacts")
            tuning.tipTap.maximumDistance = 0.2
            expect(!tuning.tipTap.allowsSpacing(MouseContact(id: 3, x: 0.41, y: 0.75), anchors: rest), "Explicit maximum spacing is still respected")
        }
        // A stray fourth contact after a completed trackpad TipTap must not
        // permanently disable every repeat while the resting pair stays down.
        for betweenTaps in [false, true] {
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let rest = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.6, y: 0.5)]
            let left = MouseContact(id: 3, x: 0.2, y: 0.5, size: 0.3)
            let right = MouseContact(id: 4, x: 0.8, y: 0.5, size: 0.3)
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(rest, timestamp: 1000, settings: tuning)
            _ = trackpad.consume(rest + [left], timestamp: 1000.3, settings: tuning)
            expect(trackpad.consume(rest, timestamp: 1000.42, settings: tuning) == .tipTapTwoLeft, "Initial trackpad tap before an extra contact")
            if !betweenTaps { _ = trackpad.consume(rest + [left], timestamp: 1000.5, settings: tuning) }
            expect(trackpad.consume(rest + [left, right], timestamp: 1000.55, settings: tuning) == nil, "An extra contact cancels the interrupted stroke")
            expect(trackpad.consume(rest + [left], timestamp: 1000.6, settings: tuning) == nil, "A held tip cannot revive a cancelled stroke")
            expect(trackpad.consume(rest, timestamp: 1000.65, settings: tuning) == nil, "Returning to the resting pair emits no action")
            _ = trackpad.consume(rest + [right], timestamp: 1000.75, settings: tuning)
            expect(trackpad.consume(rest, timestamp: 1000.87, settings: tuning) == .tipTapTwoRight, "Trackpad repeat works after the extra contact lifts, without a whole-hand release")
        }
        // A tip ID replacement is an interrupted stroke, but it must not
        // poison all later taps. Click cancellation remains a full-release gate.
        for count in 1...3 {
            let gesture: MagicMouseGesture = count == 1 ? .tipTapLeft : (count == 2 ? .tipTapTwoLeft : .tipTapThreeLeft)
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [gesture: .missionControl]
            let rest = (0..<count).map { MouseContact(id: Int32($0 + 1), x: 0.4 + Double($0) * 0.1, y: 0.5) }
            let tip = MouseContact(id: 10, x: 0.2, y: 0.5, size: 0.3)
            let replacement = MouseContact(id: 11, x: 0.2, y: 0.5, size: 0.3)
            for physical in [false, true] {
                var trackpad = MagicMouseRecognizer()
                _ = trackpad.consume(rest, timestamp: 1010, settings: tuning)
                _ = trackpad.consume(rest + [tip], timestamp: 1010.3, settings: tuning)
                if physical { _ = trackpad.physicalClick(timestamp: 1010.32) }
                expect(trackpad.consume(rest + [replacement], timestamp: 1010.34, settings: tuning) == nil, "Tip identity change emits no action")
                expect(trackpad.tipTapFeedback == (physical ? "Mouse-button event cancelled the touch session. Lift all fingers, then try again." : TipTapRejection.tipChanged.rawValue), "Cancellation reason replaces stale success")
                expect(trackpad.consume(rest, timestamp: 1010.4, settings: tuning) == nil, "Cancelled tip release emits no action")
                _ = trackpad.consume(rest + [tip], timestamp: 1010.5, settings: tuning)
                expect(trackpad.consume(rest, timestamp: 1010.62, settings: tuning) == (physical ? nil : gesture), "Fresh tap recovers after ID change but never after a physical click")
            }
        }
        // Different fingers cannot stand in for the original chord after an
        // extra-contact cancellation. Moving originals must settle again.
        for changedIDs in [false, true] {
            var tuning = MagicMouseSettings(); tuning.tipTap = .trackpadDefaults
            tuning.bindings = [.tipTapTwoLeft: .missionControl]
            let rest = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.6, y: 0.5)]
            let tip = MouseContact(id: 3, x: 0.2, y: 0.5, size: 0.3)
            var trackpad = MagicMouseRecognizer()
            _ = trackpad.consume(rest, timestamp: 1020, settings: tuning)
            _ = trackpad.consume(rest + [tip], timestamp: 1020.3, settings: tuning)
            _ = trackpad.consume(rest + [tip, MouseContact(id: 4, x: 0.8, y: 0.5)], timestamp: 1020.32, settings: tuning)
            expect(trackpad.tipTapFeedback == TipTapRejection.extraContact.rawValue, "Extra-contact cancellation is reported")
            let moved = rest.map { MouseContact(id: changedIDs ? $0.id + 10 : $0.id, x: $0.x, y: 0.7) }
            _ = trackpad.consume(moved, timestamp: 1020.4, settings: tuning)
            _ = trackpad.consume(moved + [tip], timestamp: 1020.45, settings: tuning)
            expect(trackpad.consume(moved, timestamp: 1020.57, settings: tuning) == nil, "Changed or moving anchors cannot immediately revive a cancelled stroke")
            _ = trackpad.consume(moved + [tip], timestamp: 1020.8, settings: tuning)
            expect(trackpad.consume(moved, timestamp: 1020.92, settings: tuning) == (changedIDs ? nil : .tipTapTwoLeft), "Only the original anchors can settle and recover without full release")
        }
        // The trackpad's sampled button-state path must also recover, but no
        // held button, cancelled tip, or unrelated hard cancellation may fire.
        for hardCancel in [false, true] {
            var settings = MagicMouseSettings(); settings.tipTap = .trackpadDefaults
            settings.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
            let rest = [MouseContact(id: 1, x: 0.4, y: 0.5), MouseContact(id: 2, x: 0.6, y: 0.5)]
            let left = MouseContact(id: 3, x: 0.2, y: 0.5)
            let right = MouseContact(id: 4, x: 0.8, y: 0.5)
            var r = MagicMouseRecognizer()
            _ = r.consume(rest, timestamp: 1030, settings: settings)
            _ = r.consume(rest + [left], timestamp: 1030.3, settings: settings)
            _ = r.consume(rest + [left], timestamp: 1030.34, settings: settings, physicalButtonDown: true, allowsTrackpadButtonRecovery: true)
            if hardCancel { r.cancel() }
            expect(r.consume(rest, timestamp: 1030.42, settings: settings, physicalButtonDown: true, allowsTrackpadButtonRecovery: true) == nil, "A sampled held button cannot rearm TipTaps")
            expect(r.consume(rest, timestamp: 1030.45, settings: settings, allowsTrackpadButtonRecovery: true) == nil, "Releasing sampled button only rearms, never acts")
            for (index, tip) in [right, left, right, left].enumerated() {
                let time = 1030.5 + Double(index) * 0.25
                _ = r.consume(rest + [tip], timestamp: time, settings: settings, allowsTrackpadButtonRecovery: true)
                let expected: MagicMouseGesture = tip.id == left.id ? .tipTapTwoLeft : .tipTapTwoRight
                expect(r.consume(rest, timestamp: time + 0.12, settings: settings, allowsTrackpadButtonRecovery: true) == (hardCancel ? nil : expected), "Trackpad alternates after sampled button release unless hard-cancelled")
            }
        }
        // Feed the actual C bridge output into the production recognizer. Direct
        // Swift contact fixtures alone cannot detect filtering regressions.
        if CommandLine.arguments.count > 1 {
            struct Contact: Decodable { let id: Int32; let x, y, size: Double }
            struct Frame: Decodable { let time: Double; let contacts: [Contact] }
            struct Fixture: Decodable { let anchors, side: Int; let frames: [Frame] }
            let fixtures = try! JSONDecoder().decode([Fixture].self,
                from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            expect(fixtures.count == 7, "Every trackpad TipTap is covered by the real input bridge")
            for fixture in fixtures {
                let choices: [MagicMouseGesture] = fixture.anchors == 1 ? [.tipTapLeft, .tipTapRight] :
                    fixture.anchors == 2 ? [.tipTapTwoLeft, .tipTapTwoMiddle, .tipTapTwoRight] : [.tipTapThreeLeft, .tipTapThreeRight]
                let expected = choices[fixture.side]
                var trackpadSettings = MagicMouseSettings()
                trackpadSettings.tipTap = TipTapTuning()
                trackpadSettings.tipTapSpacingGeometry = .surface
                trackpadSettings.bindings = [expected: .missionControl]
                var recognizer = MagicMouseRecognizer()
                let results = fixture.frames.compactMap { frame in
                    recognizer.consume(frame.contacts.map { MouseContact(id: $0.id, x: $0.x, y: $0.y, size: $0.size) },
                        timestamp: frame.time, settings: trackpadSettings)
                }
                expect(results == [expected, expected], "Trackpad bridge must deliver two separate \(expected) taps after long rests")
            }
        }
        // A swipe's scroll reservation lasts for the rest of that native scroll:
        // through a finger lifting early and the momentum after it, and no longer.
        do {
            var r = ScrollSequenceReservation()
            let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4
            expect(r.axes(touching: .horizontal, scrollPhase: began, momentumPhase: 0, timestamp: 10) == .horizontal, "Swipe reserves its axis")
            expect(r.axes(touching: [], scrollPhase: changed, momentumPhase: 0, timestamp: 10.05) == .horizontal, "Remaining finger after a partial lift stays reserved")
            expect(r.axes(touching: [], scrollPhase: ended, momentumPhase: 0, timestamp: 10.1) == .horizontal, "Scroll end stays reserved")
            expect(r.axes(touching: [], scrollPhase: 0, momentumPhase: 1, timestamp: 10.15) == .horizontal, "Momentum start after the swipe is withheld")
            expect(r.axes(touching: [], scrollPhase: 0, momentumPhase: 2, timestamp: 10.6) == .horizontal, "Momentum is withheld for its whole run")
            expect(r.axes(touching: [], scrollPhase: 0, momentumPhase: 3, timestamp: 11.2) == .horizontal, "Momentum end is withheld")
            expect(r.axes(touching: [], scrollPhase: began, momentumPhase: 0, timestamp: 11.3).isEmpty, "The next scroll is the user's")

            var fresh = ScrollSequenceReservation()
            _ = fresh.axes(touching: .vertical, scrollPhase: began, momentumPhase: 0, timestamp: 20)
            expect(fresh.axes(touching: [], scrollPhase: began, momentumPhase: 0, timestamp: 20.2).isEmpty, "A newly begun scroll cuts a reservation short")
            var stale = ScrollSequenceReservation()
            _ = stale.axes(touching: .vertical, scrollPhase: began, momentumPhase: 0, timestamp: 30)
            expect(stale.axes(touching: [], scrollPhase: 0, momentumPhase: 2, timestamp: 32).isEmpty, "A sequence that never ends expires")
            var other = ScrollSequenceReservation()
            expect(other.axes(touching: .horizontal, scrollPhase: began, momentumPhase: 0, timestamp: 40) == .horizontal, "Horizontal swipe reserves horizontal")
            expect(!other.axes(touching: [], scrollPhase: 0, momentumPhase: 2, timestamp: 40.3).contains(.vertical), "Only the swipe's own axis is withheld")
        }
        print("PASS: \(checks) Magic Mouse recognition and normalization checks")
    }
}
