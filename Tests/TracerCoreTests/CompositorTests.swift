import CoreGraphics
import Testing
@testable import TracerCore

private func base(px: Int) -> CGImage {
    Canvas(size: px, background: RGBA(hex: 0xFFFFFF)).ctx.makeImage()!
}

private func redPixels(_ img: CGImage) -> Int {
    let c = Canvas(size: max(img.width, img.height))
    c.ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    var n = 0
    for y in 0..<img.height { for x in 0..<img.width {
        let p = c.pixel(x, y)
        if p.r > 200 && p.g < 80 && p.b < 80 { n += 1 }
    } }
    return n
}

@Test func compositeIsFullResolution() {
    let out = Compositor.image(base: base(px: 200), baseScale: 2, strokes: [], selection: CGRect(x: 10, y: 10, width: 50, height: 50))!
    #expect(out.width == 100 && out.height == 100)
}

@Test func compositeIncludesInk() {
    let s = Stroke(tool: .pen, points: [CGPoint(x: 0, y: 35), CGPoint(x: 100, y: 35)],
                   style: StrokeStyle(color: RGBA(hex: 0xFF0000), width: 4), finishedAt: 0)
    let out = Compositor.image(base: base(px: 200), baseScale: 2, strokes: [s], selection: CGRect(x: 10, y: 10, width: 50, height: 50))!
    #expect(redPixels(out) > 100)
}

@Test func compositeCropsToSelection() {
    let s = Stroke(tool: .pen, points: [CGPoint(x: 0, y: 90), CGPoint(x: 100, y: 90)],
                   style: StrokeStyle(color: RGBA(hex: 0xFF0000), width: 4), finishedAt: 0)
    let out = Compositor.image(base: base(px: 200), baseScale: 2, strokes: [s], selection: CGRect(x: 10, y: 10, width: 50, height: 50))!
    #expect(redPixels(out) == 0)
}

@Test func compositeSkipsSpotlight() {
    let s = Stroke(tool: .spotlight, points: [CGPoint(x: 20, y: 20)], style: StrokeStyle(color: RGBA(hex: 0xFF0000), width: 4))
    let out = Compositor.image(base: base(px: 200), baseScale: 2, strokes: [s], selection: CGRect(x: 10, y: 10, width: 50, height: 50))!
    #expect(redPixels(out) == 0)
}

@Test func compositeRejectsSelectionOutsideImage() {
    #expect(Compositor.image(base: base(px: 200), baseScale: 2, strokes: [], selection: CGRect(x: 500, y: 500, width: 50, height: 50)) == nil)
}

@Test func compositeHighlighterUsesMultiply() {
    let black = Canvas(size: 200, background: RGBA(hex: 0x000000)).ctx.makeImage()!
    let s = Stroke(tool: .highlighter, points: [CGPoint(x: 0, y: 35), CGPoint(x: 100, y: 35)],
                   style: StrokeStyle(color: RGBA(hex: 0xFFFF00), width: 18), finishedAt: 0)
    let out = Compositor.image(base: black, baseScale: 2, strokes: [s], selection: CGRect(x: 10, y: 10, width: 50, height: 50))!
    let c = Canvas(size: 100)
    c.ctx.draw(out, in: CGRect(x: 0, y: 0, width: 100, height: 100))
    let p = c.pixel(50, 50)
    #expect(p.r < 30 && p.g < 30)
}

@Test func compositeRedactIsOneColour() {
    let board = Canvas(size: 200)
    board.ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    board.ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    board.ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    for y in 0..<200 { for x in 0..<200 where (x + y) % 2 == 0 { board.ctx.fill(CGRect(x: x, y: y, width: 1, height: 1)) } }
    let s = Stroke(tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
                   style: StrokeStyle(color: RGBA(hex: 0x808080), width: 0), finishedAt: 0)
    let out = Compositor.image(base: board.ctx.makeImage()!, baseScale: 2, strokes: [s], selection: CGRect(x: 0, y: 0, width: 50, height: 50))!
    let c = Canvas(size: 100)
    c.ctx.draw(out, in: CGRect(x: 0, y: 0, width: 100, height: 100))
    var odd = 0
    for y in 20...79 { for x in 20...79 where c.pixel(x, y) != (128, 128, 128, 255) { odd += 1 } }
    #expect(odd == 0)
}
