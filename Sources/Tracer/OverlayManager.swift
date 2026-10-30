import AppKit

@MainActor
final class OverlayManager {
    private(set) var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var inkViews: [CGDirectDisplayID: InkView] = [:]
    private(set) var frozenViews: [CGDirectDisplayID: FrozenView] = [:]
    private(set) var captureViews: [CGDirectDisplayID: CaptureView] = [:]
    var configureView: ((InkView, CaptureView) -> Void)?
    private(set) var isShown = false
    private var interactive = false

    func show(interactive: Bool) {
        if panels.isEmpty { sync() }
        isShown = true
        self.interactive = interactive
        for p in panels.values {
            p.setInteractive(interactive)
            p.orderFrontRegardless()
        }
    }

    func hide() {
        isShown = false
        for p in panels.values {
            p.setInteractive(false)
            p.allowsKey = false
            p.orderOut(nil)
        }
    }

    #if DEBUG
    func forgetPanels() {
        panels.values.forEach { $0.orderOut(nil) }
        panels = [:]; inkViews = [:]; frozenViews = [:]; captureViews = [:]
    }
    #endif

    func screen(of id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { $0.displayID == id } }

    // Keeps overlays (and their ink) for displays that remain, adds new ones, drops removed ones.
    @discardableResult
    func sync() -> (added: [CGDirectDisplayID], removed: [CGDirectDisplayID]) {
        let current = Dictionary(NSScreen.screens.compactMap { s in s.displayID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        let removed = panels.keys.filter { current[$0] == nil }
        for id in removed {
            panels[id]?.orderOut(nil)
            panels[id] = nil
            inkViews[id] = nil
            frozenViews[id] = nil
            captureViews[id] = nil
        }
        var added: [CGDirectDisplayID] = []
        for (id, screen) in current {
            if let p = panels[id] {
                p.setFrame(screen.frame, display: true)
            } else {
                build(screen, id: id)
                added.append(id)
                if isShown {
                    panels[id]?.setInteractive(interactive)
                    panels[id]?.orderFrontRegardless()
                }
            }
        }
        return (added, removed)
    }

    private func build(_ screen: NSScreen, id: CGDirectDisplayID) {
        let panel = OverlayPanel(screen: screen)
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        let frozen = FrozenView(frame: bounds)
        let ink = InkView(frame: bounds)
        let capture = CaptureView(frame: bounds)
        capture.inkView = ink
        capture.isHidden = true
        for v in [frozen, ink, capture] as [NSView] {
            v.autoresizingMask = [.width, .height]
            container.addSubview(v)
        }
        panel.contentView = container
        configureView?(ink, capture)
        panels[id] = panel
        inkViews[id] = ink
        frozenViews[id] = frozen
        captureViews[id] = capture
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
