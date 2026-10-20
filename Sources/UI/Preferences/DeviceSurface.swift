import SwiftUI

/// The touch surface of each device, seen from above: the Input Monitoring
/// screens draw it, and the Live View demonstrates within its proportions. Contact coordinates are normalised to the
/// sensor, so they map straight onto the surface's bounding box.
struct DeviceSurfaceShape: Shape {
    let device: GestureDevice

    /// Width over height of the touch surface: a Magic Mouse is a long oval,
    /// a MacBook trackpad a wide rounded rectangle.
    static func aspect(_ device: GestureDevice) -> CGFloat { device == .magicMouse ? 0.58 : 1.55 }

    /// The largest surface of this device's proportions that fits `size`, centred.
    static func fitted(_ device: GestureDevice, in size: CGSize, inset: CGFloat = 0) -> CGRect {
        let available = CGSize(width: max(1, size.width - inset * 2), height: max(1, size.height - inset * 2))
        let aspect = Self.aspect(device)
        let width = min(available.width, available.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    func path(in rect: CGRect) -> Path {
        guard device == .magicMouse else {
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.09, style: .continuous)
        }
        // A Magic Mouse's top: an oval a little narrower at the front (top).
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w / 2, y: y))
        path.addCurve(to: CGPoint(x: x + w, y: y + h * 0.42),
                      control1: CGPoint(x: x + w * 0.86, y: y), control2: CGPoint(x: x + w, y: y + h * 0.18))
        path.addCurve(to: CGPoint(x: x + w / 2, y: y + h),
                      control1: CGPoint(x: x + w, y: y + h * 0.76), control2: CGPoint(x: x + w * 0.90, y: y + h))
        path.addCurve(to: CGPoint(x: x, y: y + h * 0.42),
                      control1: CGPoint(x: x + w * 0.10, y: y + h), control2: CGPoint(x: x, y: y + h * 0.76))
        path.addCurve(to: CGPoint(x: x + w / 2, y: y),
                      control1: CGPoint(x: x, y: y + h * 0.18), control2: CGPoint(x: x + w * 0.14, y: y))
        path.closeSubpath()
        return path
    }
}

/// The Live View's drawing: a looping demonstration of how to perform the
/// gesture — fingers land as dots, each finger's path builds up behind it, and
/// the finished strokes linger with a mark where each finger lifted, then fade.
/// It never shows real input; Input Monitoring does that.
struct GestureHowToLayer: View {
    let device: GestureDevice
    let demo: GestureHowTo
    var body: some View {
        // Always animated, even with Reduce Motion on: the motion is the
        // demonstration, as in BetterTouchTool, and it plays only in this box.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                draw(demo.frame(at: timeline.date.timeIntervalSinceReferenceDate), in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ frame: GestureHowTo.Frame, in context: inout GraphicsContext, size: CGSize) {
        let surface = DeviceSurfaceShape.fitted(device, in: size, inset: 10)
        func point(_ p: (x: Double, y: Double)) -> CGPoint {
            CGPoint(x: surface.minX + min(1, max(0, p.x)) * surface.width,
                    y: surface.minY + (1 - min(1, max(0, p.y))) * surface.height)
        }
        let accent = Color.accentColor
        for path in frame.paths where path.count > 1 {
            var line = Path()
            line.move(to: point(path[0]))
            for p in path.dropFirst() { line.addLine(to: point(p)) }
            context.stroke(line, with: .color(accent.opacity(0.32 * frame.alpha)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        for ring in frame.rings {
            let c = point((ring.x, ring.y))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - ring.radius, y: c.y - ring.radius, width: ring.radius * 2, height: ring.radius * 2)),
                           with: .color(accent.opacity(ring.alpha * frame.alpha)), lineWidth: 1.5)
        }
        for spot in frame.lifted {
            let c = point(spot)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13)),
                         with: .color(accent.opacity(0.3 * frame.alpha)))
        }
        for dot in frame.dots {
            let c = point(dot)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13)), with: .color(accent))
        }
    }
}
