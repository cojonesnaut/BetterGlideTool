import Foundation

/// A scripted touch session that shows how to perform one gesture, drawn the
/// same way as real input in the Live View: fingers land, their paths build up
/// behind them, and the finished strokes linger and fade before it repeats.
///
/// Positions are on the device's touch surface: x 0 left → 1 right, y 0 bottom
/// → 1 top, as the sensor reports them. Offsets between fingers and circle
/// radii are given in surface heights and converted with the surface's aspect,
/// so spacing and circles look the same on a narrow mouse and a wide trackpad.
struct GestureHowTo {
    struct Contact {
        let start: Double
        let end: Double
        let position: (Double) -> (x: Double, y: Double)   // 0…1 through its life
        var clicks: [Double] = []                          // absolute times of a press
        var hold = false                                    // draw a growing ring while down
    }
    struct Frame {
        var paths: [[(x: Double, y: Double)]] = []
        var dots: [(x: Double, y: Double)] = []
        var lifted: [(x: Double, y: Double)] = []      // where finished fingers were
        var rings: [(x: Double, y: Double, radius: Double, alpha: Double)] = []
        var alpha = 1.0
    }

    let contacts: [Contact]
    let cycle: Double
    static let fade = 0.6
    /// Blank time after the fade before the demonstration starts again.
    static let pause = 0.2

    init(direction: GestureDirection, fingers: Int, device: GestureDevice,
         zone: TrackpadZone = .any, speed: GestureSpeed = .normal) {
        let aspect = DeviceSurfaceShape.aspect(device)
        let center = Self.center(for: direction, device: device, zone: zone)
        func at(_ dx: Double, _ dy: Double, from c: (x: Double, y: Double) = center) -> (x: Double, y: Double) {
            (x: min(0.96, max(0.04, c.x + dx / aspect)), y: min(0.96, max(0.04, c.y + dy)))
        }
        func still(_ p: (x: Double, y: Double)) -> (Double) -> (x: Double, y: Double) { { _ in p } }
        func eased(_ u: Double) -> Double { u * u * (3 - 2 * u) }
        let cluster = Self.cluster(fingers)
        let stroke: Double = speed == .slow ? 0.6 : (speed == .fast ? 0.22 : 0.4)
        var list: [Contact] = []

        switch direction {
        case .tap, .leftTap, .rightTap, .middleTap, .aboveAppleTap, .tapTop, .tapBottom:
            list = cluster.map { Contact(start: 0.35, end: 0.5, position: still(at($0.x, $0.y))) }
        case .doubleTap:
            list = cluster.flatMap { o in [Contact(start: 0.35, end: 0.47, position: still(at(o.x, o.y))),
                                           Contact(start: 0.6, end: 0.72, position: still(at(o.x, o.y)))] }
        case .click, .middleClick, .cornerBottomLeft, .cornerBottomRight, .cornerTopLeft, .cornerTopRight:
            list = cluster.map { Contact(start: 0.35, end: 0.75, position: still(at($0.x, $0.y)), clicks: [0.45]) }
        case .forceClick:
            list = cluster.map { Contact(start: 0.35, end: 0.95, position: still(at($0.x, $0.y)), clicks: [0.45, 0.7]) }
        case .tapHold:
            list = cluster.map { Contact(start: 0.35, end: 1.45, position: still(at($0.x, $0.y)), hold: true) }
        case .swipeLeft, .swipeRight, .swipeUp, .swipeDown:
            let horizontal = direction == .swipeLeft || direction == .swipeRight
            let sign: Double = direction == .swipeRight || direction == .swipeUp ? 1 : -1
            let span = horizontal ? 0.36 * aspect : 0.42   // in surface heights
            list = cluster.map { o in
                Contact(start: 0.35, end: 0.35 + stroke + 0.05, position: { u in
                    let d = (eased(min(1, u * (stroke + 0.05) / stroke)) - 0.5) * span * sign
                    return horizontal ? at(o.x + d, o.y) : at(o.x, o.y + d)
                })
            }
        case .swipeLeftRight, .swipeUpDown:
            let horizontal = direction == .swipeLeftRight
            let span = horizontal ? 0.3 * aspect : 0.36
            list = cluster.map { o in
                Contact(start: 0.35, end: 1.75, position: { u in
                    let d = sin(u * .pi * 3) * span / 2
                    return horizontal ? at(o.x + d, o.y) : at(o.x, o.y + d)
                })
            }
        case .circleClockwise, .circleCounterClockwise:
            let radius = 0.2, turn: Double = direction == .circleClockwise ? -1 : 1
            list = [Contact(start: 0.35, end: 1.55, position: { u in
                let angle = Double.pi / 2 + turn * eased(u) * 2 * .pi
                return at(cos(angle) * radius, sin(angle) * radius)
            })]
        case .tipTapLeft, .tipTapRight:
            let tap = direction == .tipTapLeft ? -0.17 : 0.17
            list = [Contact(start: 0.25, end: 1.45, position: still(at(0, 0))),
                    Contact(start: 0.75, end: 0.88, position: still(at(tap, -0.02)))]
        case .tipTapTwoLeft, .tipTapTwoRight, .tipTapTwoMiddle:
            let anchors: [(Double, Double)] = direction == .tipTapTwoMiddle ? [(-0.14, 0), (0.14, 0)] : [(-0.06, 0), (0.1, 0)]
            let tap: (Double, Double) = direction == .tipTapTwoLeft ? (-0.22, -0.02) : (direction == .tipTapTwoRight ? (0.26, -0.02) : (0, 0.05))
            list = anchors.map { Contact(start: 0.25, end: 1.45, position: still(at($0.0, $0.1))) }
                + [Contact(start: 0.75, end: 0.88, position: still(at(tap.0, tap.1)))]
        case .tipTapThreeLeft, .tipTapThreeRight:
            let tap: (Double, Double) = direction == .tipTapThreeLeft ? (-0.27, -0.04) : (0.3, -0.04)
            list = [(-0.12, 0), (0.02, 0.03), (0.16, 0)].map { Contact(start: 0.25, end: 1.45, position: still(at($0.0, $0.1))) }
                + [Contact(start: 0.75, end: 0.88, position: still(at(tap.0, tap.1)))]
        case .tipSwipeLeftUp, .tipSwipeLeftDown, .tipSwipeLeftLeft, .tipSwipeLeftRight:
            let move: (Double, Double)
            switch direction {
            case .tipSwipeLeftUp: move = (0, 0.28)
            case .tipSwipeLeftDown: move = (0, -0.28)
            case .tipSwipeLeftLeft: move = (-0.22, 0)
            default: move = (0.18, 0)
            }
            let origin = (-0.14, direction == .tipSwipeLeftUp ? -0.12 : (direction == .tipSwipeLeftDown ? 0.12 : 0.0))
            list = [(0.04, 0.0), (0.19, 0.0)].map { Contact(start: 0.25, end: 1.5, position: still(at($0.0, $0.1))) }
                + [Contact(start: 0.7, end: 0.7 + stroke + 0.05, position: { u in
                    let k = eased(min(1, u * (stroke + 0.05) / stroke))
                    return at(origin.0 + move.0 * k, origin.1 + move.1 * k)
                })]
        }
        contacts = list
        // Loop as soon as the finished stroke has faded.
        self.cycle = (list.map(\.end).max() ?? 1) + Self.fade + Self.pause
    }

    /// Where the hand rests for this gesture: its region on the Magic Mouse,
    /// its part of the trackpad, or the rule's trackpad zone.
    static func center(for direction: GestureDirection, device: GestureDevice, zone: TrackpadZone) -> (x: Double, y: Double) {
        switch direction {
        case .leftTap: return (0.3, 0.62)
        case .rightTap: return (0.7, 0.62)
        case .middleTap, .middleClick: return (0.5, 0.62)
        case .aboveAppleTap: return (0.5, 0.28)
        case .tapTop: return (0.5, 0.78)
        case .tapBottom: return (0.5, 0.22)
        case .cornerTopLeft: return (0.1, 0.88)
        case .cornerTopRight: return (0.9, 0.88)
        case .cornerBottomLeft: return (0.1, 0.12)
        case .cornerBottomRight: return (0.9, 0.12)
        default: break
        }
        guard device == .trackpad else { return (0.5, 0.55) }
        switch zone {
        case .any: return (0.5, 0.5)
        case .topLeft: return (0.27, 0.72)
        case .topRight: return (0.73, 0.72)
        case .bottomLeft: return (0.27, 0.28)
        case .bottomRight: return (0.73, 0.28)
        case .topEdge: return (0.5, 0.82)
        case .bottomEdge: return (0.5, 0.18)
        case .leftEdge: return (0.15, 0.5)
        case .rightEdge: return (0.85, 0.5)
        }
    }

    /// A relaxed hand: fingertips on a shallow arc, in surface heights.
    static func cluster(_ fingers: Int) -> [(x: Double, y: Double)] {
        switch fingers {
        case ...1: return [(0, 0)]
        case 2: return [(-0.08, 0), (0.08, 0)]
        case 3: return [(-0.15, -0.02), (0, 0.03), (0.15, -0.02)]
        case 4: return [(-0.21, -0.05), (-0.07, 0.02), (0.07, 0.02), (0.21, -0.05)]
        default: return [(-0.21, -0.05), (-0.07, 0.02), (0.07, 0.02), (0.21, -0.05), (-0.26, -0.24)]
        }
    }

    /// The demonstration at `time` seconds into the loop.
    func frame(at time: Double) -> Frame {
        let t = time.truncatingRemainder(dividingBy: cycle)
        var frame = Frame()
        let lastEnd = contacts.map(\.end).max() ?? 0
        if t > lastEnd { frame.alpha = max(0, 1 - (t - lastEnd) / Self.fade) }
        for contact in contacts where t >= contact.start {
            let life = contact.end - contact.start
            let until = min(t, contact.end)
            var path: [(x: Double, y: Double)] = []
            var s = contact.start
            while s <= until {
                path.append(contact.position((s - contact.start) / life))
                s += 1.0 / 60
            }
            path.append(contact.position((until - contact.start) / life))
            frame.paths.append(path)
            if t >= contact.end { frame.lifted.append(contact.position(1)) }
            if t < contact.end {
                let p = contact.position((t - contact.start) / life)
                frame.dots.append(p)
                if contact.hold {
                    frame.rings.append((p.x, p.y, 8 + 10 * (t - contact.start) / life, 0.6))
                }
                for click in contact.clicks where t >= click && t - click < 0.3 {
                    let k = (t - click) / 0.3
                    frame.rings.append((p.x, p.y, 7 + 12 * k, 0.8 * (1 - k)))
                }
            }
        }
        return frame
    }
}
