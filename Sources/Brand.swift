import AppKit

enum Brand {
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath()
            frame.lineWidth = 1.7
            frame.lineCapStyle = .round
            frame.lineJoinStyle = .round
            for (x, y, dx, dy): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                (2.5, 15.5, 3.5, -3.5), (14.5, 15.5, -3.5, -3.5),
                (2.5, 3.5, 3.5, 3.5), (14.5, 3.5, -3.5, 3.5)
            ] {
                frame.move(to: NSPoint(x: x + dx, y: y))
                frame.line(to: NSPoint(x: x, y: y))
                frame.line(to: NSPoint(x: x, y: y + dy))
            }
            frame.stroke()
            let pen = NSBezierPath()
            pen.move(to: NSPoint(x: 7, y: 5.5))
            pen.line(to: NSPoint(x: 8, y: 9))
            pen.line(to: NSPoint(x: 14.5, y: 15.5))
            pen.line(to: NSPoint(x: 17, y: 13))
            pen.line(to: NSPoint(x: 10.5, y: 6.5))
            pen.close()
            pen.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CaptureMark"
        return image
    }
}
