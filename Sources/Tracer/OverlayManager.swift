import AppKit

@MainActor
final class OverlayManager {
    private(set) var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var inkViews: [CGDirectDisplayID: InkView] = [:]
    private(set) var frozenViews: [CGDirectDisplayID: FrozenView] = [:]
    private(set) var captureViews: [CGDirectDisplayID: CaptureView] = [:]
    var configureView: ((InkView, CaptureView) -> Void)?

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

    func screen(of id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { $0.displayID == id } }

    private func build() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
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
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
