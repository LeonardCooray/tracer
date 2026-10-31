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
    var acceptsInput = true
    private var shiftHeld = false
    private var link: CADisplayLink?

    static let spotlightRadius = 120.0
    static let ringDiameter = 28.0

    #if DEBUG
    var largestInvalidation: CGFloat = 0
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        largestInvalidation = max(largestInvalidation, invalidRect.width * invalidRect.height)
        super.setNeedsDisplay(invalidRect)
    }
    #endif

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
        let old = pointer
        pointer = convert(event.locationInWindow, from: nil)
        shiftHeld = event.modifierFlags.contains(.shift)
        invalidatePointer(from: old)
        onPointerMoved?(self)
    }

    func setPointer(_ p: NSPoint?) {
        let old = pointer
        pointer = p
        invalidatePointer(from: old)
    }

    // Only the ring and label around the old and new pointer change, unless the spotlight is on.
    private func invalidatePointer(from old: NSPoint?) {
        if spotlightShown { needsDisplay = true; return }
        for p in [old, pointer].compactMap({ $0 }) { setNeedsDisplay(chromeRect(at: p)) }
    }

    private func chromeRect(at p: NSPoint) -> NSRect {
        let ring = Self.ringDiameter / 2 + 3
        var r = NSRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)
        if showsPointerLabel {
            for shift in [false, true] {
                let text = pointerLabel(tool: tool, fadeDelay: fadeDelay, shiftHeld: shift)
                r = r.union(labelBox(for: text, at: p).insetBy(dx: -2, dy: -2))
            }
        }
        return r
    }

    private func invalidateActiveStroke() {
        if let s = model.strokes.last { setNeedsDisplay(inkBounds(of: s)) }
    }

    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { setPointer(nil) }

    // The spotlight belongs to live drawing; an idle cursor ring never shows it.
    private var spotlightShown: Bool { tool == .spotlight && showsPointerLabel }

    override func mouseDown(with event: NSEvent) {
        track(event)
        guard acceptsInput else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch tool {
        case .spotlight: return
        case .text: onTextClick?(self, p); return
        default: break
        }
        model.begin(tool: tool, style: style, at: p, pinned: shiftHeld)
        invalidateActiveStroke()
    }

    override func mouseDragged(with event: NSEvent) {
        track(event)
        guard acceptsInput, model.isDrawing else { return }
        let before = model.strokes.last.map(inkBounds(of:))
        model.extend(to: convert(event.locationInWindow, from: nil))
        guard let s = model.strokes.last else { return }
        if s.tool == .pen || s.tool == .highlighter {
            // Only the newest segments change; smoothing reaches back two points.
            setNeedsDisplay(inkBounds(of: Stroke(tool: s.tool, points: Array(s.points.suffix(4)), style: s.style)))
        } else {
            if let before { setNeedsDisplay(before) }
            invalidateActiveStroke()
        }
    }

    override func mouseUp(with event: NSEvent) {
        track(event)
        guard acceptsInput, model.isDrawing else { return }
        endActiveStroke()
    }

    private func endActiveStroke() {
        model.end(at: Self.now)
        invalidateActiveStroke()
        if let s = model.strokes.last, s.tool == .arrow, let a = s.points.first, let b = s.points.last,
           hypot(b.x - a.x, b.y - a.y) < InkRenderer.minimumArrowLength {
            model.remove(id: s.id)
            return
        }
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
        endActiveStroke()
    }

    func takeStroke(id: UUID) -> Stroke? {
        defer { needsDisplay = true }
        return model.take(id: id)
    }

    func restoreStroke(_ stroke: Stroke) {
        model.restore(stroke, at: Self.now)
        startFadeLoopIfNeeded()
        needsDisplay = true
    }

    func clear() {
        model.clear()
        needsDisplay = true
    }

    func startFadeLoopIfNeeded() {
        guard link == nil, model.hasFadingStrokes else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        let t = Self.now
        let changing = model.strokes.filter { model.opacity(of: $0, at: t) < 1 }
        model.prune(at: t)
        for s in changing { setNeedsDisplay(inkBounds(of: s)) }
        if !model.hasFadingStrokes {
            link?.invalidate()
            link = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = Self.now
        if spotlightShown { drawSpotlight(at: pointer, in: ctx) }
        let visible = model.strokes.filter { inkBounds(of: $0).intersects(dirtyRect) }
        InkRenderer.draw(visible, in: ctx) { model.opacity(of: $0, at: t) }
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

    private static let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
    ]

    private func labelBox(for text: String, at p: NSPoint) -> NSRect {
        let size = NSAttributedString(string: text, attributes: Self.labelAttrs).size()
        return NSRect(x: p.x + 16, y: p.y - 16 - size.height - 8, width: size.width + 16, height: size.height + 8)
    }

    private func drawLabel(_ text: String, at p: NSPoint) {
        let box = labelBox(for: text, at: p)
        NSColor(white: 0.12, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        NSAttributedString(string: text, attributes: Self.labelAttrs).draw(at: NSPoint(x: box.minX + 8, y: box.minY + 4))
    }

}
