import AppKit
import TracerCore
import UserNotifications

@MainActor
final class OutputController: NSObject, UNUserNotificationCenterDelegate {
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tracer")

    var fallbackFolder = OutputController.defaultFolder

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner] }

    @discardableResult
    func copy(_ image: CGImage, format: ImageFormat) -> Bool {
        guard let data = encode(image, as: format) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        let type = NSPasteboard.PasteboardType(format.utType.identifier)
        guard pb.setData(data, forType: type) else { return false }
        // Many apps only paste PNG or TIFF, so a JPEG copy also carries a TIFF.
        if format == .jpeg, let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        return true
    }

    func save(_ image: CGImage, format: ImageFormat, folder: URL) -> URL? {
        let fm = FileManager.default
        let (dir, usedFallback) = resolveSaveFolder(preferred: folder, fallback: fallbackFolder, fm: fm)
        guard let data = encode(image, as: format) else { return nil }
        let url = uniqueURL(in: dir, fileName: screenshotFileName(date: Date(), format: format)) { fm.fileExists(atPath: $0.path) }
        do { try data.write(to: url) } catch { return nil }
        if usedFallback { notify("Saved to \(dir.path)", body: "\(folder.path) isn't writable.") }
        return url
    }

    private func notify(_ title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
