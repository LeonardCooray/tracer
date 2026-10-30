import CoreGraphics
import CoreText
import Foundation

public enum InkRenderer {
    public static let highlighterAlpha = 0.4

    public static func draw(_ strokes: [Stroke], in ctx: CGContext, highlighterBlend: CGBlendMode = .normal,
                            opacity: (Stroke) -> Double) {
        for s in strokes {
            let o = opacity(s)
            guard o > 0, let first = s.points.first else { continue }
            ctx.saveGState()
            ctx.setAlpha(o)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setLineWidth(s.style.width)
            let c = s.style.color
            let color = CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            switch s.tool {
            case .pen:
                ctx.addPath(smoothPath(s.points))
                ctx.strokePath()
            case .highlighter:
                ctx.setLineCap(.square)
                ctx.setBlendMode(highlighterBlend)
                ctx.setAlpha(o * highlighterAlpha)
                ctx.addPath(smoothPath(s.points))
                ctx.strokePath()
            case .arrow:
                let end = s.points.last!
                guard hypot(end.x - first.x, end.y - first.y) >= minimumArrowLength else { break }
                let (a, b) = arrowHead(from: first, to: end, width: s.style.width)
                ctx.move(to: first); ctx.addLine(to: end)
                ctx.move(to: a); ctx.addLine(to: end); ctx.addLine(to: b)
                ctx.strokePath()
            case .rectangle:
                let end = s.points.last!
                ctx.stroke(CGRect(x: min(first.x, end.x), y: min(first.y, end.y),
                                  width: abs(end.x - first.x), height: abs(end.y - first.y)))
            case .text:
                drawText(s.text ?? "", at: first, size: s.style.width, color: color, in: ctx)
            case .spotlight:
                break
            }
            ctx.restoreGState()
        }
    }

    public static let minimumArrowLength = 2.0

    // A pen path through the midpoints of successive samples, so fast strokes stay smooth.
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { path.addLine(to: first); return path }
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts.last!)
        return path
    }

    static func attributes(size: Double, color: CGColor) -> [NSAttributedString.Key: Any] {
        [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!,
         NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
    }

    // The point is the baseline origin of the first line.
    static func drawText(_ text: String, at point: CGPoint, size: Double, color: CGColor, in ctx: CGContext) {
        let attrs = attributes(size: size, color: color)
        var y = point.y
        for line in text.components(separatedBy: "\n") {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attrs))
            ctx.textPosition = CGPoint(x: point.x, y: y)
            CTLineDraw(ctLine, ctx)
            y -= size * 1.25
        }
    }
}

// Everything a stroke can paint, for partial redraws.
public func inkBounds(of s: Stroke) -> CGRect {
    guard let first = s.points.first else { return .null }
    let w = s.style.width
    func box(_ pts: [CGPoint], pad: Double) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -pad, dy: -pad)
    }
    switch s.tool {
    case .pen: return box(s.points, pad: w / 2 + 1)
    case .highlighter: return box(s.points, pad: w * 0.75 + 1)
    case .rectangle: return box([first, s.points.last!], pad: w / 2 + 1)
    case .arrow:
        let end = s.points.last!
        let (a, b) = arrowHead(from: first, to: end, width: w)
        return box([first, end, a, b], pad: w / 2 + 1)
    case .text:
        let lines = (s.text ?? "").components(separatedBy: "\n")
        let attrs = InkRenderer.attributes(size: w, color: CGColor(gray: 0, alpha: 1))
        var box = CGRect.null
        for (i, line) in lines.enumerated() {
            let ct = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attrs))
            let baseline = CGPoint(x: first.x, y: first.y - Double(i) * w * 1.25)
            var a: CGFloat = 0, d: CGFloat = 0
            let width = CTLineGetTypographicBounds(ct, &a, &d, nil)
            box = box.union(CGRect(x: baseline.x, y: baseline.y - d, width: width, height: a + d))
            // Glyph paths catch stacked accents that rise above the font's ascent.
            box = box.union(CTLineGetBoundsWithOptions(ct, .useGlyphPathBounds).offsetBy(dx: baseline.x, dy: baseline.y))
        }
        return box.insetBy(dx: -3, dy: -3)
    case .spotlight: return .null
    }
}
