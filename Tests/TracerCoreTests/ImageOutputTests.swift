import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TracerCore

@Test func fileNameFormat() {
    let date = Date(timeIntervalSince1970: 1_793_369_109) // 2026-10-30 14:05:09 UTC
    #expect(screenshotFileName(date: date, format: .png, timeZone: TimeZone(identifier: "UTC")!) == "Tracer 2026-10-30 at 14.05.09.png")
    #expect(screenshotFileName(date: date, format: .jpeg, timeZone: TimeZone(identifier: "UTC")!) == "Tracer 2026-10-30 at 14.05.09.jpg")
}

@Test func uniqueNameIncrements() {
    let folder = URL(fileURLWithPath: "/tmp/f")
    let taken: Set<String> = ["x.png", "x (2).png"]
    let url = uniqueURL(in: folder, fileName: "x.png") { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "x (3).png")
    #expect(uniqueURL(in: folder, fileName: "y.png") { _ in false }.lastPathComponent == "y.png")
}

@Test func resolveSaveFolderCreatesMissing() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let preferred = root.appendingPathComponent("Shots")
    let r = resolveSaveFolder(preferred: preferred, fallback: root.appendingPathComponent("Fallback"), fm: fm)
    #expect(r.url == preferred && !r.usedFallback)
    #expect(fm.fileExists(atPath: preferred.path))
}

@Test func resolveSaveFolderFallsBackWhenUnwritable() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let locked = root.appendingPathComponent("locked")
    try fm.createDirectory(at: locked, withIntermediateDirectories: true)
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try? fm.removeItem(at: root)
    }
    let fallback = root.appendingPathComponent("Fallback")
    let r1 = resolveSaveFolder(preferred: locked.appendingPathComponent("Shots"), fallback: fallback, fm: fm)
    #expect(r1.url == fallback && r1.usedFallback)
    let r2 = resolveSaveFolder(preferred: locked, fallback: fallback, fm: fm)
    #expect(r2.url == fallback && r2.usedFallback)
}

@Test func formatProperties() {
    #expect(ImageFormat.png.fileExtension == "png")
    #expect(ImageFormat.jpeg.fileExtension == "jpg")
    #expect(ImageFormat.png.label == "PNG")
    #expect(ImageFormat.jpeg.label == "JPEG")
}

private func solidImage(width: Int, height: Int) -> CGImage {
    let c = Canvas(size: max(width, height), background: RGBA(hex: 0x336699))
    return c.ctx.makeImage()!.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))!
}

@Test func encodingRoundTrips() {
    let img = solidImage(width: 40, height: 30)
    for f in ImageFormat.allCases {
        let data = encode(img, as: f)!
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let back = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        #expect(back.width == 40 && back.height == 30)
        let type = CGImageSourceGetType(src) as String?
        #expect(type == (f == .png ? "public.png" : "public.jpeg"))
    }
}

@Test func jpegUsesMaximumQuality() {
    let img = solidImage(width: 64, height: 64)
    #expect(ImageFormat.jpegQuality == 1.0)
    #expect(encode(img, as: .jpeg)!.count > 0)
}
