import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let releasesURL = URL(string: "https://github.com/LeonardCooray/tracer/releases/latest")!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    var onDraw: (() -> Void)?
    var onCapture: (() -> Void)?
    var onSettings: (() -> Void)?

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "Tracer")
        menu.addItem(item("Draw", #selector(draw(_:))))
        menu.addItem(item("Capture", #selector(capture(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(.separator())
        let version = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item("Quit Tracer", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func setShortcuts(draw: String, capture: String) {
        menu.items.first { $0.action == #selector(draw(_:)) }?.title = "Draw  \(draw)"
        menu.items.first { $0.action == #selector(capture(_:)) }?.title = "Capture  \(capture)"
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

    @objc private func draw(_ sender: Any?) { onDraw?() }
    @objc private func capture(_ sender: Any?) { onCapture?() }
    @objc private func settings() { onSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
    // Opens the releases page in the browser so Tracer itself never goes online.
    @objc private func checkForUpdates() { NSWorkspace.shared.open(Self.releasesURL) }

    static var versionTitle: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v.map { "Tracer \($0)" } ?? "Tracer (development build)"
    }
}
