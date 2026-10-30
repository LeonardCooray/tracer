import AppKit
import TracerCore
import UserNotifications

@MainActor
final class OutputController {
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tracer")

    @discardableResult
    func copy(_ image: CGImage, format: ImageFormat) -> Bool {
        guard let data = encode(image, as: format) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setData(data, forType: NSPasteboard.PasteboardType(format.utType.identifier))
    }

    func save(_ image: CGImage, format: ImageFormat, folder: URL) -> URL? {
        let fm = FileManager.default
        let (dir, usedFallback) = resolveSaveFolder(preferred: folder, fallback: Self.defaultFolder, fm: fm)
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
