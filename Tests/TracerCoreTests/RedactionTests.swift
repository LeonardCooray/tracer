import CoreGraphics
import Testing
@testable import TracerCore

private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

private func bitmap(_ w: Int, _ h: Int, space: CGColorSpace = srgb, bpc: Int = 8,
                    info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: bpc, bytesPerRow: 0, space: space, bitmapInfo: info)!
}

private func fill(_ ctx: CGContext, _ r: CGRect, _ c: [Double], in space: CGColorSpace? = nil) {
    ctx.setFillColor(CGColor(colorSpace: space ?? ctx.colorSpace!, components: c.map { CGFloat($0) } + [1])!)
    ctx.fill(r)
}

// Raw bytes in the image's own space; (x, y) from the bottom-left.
private func rawPixels(_ img: CGImage) -> (Int, Int) -> [Int] {
    let ctx = bitmap(img.width, img.height, space: img.colorSpace!)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    let row = ctx.bytesPerRow, h = img.height
    return { x, y in (0..<4).map { Int(ctx.data!.assumingMemoryBound(to: UInt8.self)[(h - 1 - y) * row + x * 4 + $0]) } }
}

// Left half black, right half white.
private func halves(px: Int) -> CGImage {
    let c = bitmap(px, px)
    fill(c, CGRect(x: 0, y: 0, width: px, height: px), [1, 1, 1])
    fill(c, CGRect(x: 0, y: 0, width: px / 2, height: px), [0, 0, 0])
    return c.makeImage()!
}

private func mean(_ img: CGImage, scale: Double, _ r: CGRect, maxSamples: Int? = nil) -> RGBA? {
    FramePixels(img)?.mean(in: r, scale: scale, maxSamples: maxSamples)
}

private func near(_ c: RGBA?, _ v: [Double], _ tol: Double) -> Bool {
    guard let c else { return false }
    return abs(c.r - v[0]) <= tol && abs(c.g - v[1]) <= tol && abs(c.b - v[2]) <= tol && c.a == 1
}

private func near(_ c: RGBA?, _ v: Double, _ tol: Double) -> Bool { near(c, [v, v, v], tol) }

@Test func meanColorOfHalfBlackHalfWhite() {
    #expect(near(mean(halves(px: 100), scale: 1, CGRect(x: 25, y: 0, width: 50, height: 100)), 0.5, 0.01))
}

@Test func meanColorClipsToImage() {
    let white = Canvas(size: 100, background: RGBA(hex: 0xFFFFFF)).ctx.makeImage()!
    #expect(near(mean(white, scale: 1, CGRect(x: 90, y: 90, width: 50, height: 50)), 1, 0.001))
    #expect(mean(white, scale: 1, CGRect(x: 200, y: 200, width: 10, height: 10)) == nil)
}

@Test func meanColorHonoursScale() {
    let img = halves(px: 200)
    #expect(near(mean(img, scale: 2, CGRect(x: 0, y: 0, width: 50, height: 100)), 0, 0.001))
    #expect(near(mean(img, scale: 2, CGRect(x: 25, y: 0, width: 50, height: 100)), 0.5, 0.01))
    #expect(near(mean(img, scale: 1, CGRect(x: 50, y: 0, width: 100, height: 200)), 0.5, 0.01))
}

@Test func meanColorStaysInFrameSpace() {
    let ctx = bitmap(50, 50, space: p3)
    fill(ctx, CGRect(x: 0, y: 0, width: 50, height: 50), [1, 0, 0])
    let px = FramePixels(ctx.makeImage()!)
    #expect(px?.space.name == CGColorSpace.displayP3)
    // Clipped through sRGB this would come back near (0.92, 0.2, 0.14).
    #expect(near(px?.mean(in: CGRect(x: 0, y: 0, width: 50, height: 50), scale: 1), [1, 0, 0], 0.001))
}

@Test func meanColorReadsBGRAFrames() {
    let ctx = bitmap(40, 40, info: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    fill(ctx, CGRect(x: 0, y: 0, width: 40, height: 40), [0.2, 0.4, 0.6])
    #expect(near(mean(ctx.makeImage()!, scale: 1, CGRect(x: 0, y: 0, width: 40, height: 40)), [0.2, 0.4, 0.6], 0.003))
}

@Test func meanColorReadsDeepFramesInTheirOwnSpace() {
    let ctx = bitmap(40, 40, space: p3, bpc: 16, info: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
    fill(ctx, CGRect(x: 0, y: 0, width: 40, height: 40), [1, 0, 0])
    let px = FramePixels(ctx.makeImage()!)
    #expect(px?.space.name == CGColorSpace.displayP3)
    #expect(near(px?.mean(in: CGRect(x: 0, y: 0, width: 40, height: 40), scale: 1), [1, 0, 0], 0.003))
}

@Test func meanColorRowSampleIsClose() {
    #expect(near(mean(halves(px: 400), scale: 1, CGRect(x: 0, y: 0, width: 400, height: 400), maxSamples: 1000), 0.5, 0.01))
    #expect(near(mean(halves(px: 400), scale: 1, CGRect(x: 0, y: 0, width: 400, height: 3), maxSamples: 10), 0.5, 0.01))
}

@Test func redactFillUsesItsColourSpace() {
    let ctx = bitmap(20, 20, space: p3)
    let s = Stroke(tool: .redact, points: [CGPoint(x: 2, y: 2), CGPoint(x: 18, y: 18)],
                   style: StrokeStyle(color: RGBA(r: 1, g: 0, b: 0), width: 0, colorSpace: p3), finishedAt: 0)
    InkRenderer.draw([s], in: ctx) { _ in 1 }
    #expect(rawPixels(ctx.makeImage()!)(10, 10) == [255, 0, 0, 255])
}

// A P3 frame, left half P3 red, right half black; a box with fractional edges straddles the two.
@Test func p3RedactKeepsGamutAndNoOriginalPixel() {
    let base = bitmap(200, 200, space: p3, info: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    fill(base, CGRect(x: 0, y: 0, width: 200, height: 200), [0, 0, 0])
    fill(base, CGRect(x: 0, y: 0, width: 100, height: 200), [1, 0, 0])
    let img = base.makeImage()!
    let box = CGRect(x: 40.05, y: 10.05, width: 20, height: 30)
    let px = FramePixels(img)!
    let m = px.mean(in: box, scale: 2)!
    #expect(abs(m.r - 20.0 / 41) < 0.002 && m.g == 0 && m.b == 0)
    let s = Stroke(tool: .redact, points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)],
                   style: StrokeStyle(color: m, width: 0, colorSpace: px.space), finishedAt: 0)
    let out = Compositor.image(base: img, baseScale: 2, strokes: [s], selection: CGRect(x: 0, y: 0, width: 100, height: 100))!
    #expect(out.colorSpace?.name == CGColorSpace.displayP3)
    let at = rawPixels(out)
    let want = at(100, 50)
    #expect(abs(want[0] - 124) <= 1 && want[1] == 0 && want[2] == 0 && want[3] == 255)
    // Device pixels 80..<121 by 20..<81 are the box, every edge included.
    var odd = 0
    for y in 20..<81 { for x in 80..<121 where at(x, y) != want { odd += 1 } }
    #expect(odd == 0)
    #expect(at(79, 50) == [255, 0, 0, 255] && at(121, 50) == [0, 0, 0, 255] && at(100, 19) == [0, 0, 0, 255] && at(90, 81) == [255, 0, 0, 255])
}

// Two synthetic displays: a 2x P3 main and a 1x sRGB second whose top half is white.
@Test func boxOnSecondDisplayUsesItsOwnFrame() {
    let main = bitmap(600, 400, space: p3)
    fill(main, CGRect(x: 0, y: 0, width: 600, height: 400), [1, 0, 0])
    let second = bitmap(300, 200)
    fill(second, CGRect(x: 0, y: 0, width: 300, height: 100), [0.2, 0.4, 0.6])
    fill(second, CGRect(x: 0, y: 100, width: 300, height: 100), [1, 1, 1])
    let img = second.makeImage()!
    let box = CGRect(x: 100, y: 50, width: 100, height: 100)
    #expect(near(mean(main.makeImage()!, scale: 2, box), [1, 0, 0], 0.001))
    let px = FramePixels(img)!
    let m = px.mean(in: box, scale: 1)
    #expect(near(m, [0.6, 0.7, 0.8], 0.003))
    let s = Stroke(tool: .redact, points: [box.origin, CGPoint(x: box.maxX, y: box.maxY)],
                   style: StrokeStyle(color: m!, width: 0, colorSpace: px.space), finishedAt: 0)
    let out = Compositor.image(base: img, baseScale: 1, strokes: [s], selection: CGRect(x: 50, y: 25, width: 200, height: 150))!
    #expect(out.width == 200 && out.height == 150)
    let at = rawPixels(out)
    let want = at(100, 75)
    #expect(abs(want[0] - 153) <= 1 && abs(want[1] - 178) <= 1 && abs(want[2] - 204) <= 1)
    var odd = 0
    for y in 25..<125 { for x in 50..<150 where at(x, y) != want { odd += 1 } }
    #expect(odd == 0)
    #expect(at(49, 30) == [51, 102, 153, 255] && at(150, 124) == [255, 255, 255, 255])
}
