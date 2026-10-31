import CoreGraphics
import Testing
@testable import TracerCore

// Left half black, right half white.
private func halves(px: Int) -> CGImage {
    let c = Canvas(size: px, background: RGBA(hex: 0xFFFFFF))
    c.ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    c.ctx.fill(CGRect(x: 0, y: 0, width: px / 2, height: px))
    return c.ctx.makeImage()!
}

private func near(_ c: RGBA?, _ v: Double, _ tol: Double) -> Bool {
    guard let c else { return false }
    return abs(c.r - v) <= tol && abs(c.g - v) <= tol && abs(c.b - v) <= tol && c.a == 1
}

@Test func meanColorOfHalfBlackHalfWhite() {
    #expect(near(meanColor(of: halves(px: 100), scale: 1, in: CGRect(x: 25, y: 0, width: 50, height: 100)), 0.5, 0.01))
}

@Test func meanColorClipsToImage() {
    let white = Canvas(size: 100, background: RGBA(hex: 0xFFFFFF)).ctx.makeImage()!
    #expect(near(meanColor(of: white, scale: 1, in: CGRect(x: 90, y: 90, width: 50, height: 50)), 1, 0.001))
    #expect(meanColor(of: white, scale: 1, in: CGRect(x: 200, y: 200, width: 10, height: 10)) == nil)
}

@Test func meanColorHonoursScale() {
    let img = halves(px: 200)
    #expect(near(meanColor(of: img, scale: 2, in: CGRect(x: 0, y: 0, width: 50, height: 100)), 0, 0.001))
    #expect(near(meanColor(of: img, scale: 2, in: CGRect(x: 25, y: 0, width: 50, height: 100)), 0.5, 0.01))
    #expect(near(meanColor(of: img, scale: 1, in: CGRect(x: 50, y: 0, width: 100, height: 200)), 0.5, 0.01))
}

@Test func meanColorConvertsToSRGB() {
    let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    let m = meanColor(of: ctx.makeImage()!, scale: 1, in: CGRect(x: 0, y: 0, width: 50, height: 50))
    #expect(m.map { abs($0.r - 0.2) <= 0.02 && abs($0.g - 0.4) <= 0.02 && abs($0.b - 0.6) <= 0.02 } == true)
}

@Test func meanColorDownsampleIsClose() {
    #expect(near(meanColor(of: halves(px: 400), scale: 1, in: CGRect(x: 0, y: 0, width: 400, height: 400), maxSide: 16), 0.5, 0.05))
}
