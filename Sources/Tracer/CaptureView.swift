import AppKit
import TracerCore

@MainActor
final class FrozenView: NSView {
    var frame_: FrozenFrame? {
        didSet {
            layer?.contents = frame_?.image
            isHidden = frame_ == nil
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class CaptureView: NSView {
    weak var inkView: InkView?
    var format: ImageFormat = .png { didSet { needsDisplay = true } }
    var scale = 2.0
    private(set) var selection: CGRect? { didSet { needsDisplay = true } }
    var armed = false
    var onSelectionChanged: ((CaptureView) -> Void)?

    private enum Drag { case none, creating(CGPoint), moving(CGPoint, CGRect), resizing(CGPoint), drawing }
    private var drag = Drag.none
    private var live: CGRect?
    static let handleSize = 7.0

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reset() {
        selection = nil
        live = nil
        armed = false
        drag = .none
        isHidden = true
    }

    func clearSelection() {
        selection = nil
        live = nil
        onSelectionChanged?(self)
    }

    private var shown: CGRect? { live ?? selection }

    private func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = selection, let i = corners(of: s).firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= 10 }) {
            drag = .resizing(corners(of: s)[3 - i])
        } else if let s = selection, s.insetBy(dx: -6, dy: -6).contains(p), !s.insetBy(dx: 6, dy: 6).contains(p) {
            drag = .moving(p, s)
        } else if let s = selection, s.contains(p) {
            if armed { drag = .drawing; inkView?.mouseDown(with: event) } else { drag = .moving(p, s) }
        } else {
            drag = .creating(p)
            selection = nil
            armed = false
            onSelectionChanged?(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .creating(let a), .resizing(let a):
            live = CGRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(p.x - a.x), height: abs(p.y - a.y))
            needsDisplay = true
        case .moving(let start, let original):
            var r = original.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            selection = r
            onSelectionChanged?(self)
        case .drawing:
            inkView?.mouseDragged(with: event)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .creating(let a), .resizing(let a):
            selection = selectionRect(from: a, to: p)
            live = nil
            onSelectionChanged?(self)
        case .drawing:
            inkView?.mouseUp(with: event)
        default:
            break
        }
        drag = .none
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
        ctx.addRect(bounds)
        if let r = shown { ctx.addRect(r) }
        ctx.fillPath(using: .evenOdd)
        guard let r = shown else { return }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.stroke(r)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let h = Self.handleSize
        for c in corners(of: r) {
            ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - h / 2, y: c.y - h / 2, width: h, height: h),
                               cornerWidth: 2, cornerHeight: 2, transform: nil))
        }
        ctx.fillPath()
        drawChip(sizeLabel(selection: r, scale: scale, format: format), below: r, bold: true)
        if selection != nil { drawHint(above: r) }
    }

    private func chip(_ text: String, bold: Bool) -> (NSAttributedString, NSSize) {
        let s = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: bold ? .semibold : .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(bold ? 1 : 0.85),
        ])
        return (s, s.size())
    }

    private func drawChip(_ text: String, below r: CGRect, bold: Bool) {
        let (s, size) = chip(text, bold: bold)
        var box = NSRect(x: r.minX, y: r.minY - size.height - 16, width: size.width + 14, height: size.height + 6)
        if box.minY < bounds.minY { box.origin.y = r.minY + 8 }
        NSColor(white: 0.12, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        s.draw(at: NSPoint(x: box.minX + 7, y: box.minY + 3))
    }

    private func drawHint(above r: CGRect) {
        let (s, size) = chip("↵ copy · ⌘S save · esc", bold: false)
        var at = NSPoint(x: r.minX, y: r.maxY + 6)
        if at.y + size.height > bounds.maxY { at.y = r.maxY - size.height - 6 }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 3
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        s.draw(at: at)
        NSGraphicsContext.restoreGraphicsState()
    }
}
