import CoreGraphics
import CoreText
import Foundation

public enum InkRenderer {
    public static let highlighterAlpha = 0.4

    public static func draw(_ strokes: [Stroke], in ctx: CGContext, opacity: (Stroke) -> Double) {
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
                ctx.setAlpha(o * highlighterAlpha)
                ctx.addPath(smoothPath(s.points))
                ctx.strokePath()
            case .arrow:
                let end = s.points.last!
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

    // The point is the baseline origin of the first line.
    static func drawText(_ text: String, at point: CGPoint, size: Double, color: CGColor, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        var y = point.y
        for line in text.components(separatedBy: "\n") {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attrs))
            ctx.textPosition = CGPoint(x: point.x, y: y)
            CTLineDraw(ctLine, ctx)
            y -= size * 1.25
        }
    }
}
