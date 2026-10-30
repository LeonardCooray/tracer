import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    var onDraw: (() -> Void)?
    var onCapture: (() -> Void)?
    var onSettings: (() -> Void)?

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "Tracer")
        menu.addItem(item("Draw", #selector(draw)))
        menu.addItem(item("Capture", #selector(capture)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Tracer", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func setWarnings(_ warnings: [String]) {
        menu.items.filter { $0.tag == 99 }.forEach(menu.removeItem)
        for (i, text) in warnings.enumerated() {
            let w = NSMenuItem(title: "⚠︎ \(text)", action: nil, keyEquivalent: "")
            w.isEnabled = false
            w.tag = 99
            menu.insertItem(w, at: i)
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func draw() { onDraw?() }
    @objc private func capture() { onCapture?() }
    @objc private func settings() { onSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
