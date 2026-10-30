import AppKit
import TracerCore

@MainActor
final class TextEntryController: NSObject, NSTextFieldDelegate {
    private var field: NSTextField?
    private weak var view: InkView?
    private var style: StrokeStyle?
    var onBegan: () -> Void = {}
    private var returnTo: NSRunningApplication?
    var onEnded: () -> Void = {}

    var isEditing: Bool { field != nil }

    static func font(size: Double) -> NSFont { .boldSystemFont(ofSize: size) }

    // The click point becomes the text's baseline origin, matching InkRenderer.
    func begin(at point: NSPoint, in view: InkView, style: StrokeStyle) {
        commit()
        guard let panel = view.window as? OverlayPanel else { return }
        let font = Self.font(size: style.width)
        let f = NSTextField(string: "")
        f.font = font
        f.textColor = NSColor(srgbRed: style.color.r, green: style.color.g, blue: style.color.b, alpha: style.color.a)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.isBezeled = false
        f.placeholderString = "Type, then ↩"
        f.delegate = self
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        let height = ceil(font.ascender - font.descender) + 4
        f.frame = NSRect(x: point.x - 2, y: point.y + font.descender - 2, width: 600, height: height)
        view.addSubview(f)
        field = f
        self.view = view
        self.style = style
        panel.allowsKey = true
        let front = NSWorkspace.shared.frontmostApplication
        returnTo = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(f)
        onBegan()
    }

    func commit() {
        guard let f = field, let v = view, let s = style else { return }
        let text = f.stringValue
        let font = f.font ?? Self.font(size: s.width)
        let baseline = NSPoint(x: f.frame.minX + 2, y: f.frame.minY + 2 - font.descender)
        finish()
        if !text.isEmpty { v.addText(text, baseline: baseline, style: s) }
    }

    func cancel() {
        guard field != nil else { return }
        finish()
    }

    private func finish() {
        let panel = view?.window as? OverlayPanel
        field?.removeFromSuperview()
        field = nil
        panel?.allowsKey = false
        onEnded()
        if let app = returnTo { app.activate() } else { NSApp.deactivate() }
        returnTo = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commit(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancel(); return true
        default: return false
        }
    }
}
