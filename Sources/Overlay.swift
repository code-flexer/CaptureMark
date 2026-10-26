import AppKit

final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let canvas = contentView as? CaptureView {
            if event.keyCode == 36 { canvas.finish(); return true }
            if !(firstResponder is NSTextView) {
                if event.keyCode == 8 { canvas.finish(); return true }
                if event.keyCode == 6 {
                    event.modifierFlags.contains(.shift) ? canvas.redoAnnotation() : canvas.undoAnnotation()
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class CaptureView: NSView, NSTextViewDelegate {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let image: NSImage
    let pixelSize: CGSize
    var onCancel: (() -> Void)?
    var onComplete: ((Data) -> Void)?
    var onSelected: (() -> Void)?
    private(set) var selection: CGRect?
    private(set) var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var tool: Tool = .pen
    private var color: NSColor = .systemRed
    private var strokeWidth: CGFloat = 3
    private var fontSize: CGFloat = 24
    private var textEditor: NSTextView?
    private var textOrigin: CGPoint?
    private var toolbar: NSVisualEffectView!
    private var toolButtons: [NSButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var strokeSettings: NSView?
    private var textSettings: NSView?
    private var hint: NSTextField!
    private var dimensionLabel: NSTextField!
    private var track: NSTrackingArea?

    init(frame: CGRect, image: NSImage, pixelSize: CGSize) {
        self.image = image
        self.pixelSize = pixelSize
        super.init(frame: frame)
        buildToolbar()
        hint = NSTextField(labelWithString: "영역을 드래그하세요   ·   Esc 취소")
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.alignment = .center
        hint.textColor = .labelColor
        hint.drawsBackground = true
        hint.backgroundColor = .windowBackgroundColor
        hint.wantsLayer = true
        hint.layer?.cornerRadius = 10
        hint.layer?.masksToBounds = true
        addSubview(hint)
        dimensionLabel = NSTextField(labelWithString: "")
        dimensionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        dimensionLabel.textColor = .white
        dimensionLabel.drawsBackground = true
        dimensionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        dimensionLabel.isHidden = true
        addSubview(dimensionLabel)
        setAccessibilityLabel("캡처 영역 선택 및 그리기")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        hint.frame = CGRect(x: max(12, (bounds.width - 380) / 2), y: 55, width: min(380, bounds.width - 24), height: 34)
        positionToolbar()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let track { removeTrackingArea(track) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        track = area
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: selection == nil ? .crosshair : (tool == .text ? .iBeam : .crosshair))
        if !toolbar.isHidden { addCursorRect(toolbar.frame, cursor: .arrow) }
    }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let mask = NSBezierPath(rect: bounds)
        if let selection { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        mask.fill()
        if let rect = selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            for annotation in annotations { annotation.draw() }
            draft?.draw()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1
            border.stroke()
            NSColor.controlAccentColor.setStroke()
            let accent = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
            accent.lineWidth = 1
            accent.stroke()
            for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6),
                             xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if selection == nil {
            dragStart = point
            return
        }
        guard let rect = selection, rect.contains(point) else { return }
        if tool == .text { beginText(at: point); return }
        dragStart = point
        draft = Annotation(tool: tool, points: [point], color: color, width: strokeWidth)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var point = convert(event.locationInWindow, from: nil)
        if draft == nil {
            point = clamp(point, to: bounds)
            selection = CGRect.between(start, point)
            dimensionLabel.isHidden = false
            if let selection {
                dimensionLabel.stringValue = " \(Int(selection.width.rounded())) × \(Int(selection.height.rounded())) "
                dimensionLabel.sizeToFit()
                dimensionLabel.frame.origin = CGPoint(x: min(bounds.maxX - dimensionLabel.frame.width - 8, selection.minX),
                                                       y: max(8, selection.minY - 22))
            }
        } else if let rect = selection {
            point = clamp(point, to: rect)
            if event.modifierFlags.contains(.shift), tool == .rectangle || tool == .ellipse {
                let delta = max(abs(point.x - start.x), abs(point.y - start.y))
                point = clamp(CGPoint(x: start.x + (point.x < start.x ? -delta : delta),
                                      y: start.y + (point.y < start.y ? -delta : delta)), to: rect)
            } else if event.modifierFlags.contains(.shift), tool == .arrow {
                let angle = (atan2(point.y - start.y, point.x - start.x) / (.pi / 4)).rounded() * (.pi / 4)
                let length = hypot(point.x - start.x, point.y - start.y)
                point = clamp(CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length), to: rect)
            }
            if tool == .pen || tool == .highlighter { draft?.points.append(point) }
            else { draft?.points = [start, point] }
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let draft {
            annotations.append(draft)
            self.draft = nil
            redoStack.removeAll()
            updateButtons()
        } else if dragStart != nil {
            guard let rect = selection, rect.width >= 4, rect.height >= 4 else {
                selection = nil
                dimensionLabel.isHidden = true
                needsDisplay = true
                return
            }
            hint.isHidden = true
            dimensionLabel.isHidden = true
            toolbar.isHidden = false
            positionToolbar()
            onSelected?()
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        if event.keyCode == 53 { onCancel?(); return }
        if command && (event.keyCode == 36 || event.charactersIgnoringModifiers?.lowercased() == "c") { finish(); return }
        if command && event.charactersIgnoringModifiers?.lowercased() == "z" {
            event.modifierFlags.contains(.shift) ? redoAnnotation() : undoAnnotation()
            return
        }
        guard !command, !event.modifierFlags.contains(.control), let letter = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event); return
        }
        let map: [String: Tool] = ["p": .pen, "h": .highlighter, "a": .arrow, "r": .rectangle, "o": .ellipse, "t": .text]
        if let next = map[letter] { setTool(next) }
        else if event.keyCode == 36 { finish() }
        else { super.keyDown(with: event) }
    }

    private func beginText(at point: CGPoint) {
        guard let selection else { return }
        let available = selection.maxX - point.x
        guard available >= 12, selection.maxY - point.y >= 12 else { return }
        let editor = NSTextView(frame: CGRect(x: point.x, y: point.y, width: available,
                                             height: min(max(fontSize * 2, 42), selection.maxY - point.y)))
        editor.font = .systemFont(ofSize: fontSize, weight: .semibold)
        editor.textColor = color
        editor.insertionPointColor = color
        editor.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.9)
        editor.drawsBackground = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.maxSize = NSSize(width: available, height: selection.maxY - point.y)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: available, height: selection.maxY - point.y)
        editor.delegate = self
        editor.wantsLayer = true
        editor.layer?.borderWidth = 1
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.setAccessibilityLabel("추가할 텍스트")
        textOrigin = point
        textEditor = editor
        addSubview(editor, positioned: .below, relativeTo: toolbar)
        window?.makeFirstResponder(editor)
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textEditor?.removeFromSuperview()
            textEditor = nil
            textOrigin = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
    private func commitText() {
        guard let editor = textEditor, let origin = textOrigin else { return }
        // Finish input method composition before reading Korean/CJK text.
        editor.unmarkText()
        if !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.append(Annotation(tool: .text, points: [origin], color: editor.textColor ?? color,
                                          width: strokeWidth, text: editor.string,
                                          fontSize: editor.font?.pointSize ?? fontSize, textWidth: editor.frame.width))
            redoStack.removeAll()
        }
        editor.removeFromSuperview()
        textEditor = nil
        textOrigin = nil
        window?.makeFirstResponder(self)
        updateButtons()
        needsDisplay = true
    }

    @objc func finish() {
        commitText()
        guard let selection else { return }
        guard let data = ImageRenderer.png(image: image, screenSize: bounds.size, selection: selection,
                                           pixelSize: pixelSize, annotations: annotations) else {
            let alert = NSAlert()
            alert.messageText = "이미지를 만들 수 없습니다"
            alert.informativeText = "선택 영역을 작게 잡아 다시 시도해 주세요."
            alert.runModal()
            return
        }
        onComplete?(data)
    }
    @objc private func cancel() { onCancel?() }
    @objc private func reselect() {
        commitText()
        selection = nil
        annotations.removeAll()
        redoStack.removeAll()
        toolbar.isHidden = true
        hint.isHidden = false
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        updateButtons()
    }
    @objc func undoAnnotation() {
        commitText()
        if let last = annotations.popLast() { redoStack.append(last) }
        updateButtons()
        needsDisplay = true
    }
    @objc func redoAnnotation() {
        if let last = redoStack.popLast() { annotations.append(last) }
        updateButtons()
        needsDisplay = true
    }
    @objc private func toolChanged(_ sender: NSButton) { if let value = Tool(rawValue: sender.tag) { setTool(value) } }
    private func setTool(_ value: Tool) {
        commitText()
        tool = value
        updateButtons()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
    }
    @objc private func colorChanged(_ sender: NSPopUpButton) {
        color = [NSColor.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black][sender.indexOfSelectedItem]
        textEditor?.textColor = color
    }
    @objc private func widthChanged(_ sender: NSPopUpButton) {
        strokeWidth = CGFloat([2, 3, 5, 8][sender.indexOfSelectedItem])
    }
    @objc private func fontChanged(_ sender: NSPopUpButton) {
        fontSize = CGFloat([16, 20, 24, 32, 40, 56][sender.indexOfSelectedItem])
        textEditor?.font = .systemFont(ofSize: fontSize, weight: .semibold)
    }
    private func updateButtons() {
        strokeSettings?.isHidden = tool == .text
        textSettings?.isHidden = tool != .text
        for button in toolButtons {
            let selected = button.tag == tool.rawValue
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .controlAccentColor : .labelColor
        }
        undoButton?.isEnabled = !annotations.isEmpty || textEditor != nil
        redoButton?.isEnabled = !redoStack.isEmpty
    }
    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }
    private func iconButton(_ symbol: String, _ label: String, _ action: Selector, width: CGFloat = 32) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }
    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return view
    }
    private func buildToolbar() {
        toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 14
        toolbar.layer?.masksToBounds = true
        toolbar.isHidden = true
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        for tool in Tool.allCases {
            let button = iconButton(tool.symbol, tool.label, #selector(toolChanged(_:)))
            button.tag = tool.rawValue
            button.setButtonType(.toggle)
            toolButtons.append(button)
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(separator())
        let well = NSPopUpButton()
        well.addItems(withTitles: ["빨강", "노랑", "초록", "파랑", "흰색", "검정"])
        let palette: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]
        for (index, item) in well.itemArray.enumerated() {
            item.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                palette[index].setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                NSColor.separatorColor.setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
                return true
            }
        }
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.toolTip = "그리기 색상"
        well.setAccessibilityLabel("그리기 색상")
        stack.addArrangedSubview(well)
        let width = NSPopUpButton()
        width.addItems(withTitles: ["2 pt", "3 pt", "5 pt", "8 pt"])
        width.selectItem(at: 1)
        width.target = self
        width.action = #selector(widthChanged(_:))
        width.toolTip = "선 굵기"
        width.setAccessibilityLabel("선 굵기")
        let size = NSPopUpButton()
        size.addItems(withTitles: ["16", "20", "24", "32", "40", "56"])
        size.selectItem(at: 2)
        size.target = self
        size.action = #selector(fontChanged(_:))
        size.toolTip = "글자 크기"
        size.setAccessibilityLabel("글자 크기")
        let settingsSlot = NSView()
        settingsSlot.widthAnchor.constraint(equalToConstant: 150).isActive = true
        settingsSlot.heightAnchor.constraint(equalToConstant: 32).isActive = true
        func settingsGroup(_ title: String, _ control: NSPopUpButton) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            let group = NSStackView(views: [label, control])
            group.spacing = 6
            group.alignment = .centerY
            group.translatesAutoresizingMaskIntoConstraints = false
            settingsSlot.addSubview(group)
            NSLayoutConstraint.activate([
                group.centerXAnchor.constraint(equalTo: settingsSlot.centerXAnchor),
                group.centerYAnchor.constraint(equalTo: settingsSlot.centerYAnchor)
            ])
            return group
        }
        strokeSettings = settingsGroup("선 굵기", width)
        textSettings = settingsGroup("글자 크기", size)
        stack.addArrangedSubview(settingsSlot)
        stack.addArrangedSubview(separator())
        undoButton = iconButton("arrow.uturn.backward", "실행 취소 (⌘Z)", #selector(undoAnnotation))
        redoButton = iconButton("arrow.uturn.forward", "다시 실행 (⌘⇧Z)", #selector(redoAnnotation))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        stack.addArrangedSubview(iconButton("selection.pin.in.out", "영역 다시 선택", #selector(reselect)))
        stack.addArrangedSubview(iconButton("xmark", "취소 (Esc)", #selector(cancel)))
        let done = NSButton(title: "완료", image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!, target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.bezelColor = .controlAccentColor
        done.contentTintColor = .white
        done.heightAnchor.constraint(equalToConstant: 32).isActive = true
        done.toolTip = "이미지를 클립보드에 복사 (⌘↩)"
        done.setAccessibilityLabel("완료: 이미지를 클립보드에 복사")
        stack.addArrangedSubview(done)
        toolbar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
                                     stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: toolbar.topAnchor),
                                     stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)])
        addSubview(toolbar)
        toolbar.setFrameSize(stack.fittingSize)
        updateButtons()
    }
    private func positionToolbar() {
        guard let selection, !toolbar.isHidden else { return }
        let size = toolbar.fittingSize
        let safeTop: CGFloat = 40
        let y: CGFloat
        if selection.minY - size.height - 12 >= safeTop { y = selection.minY - size.height - 12 }
        else if selection.maxY + size.height + 12 < bounds.maxY - 12 { y = selection.maxY + 12 }
        else { y = min(max(safeTop, selection.minY + 12), bounds.height - size.height - 12) }
        toolbar.frame = CGRect(x: max(12, min(selection.maxX - size.width, bounds.width - size.width - 12)),
                               y: y, width: size.width, height: size.height)
    }
}
