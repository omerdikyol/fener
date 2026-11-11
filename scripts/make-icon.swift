// Draws fener's app icon (a lantern) and writes assets/icon-1024.png.
// Run: swift scripts/make-icon.swift   (then scripts/make-icns.sh builds AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }

    // macOS icon grid: an 824 pt rounded square centered in 1024, with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    hex(0x16161e).setFill(); squircle.fill()
    ctx.restoreGState()
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [hex(0x2a2e48), hex(0x1a1b26), hex(0x13131c)])!.draw(in: body, angle: 90)   // flipped: 90 runs top to bottom

    // Warm glow behind the lantern.
    let glowCenter = NSPoint(x: 512, y: 560)
    NSGradient(colors: [hex(0xff9e64, 0.55), hex(0xe0af68, 0.18), hex(0xe0af68, 0)])!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 400, options: [])

    let frame = hex(0xc0caf5)
    // Handle.
    let ring = NSBezierPath()
    ring.appendArc(withCenter: NSPoint(x: 512, y: 300), radius: 62, startAngle: 200, endAngle: 340, clockwise: false)
    ring.lineWidth = 26; ring.lineCapStyle = .round
    frame.setStroke(); ring.stroke()
    // Cap.
    let cap = NSBezierPath()
    cap.move(to: NSPoint(x: 440, y: 330)); cap.line(to: NSPoint(x: 584, y: 330))
    cap.line(to: NSPoint(x: 668, y: 400)); cap.line(to: NSPoint(x: 356, y: 400)); cap.close()
    frame.setFill(); cap.fill()
    // Glass, lit from inside.
    let glass = NSBezierPath(roundedRect: NSRect(x: 384, y: 400, width: 256, height: 300), xRadius: 34, yRadius: 34)
    NSGradient(colors: [hex(0xfff1cf), hex(0xffc777), hex(0xff9e64)])!
        .draw(in: glass, relativeCenterPosition: NSPoint(x: 0, y: 0.15))
    // Frame bars behind the flame.
    for x in [469.0, 555.0] {
        let bar = NSBezierPath(); bar.move(to: NSPoint(x: x, y: 404)); bar.line(to: NSPoint(x: x, y: 696))
        bar.lineWidth = 10; hex(0xc0caf5, 0.45).setStroke(); bar.stroke()
    }
    // Flame.
    let flame = NSBezierPath()
    flame.move(to: NSPoint(x: 512, y: 470))
    flame.curve(to: NSPoint(x: 512, y: 640), controlPoint1: NSPoint(x: 590, y: 560), controlPoint2: NSPoint(x: 580, y: 640))
    flame.curve(to: NSPoint(x: 512, y: 470), controlPoint1: NSPoint(x: 444, y: 640), controlPoint2: NSPoint(x: 434, y: 560))
    hex(0xffffff, 0.95).setFill(); flame.fill()
    glass.lineWidth = 24; frame.setStroke(); glass.stroke()
    // Base.
    let base = NSBezierPath(roundedRect: NSRect(x: 346, y: 700, width: 332, height: 56), xRadius: 18, yRadius: 18)
    frame.setFill(); base.fill()
    ctx.restoreGState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
