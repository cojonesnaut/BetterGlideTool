import AppKit

// Reproducible native-symbol artwork. The sRGB violet stops are sampled from
// https://macosicons.com/?icon=Z6DW2YmoxD (background only; no reference artwork).
// The flattened ICNS is the compatibility icon. Separate, unmasked 1024px
// foreground/background layers are also exported for Apple's Icon Composer.
func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
}
let topColor = color(0xA28AF5)
let bottomColor = color(0x9871F7)

func render(size: Int, layer: String = "composite") -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let nativeLayer = layer != "composite"
    let rect = nativeLayer ? CGRect(x: 0, y: 0, width: 1024, height: 1024)
        : CGRect(x: 100, y: 100, width: 824, height: 824)
    let background = NSBezierPath(roundedRect: rect, xRadius: 184, yRadius: 184)
    if layer != "foreground" {
        if !nativeLayer {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18,
                              color: NSColor.black.withAlphaComponent(0.22).cgColor)
            bottomColor.setFill()
            background.fill()
            context.restoreGState()
        }
        context.saveGState()
        if !nativeLayer { background.addClip() }
        NSGradient(starting: bottomColor, ending: topColor)!.draw(in: rect, angle: 90)
        if !nativeLayer {
            // Static compatibility artwork; the native layered icon must let
            // Icon Composer supply its own dynamic lighting instead.
            let highlight = NSGradient(starting: NSColor.white.withAlphaComponent(0.14),
                                       ending: NSColor.white.withAlphaComponent(0))!
            highlight.draw(fromCenter: NSPoint(x: 510, y: 1000), radius: 0,
                           toCenter: NSPoint(x: 510, y: 1000), radius: 830, options: [])
            NSColor.white.withAlphaComponent(0.30).setStroke()
            background.lineWidth = 3
            background.stroke()
        }
        context.restoreGState()
    }
    if layer != "background" {
        let symbol = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 512, weight: .regular))!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
        // Same glyph placement for compatibility and future layered builds.
        let width: CGFloat = 556
        let height = width * symbol.size.height / symbol.size.width
        let glyphRect = CGRect(x: (1024 - width) / 2, y: (1024 - height) / 2 + 8, width: width, height: height)
        context.saveGState()
        if !nativeLayer {
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 10,
                              color: color(0x49228C).withAlphaComponent(0.24).cgColor)
        }
        symbol.draw(in: glyphRect)
        context.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "preview"
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
func write(_ size: Int, _ name: String, layer: String = "composite") throws {
    try render(size: size, layer: layer).write(to: outDir.appendingPathComponent(name), options: .atomic)
}
if mode == "iconset" {
    for size in [16, 32, 128, 256, 512] {
        try write(size, "icon_\(size)x\(size).png")
        try write(size * 2, "icon_\(size)x\(size)@2x.png")
    }
} else if mode == "icns" {
    // ICNS supports PNG payloads directly. Write the standard Retina and 1x
    // chunks without depending on iconutil's installed image-conversion service.
    func chunk(_ type: String, _ payload: Data) -> Data {
        var length = UInt32(payload.count + 8).bigEndian
        var data = Data(type.utf8)
        data.append(Data(bytes: &length, count: 4))
        data.append(payload)
        return data
    }
    let entries: [(String, Int)] = [
        ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024)
    ]
    var payload = Data()
    for (type, size) in entries { payload.append(chunk(type, render(size: size))) }
    try chunk("icns", payload).write(to: outDir.appendingPathComponent("AppIcon.icns"), options: .atomic)
} else if mode == "layers" {
    try write(1024, "Hand.png", layer: "foreground")
    try write(1024, "Background.png", layer: "background")
} else {
    try write(256, "preview.png")
    try write(1024, "icon_source.png")
}
print("Icon artwork written to \(outDir.path)")
