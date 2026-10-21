// Draws Resources/AppIcon.icns. Run from the repository root: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = size / 1024

    // Standard macOS icon grid: an 824pt rounded square centered in 1024.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(colors: [
        NSColor(srgbRed: 0.09, green: 0.16, blue: 0.29, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.45, blue: 0.53, alpha: 1),
    ])!.draw(in: shape, angle: 90)

    // Two opposing arrows: traffic going out through the tunnel and coming back.
    NSColor(white: 0.97, alpha: 1).setStroke()
    func arrow(y: CGFloat, pointingRight: Bool) {
        let left = 300 * unit, right = 724 * unit, head = 110 * unit
        let path = NSBezierPath()
        path.lineWidth = 64 * unit
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: left, y: y))
        path.line(to: NSPoint(x: right, y: y))
        let tip = pointingRight ? right : left
        let back = pointingRight ? tip - head : tip + head
        path.move(to: NSPoint(x: back, y: y + head))
        path.line(to: NSPoint(x: tip, y: y))
        path.line(to: NSPoint(x: back, y: y - head))
        path.stroke()
    }
    arrow(y: 640 * unit, pointingRight: false)
    arrow(y: 384 * unit, pointingRight: true)

    // The live badge from the menu bar icon.
    NSColor(srgbRed: 0.20, green: 0.80, blue: 0.40, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 724 * unit, y: 160 * unit, width: 150 * unit, height: 150 * unit)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print("wrote Resources/AppIcon.icns")
