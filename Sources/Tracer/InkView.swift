import AppKit
import QuartzCore
import TracerCore

@MainActor
final class InkView: NSView {
    let model = InkModel(mode: .live(delay: 3))
    var tool: Tool = .pen
    var style = StrokeStyle(color: InkPalette.presets[0], width: defaultWidth(for: .pen))
    var onStrokeEnded: ((InkView) -> Void)?
    private var link: CADisplayLink?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static var now: TimeInterval { CACurrentMediaTime() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        model.begin(tool: tool, style: style, at: p, pinned: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        model.extend(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        model.end(at: Self.now)
        onStrokeEnded?(self)
        startFadeLoopIfNeeded()
        needsDisplay = true
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
        InkRenderer.draw(model.strokes, in: ctx) { model.opacity(of: $0, at: t) }
    }
}
