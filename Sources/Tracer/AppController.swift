import AppKit
import TracerCore

@MainActor
final class AppController {
    private(set) var session = Session()
    private let hotkeys = HotkeyCenter()
    let overlays = OverlayManager()
    private let menuBar = MenuBarController()
    private var previousApp: NSRunningApplication?
    private var strokeOrder: [InkView] = []
    private var tool: Tool = .pen
    private var color = InkPalette.presets[0]
    private var width: Double?
    private(set) var hotkeyWarnings: [String] = []

    private enum HotkeyID { static let pen: UInt32 = 1, capture: UInt32 = 2 }

    init() {
        overlays.configureView = { [weak self] view in
            view.onStrokeEnded = { self?.strokeOrder.append($0) }
            self?.applyStyle(to: view)
        }
        menuBar.onDraw = { [weak self] in self?.send(.penHotkey) }
        registerHotkeys()
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
        case .hideOverlays:
            overlays.hide()
        case .clearInk:
            overlays.inkViews.values.forEach { $0.clear() }
            strokeOrder.removeAll()
        case .setFadeMode(let mode):
            overlays.inkViews.values.forEach { $0.model.mode = mode }
        case .registerSessionKeys(let capture):
            hotkeys.registerSessionKeys(capture: capture) { [weak self] in self?.handleSessionKey($0) }
        case .unregisterSessionKeys:
            hotkeys.unregisterSessionKeys()
        case .selectTool(let t):
            tool = t
            width = nil
            overlays.inkViews.values.forEach(applyStyle)
        case .undo:
            if let v = strokeOrder.popLast() { v.undo() }
        case .clearAll:
            overlays.inkViews.values.forEach { $0.clear() }
            strokeOrder.removeAll()
        case .restorePreviousApp:
            previousApp?.activate()
            previousApp = nil
        case .freezeScreens, .copySelection, .saveSelection:
            break
        }
    }

    private func applyStyle(to view: InkView) {
        view.tool = tool
        view.style = StrokeStyle(color: color, width: width ?? defaultWidth(for: tool))
    }
}
