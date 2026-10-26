import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func icon(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x123D42).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x174E54), ending: color(0x082C33))!.draw(in: tile, angle: -65)
    let edge = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 190, yRadius: 190)
    NSColor.white.withAlphaComponent(0.13).setStroke()
    edge.lineWidth = 3
    edge.stroke()
    // Four distinctive capture corners. Own geometry, not an SF Symbol.
    let frame = NSBezierPath()
    frame.lineWidth = 46
    frame.lineCapStyle = .round
    frame.lineJoinStyle = .round
    let left: CGFloat = 258, right: CGFloat = 710, bottom: CGFloat = 292, top: CGFloat = 744, arm: CGFloat = 108
    for (x, y, dx, dy) in [(left, top, arm, -arm), (right, top, -arm, -arm),
                           (left, bottom, arm, arm), (right, bottom, -arm, arm)] {
        frame.move(to: NSPoint(x: x + dx, y: y))
        frame.line(to: NSPoint(x: x, y: y))
        frame.line(to: NSPoint(x: x, y: y + dy))
    }
    color(0x86EFCE).setStroke()
    frame.stroke()
    // A solid diagonal marker crosses the frame, pointing at a hand-drawn mark.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 482, yBy: 342)
    transform.rotate(byDegrees: -42)
    transform.concat()
    let penShadow = NSShadow()
    penShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    penShadow.shadowBlurRadius = 18
    penShadow.shadowOffset = NSSize(width: 0, height: -9)
    penShadow.set()
    let body = NSBezierPath(roundedRect: NSRect(x: -47, y: 54, width: 94, height: 374), xRadius: 17, yRadius: 17)
    color(0xFFF6DF).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    transform.concat()
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: -47, y: 70))
    nib.line(to: NSPoint(x: 47, y: 70))
    nib.line(to: NSPoint(x: 8, y: 0))
    nib.curve(to: NSPoint(x: -8, y: 0), controlPoint1: NSPoint(x: 4, y: -8), controlPoint2: NSPoint(x: -4, y: -8))
    nib.close()
    color(0xFFF6DF).setFill()
    nib.fill()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: -17, y: 20)); tip.line(to: NSPoint(x: 17, y: 20))
    tip.line(to: NSPoint(x: 7, y: 0)); tip.line(to: NSPoint(x: -7, y: 0)); tip.close()
    color(0x153C42).setFill(); tip.fill()
    color(0xFF8D77).setFill()
    NSBezierPath(roundedRect: NSRect(x: -47, y: 370, width: 94, height: 64), xRadius: 16, yRadius: 16).fill()
    color(0x153C42).setFill()
    NSRect(x: -47, y: 359, width: 94, height: 12).fill()
    NSGraphicsContext.restoreGraphicsState()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 392, y: 244))
    mark.curve(to: NSPoint(x: 510, y: 244), controlPoint1: NSPoint(x: 425, y: 267), controlPoint2: NSPoint(x: 474, y: 219))
    mark.lineWidth = 24; mark.lineCapStyle = .round
    color(0xFF8D77).setStroke(); mark.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
for n in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let data = icon(n * scale).representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("icon_\(n)x\(n)\(suffix).png"))
    }
}
