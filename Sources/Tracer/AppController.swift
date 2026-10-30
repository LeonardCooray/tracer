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
        overlays.configureView = { [weak self] view in self?.configure(view) }
        menuBar.onDraw = { [weak self] in self?.send(.penHotkey) }
        dockState.onCommand = { [weak self] in self?.send(.command($0)) }
        dockState.onColor = { [weak self] in self?.setColor($0) }
        dockState.onWidth = { [weak self] in self?.setWidth($0) }
        dockState.onMoreColors = { [weak self] in self?.showColorPanel() }
        text.onBegan = { [weak self] in self?.send(.textEditingBegan) }
        text.onEnded = { [weak self] in self?.send(.textEditingEnded) }
        registerHotkeys()
    }

    private func configure(_ view: InkView) {
        view.onStrokeEnded = { [weak self] in self?.strokeOrder.append($0) }
        view.onTextClick = { [weak self] v, p in
            guard let self else { return }
            text.begin(at: p, in: v, style: currentStyle)
        }
        applyStyle(to: view)
    }

    private func registerHotkeys() {
        var warnings: [String] = []
        if !hotkeys.register(.defaultPen, id: HotkeyID.pen, handler: { [weak self] in self?.send(.penHotkey) }) {
            warnings.append("Draw hotkey \(Hotkey.defaultPen.displayString) unavailable")
        }
        hotkeyWarnings = warnings
        menuBar.setWarnings(warnings)
    }

    func send(_ event: SessionEvent) {
        for effect in session.handle(event) { perform(effect) }
        dockState.tool = session.tool
        dockState.mode = session.mode
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
            overlays.inkViews.values.forEach { $0.showsCursorRing = true }
            if session.mode == .drawing, let screen = screenUnderPointer { dock.slideIn(onRightEdgeOf: screen) }
        case .hideOverlays:
            text.cancel()
            dock.slideOut()
            NSColorPanel.shared.orderOut(nil)
            overlays.inkViews.values.forEach { $0.showsCursorRing = false; $0.setPointer(nil) }
            overlays.hide()
        case .clearInk, .clearAll:
            overlays.inkViews.values.forEach { $0.clear() }
            strokeOrder.removeAll()
        case .setFadeMode(let mode):
            overlays.inkViews.values.forEach { $0.model.mode = mode }
        case .registerSessionKeys(let capture):
            hotkeys.registerSessionKeys(capture: capture) { [weak self] in self?.handleSessionKey($0) }
        case .unregisterSessionKeys:
            hotkeys.unregisterSessionKeys()
        case .selectTool(let t):
            if text.isEditing { text.commit() }
            tool = t
            width = nil
            overlays.inkViews.values.forEach(applyStyle)
        case .undo:
            if let v = strokeOrder.popLast() { v.undo() }
        case .restorePreviousApp:
            previousApp?.activate()
            previousApp = nil
        case .freezeScreens, .copySelection, .saveSelection:
            break
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
