import AppKit

/// A monochrome template lets the menu bar provide light/dark/selected tinting.
/// Constructed once, with resolution-independent drawing for Retina screens.
enum MenuBarIcon {
    static let image: NSImage = {
        // Keep the outline's visible bounds 14pt tall, matching neighboring
        // menu-bar symbols. The 20 × 18pt canvas preserves native placement.
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            guard let hand = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)),
                  let mask = NSImage(systemSymbolName: "hand.draw.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) else { return false }
            let trackpad = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 17, height: 12.2), xRadius: 2.2, yRadius: 2.2)
            NSColor.black.setStroke()
            trackpad.lineWidth = 1.8
            trackpad.stroke()
            let width: CGFloat = 14.5
            // SF Symbols include internal bottom padding. Compensate for it so
            // the visible hand, rather than its image rectangle, is centered.
            let rect = NSRect(x: 3.5, y: -0.125, width: width, height: width * hand.size.height / hand.size.width)
            // Knock out the trackpad behind the hand without a fixed-color fill.
            mask.draw(in: rect.insetBy(dx: -0.55, dy: -0.55), from: .zero,
                      operation: .destinationOut, fraction: 1)
            hand.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black]))?.draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "BetterGlideTool"
        return image
    }()
}
