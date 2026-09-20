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
        print("PASS: \(checks) Magic Mouse recognition and normalization checks")
    }
}
