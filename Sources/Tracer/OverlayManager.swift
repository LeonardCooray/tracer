import AppKit

@MainActor
final class OverlayManager {
    private(set) var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var inkViews: [CGDirectDisplayID: InkView] = [:]
    var configureView: ((InkView) -> Void)?

    func show(interactive: Bool) {
        if panels.isEmpty { build() }
        for p in panels.values {
            p.setInteractive(interactive)
            p.orderFrontRegardless()
        }
    }

    func hide() {
        for p in panels.values {
            p.setInteractive(false)
            p.allowsKey = false
            p.orderOut(nil)
        }
    }

    func inkView(at screenPoint: NSPoint) -> InkView? {
        guard let id = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })?.displayID else { return nil }
        return inkViews[id]
    }

    private func build() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let panel = OverlayPanel(screen: screen)
            let view = InkView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            configureView?(view)
            panels[id] = panel
            inkViews[id] = view
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
