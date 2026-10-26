import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var welcome: NSWindow?
    private var overlays: [CaptureWindow] = []
    private var hotkey: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?
    private var capturing = false
    private var generation = UUID()
    private var lastApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "CaptureMark", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        configureMenus()
        registerShortcut()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.cancelCapture() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in self?.cancelCapture() })
        if CommandLine.arguments.contains("--preview") { showPreview() }
        else { showWelcome() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if overlays.isEmpty { showWelcome() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler) }
        overlays.forEach { $0.orderOut(nil) }
    }
    private func configureMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "CaptureMark 안내", action: #selector(showWelcome), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "CaptureMark 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Brand.menuBarIcon()
        statusItem.button?.toolTip = "CaptureMark · 새 캡처 ⌘⇧2"
        let statusMenu = NSMenu()
        let capture = NSMenuItem(title: "새 캡처                         ⌘⇧2", action: #selector(startCapture), keyEquivalent: "")
        capture.target = self
        statusMenu.addItem(capture)
        let help = NSMenuItem(title: "사용 방법", action: #selector(showWelcome), keyEquivalent: "")
        help.target = self
        statusMenu.addItem(help)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "CaptureMark 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = statusMenu
    }
    private func registerShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { app.startCapture() }
            return noErr
        }, 1, &spec, pointer, &hotkeyHandler)
        let id = EventHotKeyID(signature: OSType(0x434D4152), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { statusItem.button?.toolTip = "CaptureMark · 메뉴에서 새 캡처를 선택하세요 (단축키 사용 중)" }
    }

    @objc private func showWelcome() {
        if let welcome { welcome.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CaptureMark"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        let glyph = NSImageView(image: NSApp.applicationIconImage)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.widthAnchor.constraint(equalToConstant: 64).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(glyph)
        let title = NSTextField(labelWithString: "잡고, 그리고, 복사하세요")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(title)
        let body = NSTextField(wrappingLabelWithString: "영역 드래그 → 텍스트와 표시 추가 → 완료\n완성한 이미지가 클립보드에 복사됩니다.")
        body.alignment = .center
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        stack.addArrangedSubview(body)
        let capture = NSButton(title: "캡처 시작   ⌘⇧2", target: self, action: #selector(startCapture))
        capture.bezelStyle = .rounded
        capture.bezelColor = .controlAccentColor
        capture.keyEquivalent = "\r"
        capture.controlSize = .large
        stack.addArrangedSubview(capture)
        let preview = NSButton(title: "도구 미리보기", target: self, action: #selector(showPreview))
        preview.bezelStyle = .inline
        stack.addArrangedSubview(preview)
        let privacy = NSTextField(labelWithString: "외부 연결 없음 · 자동 저장 없음")
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(privacy)
        window.contentView = stack
        window.center()
        welcome = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func startCapture() {
        guard !capturing, overlays.isEmpty else { return }
        lastApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0 }
        welcome?.orderOut(nil)
        capturing = true
        let request = UUID()
        generation = request
        Task { @MainActor in
            do {
                // Let the menu and welcome window disappear before freezing the displays.
                try await Task.sleep(nanoseconds: 180_000_000)
                guard generation == request else { return }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var frames: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false
                    config.capturesAudio = false
                    config.pixelFormat = kCVPixelFormatType_32BGRA
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard generation == request else { return }
                    frames.append((screen, image))
                }
                guard !frames.isEmpty else { throw CaptureError.noDisplay }
                capturing = false
                for (screen, image) in frames { addOverlay(screen: screen, image: image) }
                NSApp.activate(ignoringOtherApps: true)
                let point = NSEvent.mouseLocation
                (overlays.first(where: { $0.frame.contains(point) }) ?? overlays.first)?.makeKeyAndOrderFront(nil)
            } catch {
                guard generation == request else { return }
                capturing = false
                let alert = NSAlert()
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.userDeclined.rawValue {
                    alert.messageText = "화면 캡처 권한을 확인해 주세요"
                    alert.informativeText = "시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록에서 CaptureMark를 허용한 뒤 앱을 다시 실행해 주세요.\n\n이미 켜져 있다면 이전 빌드의 권한일 수 있습니다. 기존 CaptureMark 항목을 제거하고 사용자 Applications 폴더의 CaptureMark.app을 다시 추가해 주세요."
                } else {
                    alert.messageText = "화면을 캡처할 수 없습니다"
                    alert.informativeText = "다시 시도해 주세요.\n\(error.localizedDescription)"
                }
                NSApp.activate(ignoringOtherApps: true)
                showWelcome()
                if let welcome { _ = await alert.beginSheetModal(for: welcome) }
            }
        }
    }
    private func addOverlay(screen: NSScreen, image: CGImage) {
        let window = CaptureWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        let view = CaptureView(frame: CGRect(origin: .zero, size: screen.frame.size),
                               image: NSImage(cgImage: image, size: screen.frame.size),
                               pixelSize: CGSize(width: image.width, height: image.height))
        view.onCancel = { [weak self] in self?.cancelCapture() }
        view.onComplete = { [weak self] data in
            guard LocalClipboard.write(png: data) else { NSSound.beep(); return }
            self?.cancelCapture()
            self?.showCopiedFeedback()
        }
        view.onSelected = { [weak self, weak window] in
            self?.overlays.forEach { other in if other !== window { other.ignoresMouseEvents = true } }
        }
        window.contentView = view
        window.makeFirstResponder(view)
        overlays.append(window)
        window.orderFrontRegardless()
    }
    func cancelCapture(restore: Bool = true) {
        generation = UUID()
        capturing = false
        let old = overlays
        overlays.removeAll()
        old.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() }
        if restore { lastApp?.activate() }
        lastApp = nil
    }
    private func showCopiedFeedback() {
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "복사 완료")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusItem.button?.image = Brand.menuBarIcon()
        }
    }
    // A synthetic canvas lets people try the tools without granting screen access.
    @objc private func showPreview() {
        guard overlays.isEmpty, let screen = NSScreen.main else { return }
        welcome?.orderOut(nil)
        let size = screen.frame.size
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            let card = CGRect(x: size.width * 0.22, y: size.height * 0.25, width: size.width * 0.56, height: size.height * 0.5)
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20).fill()
            ("CaptureMark" as NSString).draw(at: CGPoint(x: card.minX + 40, y: card.minY + 40),
                                             withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.labelColor])
            ("영역을 드래그하고 바로 그려 보세요.\n텍스트 · 펜 · 화살표 · 도형\n\n완료하면 클립보드에 복사됩니다." as NSString)
                .draw(at: CGPoint(x: card.minX + 40, y: card.minY + 110),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 21), .foregroundColor: NSColor.secondaryLabelColor])
            return true
        }
        var rect = CGRect(origin: .zero, size: size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        addOverlay(screen: screen, image: cg)
        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKeyAndOrderFront(nil)
    }
}

private enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "캡처할 수 있는 화면을 찾지 못했습니다." }
}
