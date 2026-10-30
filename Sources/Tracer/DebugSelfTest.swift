#if DEBUG
import AppKit
import TracerCore

// Debug-only smoke test: `Tracer --self-test live` drives the real overlays and prints PASS/FAIL lines.
@MainActor
enum DebugSelfTest {
    static func runIfRequested(_ c: AppController) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-test"), i + 1 < args.count else { return }
        Task { @MainActor in
            switch args[i + 1] {
            case "live": await live(c)
            case "tools": await tools(c)
            default: print("FAIL unknown self-test")
            }
            exit(0)
        }
    }

    static func check(_ ok: Bool, _ name: String) { print(ok ? "PASS \(name)" : "FAIL \(name)") }

    static func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static func mouse(_ type: NSEvent.EventType, _ p: NSPoint, in w: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func drag(_ v: InkView, from a: NSPoint, to b: NSPoint, shift: Bool = false) {
        let w = v.window!
        let f: NSEvent.ModifierFlags = shift ? .shift : []
        v.mouseDown(with: mouse(.leftMouseDown, a, in: w, flags: f))
        for t in stride(from: 0.1, through: 1, by: 0.1) {
            v.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), in: w))
        }
        v.mouseUp(with: mouse(.leftMouseUp, b, in: w))
    }

    static func painted(_ v: InkView, at p: NSPoint, minAlpha: Double = 0.5) -> Bool {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return false }
        v.cacheDisplay(in: v.bounds, to: rep)
        let sx = Double(rep.pixelsWide) / v.bounds.width, sy = Double(rep.pixelsHigh) / v.bounds.height
        let color = rep.colorAt(x: Int(p.x * sx), y: rep.pixelsHigh - 1 - Int(p.y * sy))
        return (color?.alphaComponent ?? 0) > minAlpha
    }

    static func ownWindowCount() -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }.count
    }

    static func pixel(_ v: InkView, at p: NSPoint) -> NSColor? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        let sx = Double(rep.pixelsWide) / v.bounds.width, sy = Double(rep.pixelsHigh) / v.bounds.height
        return rep.colorAt(x: Int(p.x * sx), y: rep.pixelsHigh - 1 - Int(p.y * sy))?.usingColorSpace(.sRGB)
    }

    static func tools(_ c: AppController) async {
        c.send(.penHotkey)
        await pause(0.5)
        guard let v = c.overlays.inkViews.values.first, let screen = v.window?.screen else { return }
        let d = c.dock.frame
        check(c.dock.isVisible, "dock visible while drawing")
        check(abs(d.maxX - (screen.visibleFrame.maxX - 10)) < 2 && abs(d.midY - screen.visibleFrame.midY) < 2,
              "dock on right edge, vertically centred (\(d))")
        check(d.height > d.width * 4, "dock is a slim vertical column (\(d.size))")

        for (digit, tool) in [(2, Tool.highlighter), (3, .arrow), (4, .rectangle)] {
            c.send(.command(command(for: .digit(digit), mode: .drawing, isEditingText: false)!))
            check(c.tool == tool && c.dockState.tool == tool, "key \(digit) selects \(tool.displayName)")
            c.send(.command(.clearAll))
            drag(v, from: NSPoint(x: 200, y: 300), to: NSPoint(x: 600, y: 360))
            check(v.model.strokes.count == 1 && v.model.strokes[0].tool == tool, "\(tool.displayName) stroke recorded")
            check(painted(v, at: NSPoint(x: 200, y: 300), minAlpha: 0.2) || painted(v, at: NSPoint(x: 600, y: 360), minAlpha: 0.2), "\(tool.displayName) paints")
        }
        c.send(.command(.clearAll))

        c.setColor(InkPalette.presets[3])
        check(v.style.color == InkPalette.presets[3] && c.dockState.color == InkPalette.presets[3], "colour applies to ink and dock")

        c.send(.command(.selectTool(.spotlight)))
        v.setPointer(NSPoint(x: 500, y: 500))
        drag(v, from: NSPoint(x: 500, y: 500), to: NSPoint(x: 520, y: 520))
        check(v.model.strokes.isEmpty, "spotlight never stores strokes")
        let far = pixel(v, at: NSPoint(x: 50, y: 50))
        let near = pixel(v, at: NSPoint(x: 520, y: 520))
        check((far?.alphaComponent ?? 0) > 0.4, "spotlight dims away from pointer")
        check((near?.alphaComponent ?? 1) < 0.3 || near == nil, "spotlight clear around pointer")

        c.send(.command(.selectTool(.pen)))
        v.setPointer(NSPoint(x: 700, y: 700))
        check(painted(v, at: NSPoint(x: 700 + InkView.ringDiameter / 2, y: 700)), "cursor ring drawn at pointer")
        check(painted(v, at: NSPoint(x: 725, y: 675)), "pointer label drawn beside pointer")

        c.send(.command(.selectTool(.text)))
        v.onTextClick?(v, NSPoint(x: 300, y: 200))
        await pause(0.2)
        check(c.text.isEditing && c.session.isEditingText, "text click starts editing")
        check(v.window?.isKeyWindow == true, "overlay takes keyboard focus for text")
        if let field = v.subviews.compactMap({ $0 as? NSTextField }).first { field.stringValue = "Look here 123" }
        c.text.commit()
        check(!c.session.isEditingText, "commit ends editing")
        check(v.model.strokes.last?.text == "Look here 123", "typed text stored (digits typed, not tools)")
        check(painted(v, at: NSPoint(x: 310, y: 205)), "text paints")
        check(v.window?.isKeyWindow != true || !(v.window as! OverlayPanel).allowsKey, "overlay gives up key status after text")

        v.onTextClick?(v, NSPoint(x: 300, y: 600))
        c.send(.escape)
        check(c.session.mode == .drawing, "escape while typing keeps the pen on")
        c.text.cancel()
        check(!c.text.isEditing && !c.session.isEditingText, "cancel drops the text box")

        c.send(.penHotkey)
        await pause(0.4)
        check(!c.dock.isVisible, "dock hidden after drawing ends")
    }

    static func live(_ c: AppController) async {
        check(c.hotkeyWarnings.isEmpty, "global hotkeys registered \(c.hotkeyWarnings)")
        c.send(.penHotkey)
        await pause(0.3)
        let panels = Array(c.overlays.panels.values)
        check(c.session.mode == .drawing, "pen hotkey enters drawing")
        check(panels.count == NSScreen.screens.count, "one overlay per screen (\(panels.count)/\(NSScreen.screens.count))")
        check(panels.allSatisfy { $0.isVisible && !$0.ignoresMouseEvents && $0.level == .screenSaver }, "overlays visible, interactive, screen-saver level")
        check(ownWindowCount() >= panels.count, "window server shows overlay windows")
        check(NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier, "drawing doesn't steal focus")

        guard let v = c.overlays.inkViews.values.first else { return }
        drag(v, from: NSPoint(x: 200, y: 300), to: NSPoint(x: 600, y: 300))
        drag(v, from: NSPoint(x: 200, y: 500), to: NSPoint(x: 600, y: 500), shift: true)
        check(painted(v, at: NSPoint(x: 400, y: 300)), "stroke paints on screen")
        await pause(3.8)
        check(!painted(v, at: NSPoint(x: 400, y: 300)), "stroke faded after ~3s")
        check(painted(v, at: NSPoint(x: 400, y: 500)), "shift stroke stays")
        check(v.model.strokes.count == 1, "faded stroke pruned")

        c.send(.command(.undo))
        check(v.model.strokes.isEmpty, "undo removes last stroke")
        drag(v, from: NSPoint(x: 200, y: 400), to: NSPoint(x: 600, y: 400), shift: true)
        c.send(.command(.clearAll))
        check(v.model.strokes.isEmpty, "clear removes all")

        c.send(.penHotkey)
        await pause(0.3)
        check(c.session.mode == .idle, "pen hotkey again leaves drawing")
        check(panels.allSatisfy { !$0.isVisible && $0.ignoresMouseEvents }, "overlays hidden and click-through")

        c.send(.penHotkey)
        drag(v, from: NSPoint(x: 200, y: 300), to: NSPoint(x: 600, y: 300), shift: true)
        c.send(.escape)
        check(c.session.mode == .idle && v.model.strokes.isEmpty, "escape leaves drawing and clears ink")
    }
}
#endif
