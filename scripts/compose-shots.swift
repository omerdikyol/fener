// Composes README images from raw panel captures (screencapture -o -l <window> of the panel).
//   swift scripts/compose-shots.swift banner <panel.png> <out.png>
//   swift scripts/compose-shots.swift card <out.png> <panel.png> [<panel.png> …]   (stacked)
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func render(_ w: Int, _ h: Int, to path: String, draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    g.cgContext.translateBy(x: 0, y: CGFloat(h)); g.cgContext.scaleBy(x: 1, y: -1)
    draw(NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(w)x\(h)")
}

/// Dark backdrop with soft color light, clipped to a rounded rectangle.
func backdrop(_ r: NSRect) {
    NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40).addClip()
    hex(0x0f1018).setFill(); r.fill()
    let blobs: [(CGFloat, CGFloat, UInt32, CGFloat, CGFloat)] = [
        (0.12, 0.05, 0x7aa2f7, 0.38, 0.75), (0.92, 0.25, 0xbb9af7, 0.30, 0.6), (0.55, 1.05, 0xff9e64, 0.16, 0.6),
    ]
    for (x, y, c, a, rad) in blobs {
        let p = NSPoint(x: r.width * x, y: r.height * y)
        NSGradient(colors: [hex(c, a), hex(c, 0)])!.draw(fromCenter: p, radius: 0, toCenter: p, radius: max(r.width, r.height) * rad, options: [])
    }
}

func panel(_ img: NSImage, at origin: NSPoint) {
    let rect = NSRect(origin: origin, size: img.size)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    hex(0x1a1b26).setFill(); rect.insetBy(dx: 2, dy: 2).fill()   // shadow caster under the slightly transparent panel
    NSGraphicsContext.restoreGraphicsState()
    img.draw(in: rect)
}

/// Pixel-sized image (captures are 2x; drawn 1 pixel per point here).
func load(_ path: String) -> NSImage {
    let rep = NSImageRep(contentsOfFile: path)!
    let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    img.addRepresentation(rep)
    return img
}

let a = CommandLine.arguments
switch a[1] {
case "banner":
    let raw = load(a[2]), scale: CGFloat = 1.0
    let shot = NSImage(size: NSSize(width: raw.size.width * scale, height: raw.size.height * scale))
    shot.lockFocus(); raw.draw(in: NSRect(origin: .zero, size: shot.size)); shot.unlockFocus()
    let W = 2560, H = max(1280, Int(shot.size.height) + 320)
    render(W, H, to: a[3]) { r in
        backdrop(r)
        let px = CGFloat(W) - shot.size.width - 170, py = (CGFloat(H) - shot.size.height) / 2
        panel(shot, at: NSPoint(x: px, y: py))
        let icon = load(CommandLine.arguments.count > 4 ? a[4] : "assets/icon-1024.png")
        let left: CGFloat = 170, iconSize: CGFloat = 240
        let top = CGFloat(H) / 2 - 330
        icon.draw(in: NSRect(x: left - 30, y: top, width: iconSize, height: iconSize))
        let name = NSAttributedString(string: "fener", attributes: [
            .font: NSFont(name: "JetBrainsMonoNF-Bold", size: 170) ?? NSFont.monospacedSystemFont(ofSize: 170, weight: .bold),
            .foregroundColor: hex(0xc0caf5)])
        name.draw(at: NSPoint(x: left, y: top + iconSize + 10))
        let para = NSMutableParagraphStyle(); para.lineSpacing = 10
        let tag = NSAttributedString(string: "The keyboard launcher for macOS\nyou configure with text files.", attributes: [
            .font: NSFont.systemFont(ofSize: 56, weight: .medium), .foregroundColor: hex(0xa9b1d6), .paragraphStyle: para])
        tag.draw(at: NSPoint(x: left, y: top + iconSize + 230))
    }
case "card":
    let shots = a[3...].map(load)
    let gap: CGFloat = 56, pad: CGFloat = 120
    let w = Int((shots.map(\.size.width).max() ?? 0) + 2 * pad)
    let h = Int(shots.map(\.size.height).reduce(0, +) + gap * CGFloat(shots.count - 1) + 2 * pad)
    render(w, h, to: a[2]) { r in
        backdrop(r)
        var y = pad
        for s in shots {
            panel(s, at: NSPoint(x: (r.width - s.size.width) / 2, y: y))
            y += s.size.height + gap
        }
    }
default: fatalError("banner | card")
}
