import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg

    public static let jpegQuality = 1.0

    public var fileExtension: String { self == .png ? "png" : "jpg" }
    public var label: String { self == .png ? "PNG" : "JPEG" }
    public var utType: UTType { self == .png ? .png : .jpeg }
}

public func encode(_ image: CGImage, as format: ImageFormat) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { return nil }
    let props: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: ImageFormat.jpegQuality] : [:]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    return CGImageDestinationFinalize(dest) ? data as Data : nil
}

public func screenshotFileName(date: Date, format: ImageFormat, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Tracer \(f.string(from: date)).\(format.fileExtension)"
}

public func uniqueURL(in folder: URL, fileName: String, exists: (URL) -> Bool) -> URL {
    let first = folder.appendingPathComponent(fileName)
    guard exists(first) else { return first }
    let ext = (fileName as NSString).pathExtension
    let stem = (fileName as NSString).deletingPathExtension
    var n = 2
    while true {
        let url = folder.appendingPathComponent("\(stem) (\(n))").appendingPathExtension(ext)
        if !exists(url) { return url }
        n += 1
    }
}

public func resolveSaveFolder(preferred: URL, fallback: URL, fm: FileManager) -> (url: URL, usedFallback: Bool) {
    func usable(_ url: URL) -> Bool {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && fm.isWritableFile(atPath: url.path)
    }
    if usable(preferred) { return (preferred, false) }
    _ = usable(fallback)
    return (fallback, true)
}
