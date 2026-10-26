import AppKit

// All coordinates are screen-local points with a top-left origin.
enum Tool: Int, CaseIterable {
    case pen, highlighter, arrow, rectangle, ellipse, text
    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }
    var label: String {
        switch self {
        case .pen: return "펜 (P)"
        case .highlighter: return "형광펜 (H)"
        case .arrow: return "화살표 (A)"
        case .rectangle: return "사각형 (R)"
        case .ellipse: return "원 (O)"
        case .text: return "텍스트 (T)"
        }
    }
}

struct Annotation {
    var tool: Tool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var fontSize: CGFloat = 24
    var textWidth: CGFloat = 300

    func draw() {
        guard let start = points.first else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let ink = tool == .highlighter ? color.withAlphaComponent(0.3) : color
        ink.setStroke()
        ink.setFill()
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = tool == .highlighter ? width * 5 : width
        let end = points.last ?? start
        switch tool {
        case .pen, .highlighter:
            if points.count < 2 || points.allSatisfy({ $0 == start }) {
                NSBezierPath(ovalIn: CGRect(x: start.x - path.lineWidth / 2, y: start.y - path.lineWidth / 2,
                                           width: path.lineWidth, height: path.lineWidth)).fill()
            } else {
                path.move(to: start)
                for point in points.dropFirst() { path.line(to: point) }
                path.stroke()
            }
        case .arrow:
            path.move(to: start)
            path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(max(12, width * 4), hypot(end.x - start.x, end.y - start.y) * 0.45)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.line(to: CGPoint(x: end.x - cos(angle + offset) * length,
                                     y: end.y - sin(angle + offset) * length))
            }
            path.stroke()
        case .rectangle, .ellipse:
            let rect = CGRect.between(start, end)
            let shape = tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            shape.lineWidth = width
            shape.lineJoinStyle = .round
            shape.stroke()
        case .text:
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            (text as NSString).draw(with: CGRect(x: start.x, y: start.y, width: textWidth, height: 10000),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                                                 .foregroundColor: color, .paragraphStyle: style])
        }
    }
}

extension CGRect {
    static func between(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

enum ImageRenderer {
    // Draw the identical image and annotation paths used by the overlay, omitting all UI.
    static func png(image: NSImage, screenSize: CGSize, selection: CGRect,
                    pixelSize: CGSize, annotations: [Annotation]) -> Data? {
        let rect = selection.intersection(CGRect(origin: .zero, size: screenSize))
        guard rect.width >= 2, rect.height >= 2, screenSize.width > 0, screenSize.height > 0 else { return nil }
        let sx = pixelSize.width / screenSize.width
        let sy = pixelSize.height / screenSize.height
        let w = Int((rect.width * sx).rounded())
        let h = Int((rect.height * sy).rounded())
        guard w > 0, h > 0, w <= 32768, h <= 32768,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let baseContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = rect.size
        let ctx = baseContext.cgContext
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / rect.width, y: -CGFloat(h) / rect.height)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ctx.clip(to: rect)
        image.draw(in: CGRect(origin: .zero, size: screenSize), from: .zero, operation: .copy,
                   fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        for annotation in annotations { annotation.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

enum LocalClipboard {
    @discardableResult static func write(png: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        return pasteboard.writeObjects([item])
    }
}
