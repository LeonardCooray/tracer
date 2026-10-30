import CoreGraphics
import Testing
@testable import TracerCore

struct Canvas {
    let ctx: CGContext
    let size: Int

    init(size: Int = 100, background: RGBA? = nil) {
        self.size = size
        ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let bg = background {
            ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    // (x, y) in user space, origin bottom-left; returns r, g, b, a in 0...255.
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = ((size - 1 - y) * size + x) * 4
        return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]), Int(p[i + 3]))
    }

    var anyPainted: Bool {
        (0..<size).contains { y in (0..<size).contains { x in pixel(x, y).a > 0 } }
    }
}

private func stroke(_ tool: Tool, _ pts: [CGPoint], color: RGBA = RGBA(hex: 0xFF0000), width: Double = 4) -> Stroke {
    Stroke(tool: tool, points: pts, style: StrokeStyle(color: color, width: width), finishedAt: 0)
}

@Test func penPaintsAlongPath() {
    let c = Canvas()
    InkRenderer.draw([stroke(.pen, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])], in: c.ctx) { _ in 1 }
    let on = c.pixel(50, 50)
    #expect(on.r > 200 && on.g < 40 && on.a > 200)
    #expect(c.pixel(50, 10).a == 0)
}

@Test func opacityZeroPaintsNothing() {
    let c = Canvas()
    InkRenderer.draw([stroke(.pen, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])], in: c.ctx) { _ in 0 }
    #expect(!c.anyPainted)
}

@Test func rectangleIsOutlineOnly() {
    let c = Canvas()
    InkRenderer.draw([stroke(.rectangle, [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)])], in: c.ctx) { _ in 1 }
    #expect(c.pixel(20, 50).a > 200)
    #expect(c.pixel(50, 50).a == 0)
}

@Test func arrowPaintsShaftAndHead() {
    let c = Canvas()
    InkRenderer.draw([stroke(.arrow, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])], in: c.ctx) { _ in 1 }
    #expect(c.pixel(50, 50).a > 200)
    let (wing, _) = arrowHead(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50), width: 4)
    let mid = CGPoint(x: (wing.x + 90) / 2, y: (wing.y + 50) / 2)
    #expect(c.pixel(Int(mid.x.rounded()), Int(mid.y.rounded())).a > 100)
}

@Test func arrowHeadWingsAreSymmetric() {
    let (a, b) = arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), width: 4)
    #expect(abs(a.y + b.y) < 0.001)
    #expect(a.x < 100 && b.x < 100)
    let len = hypot(100 - a.x, a.y)
    #expect(abs(len - 14) < 0.001)
}

@Test func highlighterIsTranslucent() {
    let c = Canvas(background: RGBA(hex: 0x0000FF))
    InkRenderer.draw([stroke(.highlighter, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
                             color: RGBA(hex: 0xFFFF00), width: 18)], in: c.ctx) { _ in 1 }
    let p = c.pixel(50, 50)
    #expect(p.b > 60)
    #expect(p.r > 60 || p.g > 60)
}

@Test func textPaints() {
    let c = Canvas()
    var s = stroke(.text, [CGPoint(x: 10, y: 40)], width: 18)
    s.text = "Hi"
    InkRenderer.draw([s], in: c.ctx) { _ in 1 }
    #expect(c.anyPainted)
}

@Test func arrowClickPaintsNothing() {
    let c = Canvas()
    InkRenderer.draw([stroke(.arrow, [CGPoint(x: 50, y: 50)])], in: c.ctx) { _ in 1 }
    #expect(!c.anyPainted)
    let c2 = Canvas()
    InkRenderer.draw([stroke(.arrow, [CGPoint(x: 50, y: 50), CGPoint(x: 51, y: 50)])], in: c2.ctx) { _ in 1 }
    #expect(!c2.anyPainted)
}

@Test func multiplyHighlighterKeepsDarkTextDark() {
    let c = Canvas(background: RGBA(hex: 0x000000))
    InkRenderer.draw([stroke(.highlighter, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], color: RGBA(hex: 0xFFFF00), width: 18)],
                     in: c.ctx, highlighterBlend: .multiply) { _ in 1 }
    let p = c.pixel(50, 50)
    #expect(p.r < 30 && p.g < 30)
}

@Test func strokeBoundsContainEveryPaintedPixel() {
    let strokes = [
        stroke(.pen, [CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 40)], width: 8),
        stroke(.arrow, [CGPoint(x: 20, y: 70), CGPoint(x: 80, y: 70)]),
        stroke(.rectangle, [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 60)]),
        stroke(.highlighter, [CGPoint(x: 15, y: 50), CGPoint(x: 85, y: 50)], width: 18),
        { var s = stroke(.text, [CGPoint(x: 10, y: 30)], width: 18); s.text = "Hey"; return s }(),
    ]
    for s in strokes {
        let c = Canvas()
        InkRenderer.draw([s], in: c.ctx) { _ in 1 }
        let b = inkBounds(of: s)
        var outside = 0
        for y in 0..<c.size { for x in 0..<c.size where c.pixel(x, y).a > 0 {
            if !b.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { outside += 1 }
        } }
        #expect(outside == 0, "\(s.tool) painted \(outside) px outside \(b)")
        #expect(b.width > 0 && b.height > 0)
    }
}
