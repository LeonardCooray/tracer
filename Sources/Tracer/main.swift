import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let c = DebugSelfTest.isRequested ? AppController(defaults: DebugSelfTest.isolatedDefaults()) : AppController()
        controller = c
        DebugSelfTest.runIfRequested(c)
        #else
        controller = AppController()
        #endif
    }
}
