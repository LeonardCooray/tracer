import AppKit
import ScreenCaptureKit

struct FrozenFrame {
    let image: CGImage
    let scale: Double
}

@MainActor
protocol ScreenCapturing {
    var hasPermission: Bool { get }
    func requestPermission()
    func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame]
}

@MainActor
final class ScreenCapturer: ScreenCapturing {
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestPermission() { CGRequestScreenCaptureAccess() }

    func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var frames: [CGDirectDisplayID: FrozenFrame] = [:]
        for display in content.displays {
            let scale = NSScreen.screens.first { $0.displayID == display.displayID }?.backingScaleFactor ?? 2
            let config = SCStreamConfiguration()
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frames[display.displayID] = FrozenFrame(image: image, scale: scale)
        }
        return frames
    }
}
