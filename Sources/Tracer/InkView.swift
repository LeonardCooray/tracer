import AppKit
import QuartzCore
import TracerCore

@MainActor
final class InkView: NSView {
    let model = InkModel(mode: .live(delay: 3))
    var tool: Tool = .pen { didSet { needsDisplay = true } }
    var style = StrokeStyle(color: InkPalette.presets[0], width: defaultWidth(for: .pen))
    var fadeDelay = FadeSetting.defaultDelay
    var showsPointerLabel = true
    var showsCursorRing = false { didSet { needsDisplay = true } }
    var onStrokeEnded: ((InkView) -> Void)?
    var onTextClick: ((InkView, NSPoint) -> Void)?
    var onPointerMoved: ((InkView) -> Void)?
    private(set) var pointer: NSPoint?
    private var shiftHeld = false
    private var link: CADisplayLink?

    static let spotlightRadius = 120.0
    static let ringDiameter = 28.0

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static var now: TimeInterval { CACurrentMediaTime() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func track(_ event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        shiftHeld = event.modifierFlags.contains(.shift)
        needsDisplay = true
        onPointerMoved?(self)
    }

    func setPointer(_ p: NSPoint?) {
        pointer = p
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { setPointer(nil) }

    override func mouseDown(with event: NSEvent) {
        track(event)
        let p = convert(event.locationInWindow, from: nil)
        switch tool {
        case .spotlight: return
        case .text: onTextClick?(self, p); return
        default: break
        }
        model.begin(tool: tool, style: style, at: p, pinned: shiftHeld)
    }

    override func mouseDragged(with event: NSEvent) {
        track(event)
        guard tool != .spotlight, tool != .text else { return }
        model.extend(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        track(event)
        guard tool != .spotlight, tool != .text else { return }
        model.end(at: Self.now)
        onStrokeEnded?(self)
        startFadeLoopIfNeeded()
    }

    func addText(_ text: String, baseline: NSPoint, style: StrokeStyle) {
        model.addText(text, at: baseline, style: style, time: Self.now)
        onStrokeEnded?(self)
        startFadeLoopIfNeeded()
        needsDisplay = true
    }

    func finishActiveStroke() {
        guard model.isDrawing else { return }
        model.end(at: Self.now)
        onStrokeEnded?(self)
        startFadeLoopIfNeeded()
        needsDisplay = true
    }

    func removeStroke(id: UUID) -> Bool {
        defer { needsDisplay = true }
        return model.remove(id: id)
    }

    func clear() {
        model.clear()
        needsDisplay = true
    }

    func undo() {
        model.undo()
        needsDisplay = true
    }

    func startFadeLoopIfNeeded() {
        guard link == nil, model.hasFadingStrokes else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        model.prune(at: Self.now)
        needsDisplay = true
        if !model.hasFadingStrokes {
            link?.invalidate()
            link = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = Self.now
        if tool == .spotlight { drawSpotlight(at: pointer, in: ctx) }
        InkRenderer.draw(model.strokes, in: ctx) { model.opacity(of: $0, at: t) }
        guard let p = pointer else { return }
        if showsCursorRing { drawRing(at: p, in: ctx) }
        if showsPointerLabel { drawLabel(pointerLabel(tool: tool, fadeDelay: fadeDelay, shiftHeld: shiftHeld), at: p) }
    }

    // With the pointer on another display, this one is dimmed entirely.
    private func drawSpotlight(at p: NSPoint?, in ctx: CGContext) {
        let r = Self.spotlightRadius
        ctx.saveGState()
        ctx.addRect(bounds)
        if let p { ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private func drawRing(at p: NSPoint, in ctx: CGContext) {
        let d = Self.ringDiameter
        let c = style.color
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
        ctx.restoreGState()
    }

    private func drawLabel(_ text: String, at p: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        let box = NSRect(x: p.x + 16, y: p.y - 16 - size.height - 8, width: size.width + 16, height: size.height + 8)
        NSColor(white: 0.12, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        s.draw(at: NSPoint(x: box.minX + 8, y: box.minY + 4))
    }
}
