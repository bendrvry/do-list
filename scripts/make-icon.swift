// Renders the app icon master (1024×1024 PNG). Usage: swift make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let context = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    // Soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor(white: 0, alpha: 0.28).cgColor)
    NSColor(srgbRed: 0.97, green: 0.965, blue: 0.955, alpha: 1).setFill()
    shape.fill()
    context.restoreGState()

    // Warm paper gradient.
    context.saveGState()
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.995, green: 0.993, blue: 0.985, alpha: 1),
        NSColor(srgbRed: 0.937, green: 0.929, blue: 0.914, alpha: 1),
    ])
    gradient?.draw(in: body, angle: -90)
    context.restoreGState()

    // Hairline edge.
    NSColor(white: 0, alpha: 0.08).setStroke()
    shape.lineWidth = 2
    shape.stroke()

    // The mark: a quiet ring with a checkmark.
    let ink = NSColor(srgbRed: 0.145, green: 0.145, blue: 0.157, alpha: 1)
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius: CGFloat = 228
    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = 24
    ink.setStroke()
    ring.stroke()

    let check = NSBezierPath()
    check.move(to: CGPoint(x: center.x - 104, y: center.y + 6))
    check.line(to: CGPoint(x: center.x - 30, y: center.y - 72))
    check.line(to: CGPoint(x: center.x + 112, y: center.y + 92))
    check.lineWidth = 28
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()
    return true
}

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: output))
