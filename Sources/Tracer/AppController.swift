import AppKit
import TracerCore

@MainActor
final class AppController: NSObject {
    private(set) var session = Session()
    private let hotkeys = HotkeyCenter()
    let overlays = OverlayManager()
    private let menuBar = MenuBarController()
    let dockState = DockState()
    lazy var dock = DockPanel(state: dockState)
    let text = TextEntryController()
    let output = OutputController()
    var capturer: ScreenCapturing = ScreenCapturer()
    var format: ImageFormat = .png
    var saveFolder = OutputController.defaultFolder
    private(set) var lastSavedURL: URL?
    private(set) var frames: [CGDirectDisplayID: FrozenFrame] = [:]
    private var previousApp: NSRunningApplication?
    private var strokeOrder: [InkView] = []
    private(set) var tool: Tool = .pen
    private(set) var color = InkPalette.presets[0]
    private var width: Double?
    private var fadeDelay = FadeSetting.defaultDelay
    private(set) var hotkeyWarnings: [String] = []

    private enum HotkeyID { static let pen: UInt32 = 1, capture: UInt32 = 2 }

    override init() {
        super.init()
        overlays.configureView = { [weak self] ink, capture in self?.configure(ink, capture) }
        menuBar.onDraw = { [weak self] in self?.send(.penHotkey) }
        menuBar.onCapture = { [weak self] in self?.requestCapture() }
        dockState.onCommand = { [weak self] in self?.send(.command($0)) }
        dockState.onColor = { [weak self] in self?.setColor($0) }
        dockState.onWidth = { [weak self] in self?.setWidth($0) }
        dockState.onMoreColors = { [weak self] in self?.showColorPanel() }
        text.onBegan = { [weak self] in self?.send(.textEditingBegan) }
        text.onEnded = { [weak self] in self?.send(.textEditingEnded) }
        registerHotkeys()
    }

    private func configure(_ ink: InkView, _ capture: CaptureView) {
        ink.onStrokeEnded = { [weak self] in self?.strokeOrder.append($0) }
        ink.onTextClick = { [weak self] v, p in
            guard let self else { return }
            text.begin(at: p, in: v, style: currentStyle)
        }
        capture.onSelectionChanged = { [weak self] in self?.selectionChanged(in: $0) }
        applyStyle(to: ink)
    }

    private func registerHotkeys() {
        var warnings: [String] = []
        if !hotkeys.register(.defaultPen, id: HotkeyID.pen, handler: { [weak self] in self?.send(.penHotkey) }) {
            warnings.append("Draw hotkey \(Hotkey.defaultPen.displayString) unavailable")
        }
        if !hotkeys.register(.defaultCapture, id: HotkeyID.capture, handler: { [weak self] in self?.requestCapture() }) {
            warnings.append("Capture hotkey \(Hotkey.defaultCapture.displayString) unavailable")
        }
        hotkeyWarnings = warnings
        menuBar.setWarnings(warnings)
    }

    func send(_ event: SessionEvent) {
        for effect in session.handle(event) { perform(effect) }
        dockState.tool = session.tool
        dockState.mode = session.mode
    }

    func requestCapture() {
        guard session.mode != .capturing else { return }
        guard capturer.hasPermission else { showPermissionAlert(); return }
        send(.captureHotkey)
    }

    private func handleSessionKey(_ key: SessionKey) {
        if key == .escape { send(.escape); return }
        if let c = command(for: key, mode: session.mode, isEditingText: session.isEditingText) {
            send(.command(c))
        }
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .showOverlays(let interactive):
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            overlays.show(interactive: interactive)
            enterLiveChrome(session.mode == .drawing)
            if session.mode == .drawing, let screen = screenUnderPointer { dock.slideIn(onRightEdgeOf: screen) }
        case .hideOverlays:
            text.cancel()
            dock.slideOut()
            NSColorPanel.shared.orderOut(nil)
            overlays.inkViews.values.forEach { $0.showsCursorRing = false; $0.setPointer(nil) }
            overlays.captureViews.values.forEach { $0.reset() }
            overlays.frozenViews.values.forEach { $0.frame_ = nil }
            frames = [:]
            overlays.hide()
        case .clearInk, .clearAll:
            overlays.inkViews.values.forEach { $0.clear() }
            strokeOrder.removeAll()
        case .setFadeMode(let mode):
            if mode == .frozen { overlays.inkViews.values.forEach { $0.model.prune(at: InkView.now) } }
            overlays.inkViews.values.forEach { $0.model.mode = mode }
        case .freezeScreens:
            freeze()
        case .registerSessionKeys(let capture):
            hotkeys.registerSessionKeys(capture: capture) { [weak self] in self?.handleSessionKey($0) }
        case .unregisterSessionKeys:
            hotkeys.unregisterSessionKeys()
        case .selectTool(let t):
            if text.isEditing { text.commit() }
            tool = t
            width = nil
            overlays.inkViews.values.forEach(applyStyle)
            if session.mode == .capturing { overlays.captureViews.values.forEach { $0.armed = true } }
        case .undo:
            if let v = strokeOrder.popLast() { v.undo() }
        case .copySelection:
            if let img = composedSelection() { output.copy(img, format: format) }
            send(.captureFinished)
        case .saveSelection:
            if let img = composedSelection() { lastSavedURL = output.save(img, format: format, folder: saveFolder) }
            send(.captureFinished)
        case .restorePreviousApp:
            previousApp?.activate()
            previousApp = nil
        }
    }

    private func enterLiveChrome(_ live: Bool) {
        for v in overlays.inkViews.values {
            v.showsCursorRing = live
            v.showsPointerLabel = live
            if !live { v.setPointer(nil) }
        }
        if !live { dock.orderOut(nil) }
    }

    private func freeze() {
        enterLiveChrome(false)
        Task { @MainActor in
            do {
                let captured = try await capturer.captureAll()
                guard session.mode == .capturing else { return }
                frames = captured
                for (id, frame) in captured {
                    overlays.frozenViews[id]?.frame_ = frame
                    if let c = overlays.captureViews[id] {
                        c.scale = frame.scale
                        c.format = format
                        c.isHidden = false
                    }
                }
            } catch {
                send(.escape)
                showPermissionAlert()
            }
        }
    }

    private func selectionChanged(in view: CaptureView) {
        if view.selection != nil {
            for other in overlays.captureViews.values where other !== view && other.selection != nil { other.clearSelection() }
        }
        let active = overlays.captureViews.first { $0.value.selection != nil }
        dockState.canOutput = active != nil
        guard let (id, cv) = active, let sel = cv.selection, let screen = overlays.screen(of: id) else {
            dock.orderOut(nil)
            return
        }
        dockState.mode = .capturing
        let size = dock.fittingSize
        let local = dockOrigin(selection: sel, dockSize: size, screen: NSRect(origin: .zero, size: screen.frame.size))
        dock.place(at: NSPoint(x: screen.frame.minX + local.x, y: screen.frame.minY + local.y))
    }

    private func composedSelection() -> CGImage? {
        guard let (id, cv) = overlays.captureViews.first(where: { $0.value.selection != nil }),
              let sel = cv.selection, let frame = frames[id], let ink = overlays.inkViews[id] else { return nil }
        return Compositor.image(base: frame.image, baseScale: frame.scale, strokes: ink.model.strokes, selection: sel)
    }

    private func showPermissionAlert() {
        capturer.requestPermission()
        let alert = NSAlert()
        alert.messageText = "Tracer needs Screen Recording permission to take screenshots"
        alert.informativeText = "Turn on Tracer in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. Drawing works without it."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private var screenUnderPointer: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private var currentStyle: StrokeStyle { StrokeStyle(color: color, width: width ?? defaultWidth(for: tool)) }

    private func applyStyle(to view: InkView) {
        view.tool = tool
        view.style = currentStyle
        view.fadeDelay = fadeDelay
    }

    func setColor(_ c: RGBA) {
        color = c
        dockState.color = c
        overlays.inkViews.values.forEach(applyStyle)
    }

    private func setWidth(_ w: Double) {
        width = w
        overlays.inkViews.values.forEach(applyStyle)
    }

    private func showColorPanel() {
        let panel = NSColorPanel.shared
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate()
        panel.orderFrontRegardless()
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        setColor(RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent))
    }
}
