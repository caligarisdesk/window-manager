// Renders Resources/AppIcon.icns: session cards standing on a shelf.
// Run: swiftc scripts/make_icon.swift -o .build/make_icon && .build/make_icon
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body centered in 1024 with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.setFill(); bodyPath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    bodyPath.addClip()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.27, blue: 0.55, alpha: 1),
                        NSColor(red: 0.36, green: 0.30, blue: 0.70, alpha: 1)])!.draw(in: body, angle: 70)

    // Shelf plank.
    let plank = CGRect(x: 170, y: 250, width: 684, height: 46)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(red: 0.96, green: 0.80, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: plank, xRadius: 14, yRadius: 14).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Three cards standing on the shelf, each with a status dot.
    let cards: [(x: CGFloat, h: CGFloat, dot: NSColor, tilt: CGFloat)] = [
        (215, 420, NSColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1), 0),
        (420, 500, NSColor(red: 0.25, green: 0.85, blue: 0.50, alpha: 1), 0),
        (625, 360, NSColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1), 0),
    ]
    for c in cards {
        ctx.saveGState()
        let r = CGRect(x: c.x, y: 296, width: 185, height: c.h)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.rotate(by: c.tilt * .pi / 180)
        let local = CGRect(origin: .zero, size: r.size)
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: local, xRadius: 26, yRadius: 26).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        c.dot.setFill()
        NSBezierPath(ovalIn: CGRect(x: 26, y: local.height - 62, width: 36, height: 36)).fill()
        // Text lines.
        NSColor(white: 0.82, alpha: 1).setFill()
        for (i, w) in [CGFloat(120), 95, 130, 80].enumerated() {
            let y = local.height - 110 - CGFloat(i) * 40
            if y < 30 { break }
            NSBezierPath(roundedRect: CGRect(x: 26, y: y, width: w, height: 16), xRadius: 8, yRadius: 8).fill()
        }
        ctx.restoreGState()
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = ".build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: ".build/AppIcon-preview.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
