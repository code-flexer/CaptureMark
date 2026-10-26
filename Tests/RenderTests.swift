import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct RenderTests {
    static func main() {
        _ = NSApplication.shared
        let source = NSImage(size: CGSize(width: 200, height: 120), flipped: true) { _ in
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: 200, height: 120).fill()
            NSColor.red.setFill()
            CGRect(x: 0, y: 0, width: 100, height: 60).fill()
            NSColor.blue.setFill()
            CGRect(x: 0, y: 60, width: 100, height: 60).fill()
            return true
        }
        func render(_ rect: CGRect, _ annotations: [Annotation] = [], scale: CGFloat = 2) -> NSBitmapImageRep {
            let data = ImageRenderer.png(image: source, screenSize: CGSize(width: 200, height: 120), selection: rect,
                                         pixelSize: CGSize(width: 200 * scale, height: 120 * scale), annotations: annotations)
            require(data != nil, "PNG export failed")
            let rep = NSBitmapImageRep(data: data!)!
            return rep
        }
        let crop = CGRect(x: 10, y: 10, width: 80, height: 100)
        let rep = render(crop)
        require(rep.pixelsWide == 160 && rep.pixelsHigh == 200, "Retina crop dimensions")
        func rgb(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor { rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)! }
        require(rgb(rep, 20, 20).redComponent > 0.9 && rgb(rep, 20, 20).blueComponent < 0.1, "Top-left orientation")
        require(rgb(rep, 20, 180).blueComponent > 0.9 && rgb(rep, 20, 180).redComponent < 0.1, "Bottom-left orientation")
        let pen = Annotation(tool: .pen, points: [CGPoint(x: 20, y: 80), CGPoint(x: 70, y: 80)], color: .green, width: 6)
        let marked = render(crop, [pen])
        require(rgb(marked, 60, 140).greenComponent > 0.8, "Annotation maps to crop-relative pixels")
        require(rgb(marked, 60, 140).blueComponent < 0.2, "Annotation is flattened over base")
        let arrow = Annotation(tool: .arrow, points: [CGPoint(x: 120, y: 20), CGPoint(x: 180, y: 50)], color: .black, width: 4)
        let text = Annotation(tool: .text, points: [CGPoint(x: 110, y: 65)], color: .black, width: 3,
                              text: "한글 테스트", fontSize: 16, textWidth: 90)
        let words = render(CGRect(x: 100, y: 0, width: 100, height: 120), [arrow, text], scale: 1)
        var dark = 0
        for y in 66..<95 { for x in 10..<95 { if rgb(words, x, y).redComponent < 0.5 { dark += 1 } } }
        require(dark > 50, "Korean text rasterizes")
        let outside = Annotation(tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 120)], color: .green, width: 3)
        let clipped = render(crop, [outside])
        require(rgb(clipped, 60, 20).redComponent > 0.9, "Export clips annotations to selection")
        let partial = render(CGRect(x: -10, y: -10, width: 30, height: 30))
        require(partial.pixelsWide == 40 && partial.pixelsHigh == 40, "Out-of-bounds selection clamped")
        require(ImageRenderer.png(image: source, screenSize: source.size, selection: .zero, pixelSize: source.size, annotations: []) == nil,
                "Empty selection rejected")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let data = words.representation(using: .png, properties: [:])!
        require(LocalClipboard.write(png: data, to: pasteboard), "Clipboard write")
        require(pasteboard.data(forType: .png) == data, "Clipboard PNG round trip")
        require(pasteboard.types?.contains(.fileURL) == false, "Clipboard has no file reference")
        print("PASS: crop dimensions, orientation, Retina scale, annotation position, flattening, Korean text, clipping, invalid selection, private clipboard round trip")
    }
}
