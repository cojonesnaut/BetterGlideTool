import AppKit

// DMG window background: "Drag BetterGlideTool into Applications" with an
// arrow between the two icons, and the one-line Terminal fix underneath.
//
//   swift assets/render_dmg_background.swift
//
// writes assets/dmg-background.png (640×448). build.sh copies it into the DMG
// and places the icons on the arrow's ends, so keep `appCenter`, `appsCenter`
// and `windowSize` in step with the Finder layout there. Everything sits in
// the top 420 pt, so Finder's path bar can cover the bottom without hiding it.
//
// One 1x PNG on purpose: current Finder ignores the DPI of a 1x+2x TIFF (and
// @2x files) and draws the 2x image at double size.

let windowSize = NSSize(width: 640, height: 448)
// Where the icons are drawn (top-left origin). Finder draws an icon 44 pt
// below the position it is given, so build.sh places them at y 140.
let appCenter = NSPoint(x: 170, y: 184)
let appsCenter = NSPoint(x: 470, y: 184)
let command = "xattr -cr /Applications/BetterGlideTool.app"

func hex(_ s: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = UInt32(s.dropFirst(), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, shadow: Bool = true) -> NSSize {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.18)
        s.shadowOffset = NSSize(width: 0, height: -1); s.shadowBlurRadius = 3; s.set()
    }
    (text as NSString).draw(at: NSPoint(x: (windowSize.width - size.width) / 2, y: y - size.height / 2),
                            withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return size
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(windowSize.width * scale),
                               pixelsHigh: Int(windowSize.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = windowSize
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    let cg = context.cgContext
    cg.translateBy(x: 0, y: windowSize.height * scale); cg.scaleBy(x: scale, y: -scale)
    let bounds = NSRect(origin: .zero, size: windowSize)

    // The app icon's lilac-to-violet, a shade deeper so white text reads.
    NSGradient(starting: hex("#a99bd8"), ending: hex("#7d6bb6"))!.draw(in: bounds, angle: 90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 320, y: 40), radius: 0, toCenter: NSPoint(x: 320, y: 40), radius: 360, options: [])

    _ = drawCentered("Drag BetterGlideTool into Applications",
                     font: .systemFont(ofSize: 24, weight: .bold), color: .white, y: 58)

    // Arrow between the icons (128 pt icons, so stop well short of each).
    let y = appCenter.y, start = appCenter.x + 92, end = appsCenter.x - 88
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: start, y: y)); arrow.line(to: NSPoint(x: end, y: y))
    arrow.move(to: NSPoint(x: end - 26, y: y - 26)); arrow.line(to: NSPoint(x: end, y: y))
    arrow.line(to: NSPoint(x: end - 26, y: y + 26))
    arrow.lineWidth = 11; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    glow.shadowOffset = NSSize(width: 0, height: -2); glow.shadowBlurRadius = 6; glow.set()
    NSColor.white.withAlphaComponent(0.92).setStroke(); arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()

    _ = drawCentered("Before the first launch, run in Terminal:",
                     font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.95), y: 322)
    let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let codeSize = (command as NSString).size(withAttributes: [.font: mono])
    let box = NSRect(x: (windowSize.width - codeSize.width) / 2 - 14, y: 356 - 15, width: codeSize.width + 28, height: 30)
    hex("#2a2140", 0.55).setFill(); NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
    _ = drawCentered(command, font: mono, color: .white, y: 356, shadow: false)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("dmg-background.png")
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: out)
print("wrote", out.path)
