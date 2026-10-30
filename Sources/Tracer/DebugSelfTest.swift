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
            case "capture": await capture(c)
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

    final class FakeCapturer: ScreenCapturing {
        var hasPermission: Bool { true }
        func requestPermission() {}
        func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] {
            var out: [CGDirectDisplayID: FrozenFrame] = [:]
            for s in NSScreen.screens {
                guard let id = s.displayID else { continue }
                let scale = s.backingScaleFactor
                let w = Int(s.frame.width * scale), h = Int(s.frame.height * scale)
                let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                out[id] = FrozenFrame(image: ctx.makeImage()!, scale: scale)
            }
            return out
        }
    }

    static func capture(_ c: AppController) async {
        c.capturer = FakeCapturer()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tracer-selftest-\(UUID().uuidString)")
        c.saveFolder = tmp
        c.requestCapture()
        await pause(0.5)
        guard let (id, cv) = c.overlays.captureViews.first, let v = c.overlays.inkViews[id],
              let screen = c.overlays.screen(of: id), let w = cv.window else { return }
        check(c.session.mode == .capturing, "capture hotkey enters capturing")
        check(c.overlays.frozenViews[id]?.isHidden == false && !cv.isHidden, "screen frozen and selection layer shown")
        check(!c.dock.isVisible, "no dock before a selection")
        check(!v.showsCursorRing && !v.showsPointerLabel, "no cursor ring or label over a capture")

        func dragCV(_ a: NSPoint, _ b: NSPoint) {
            cv.mouseDown(with: mouse(.leftMouseDown, a, in: w))
            for t in stride(from: 0.2, through: 1, by: 0.2) {
                cv.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), in: w))
            }
            cv.mouseUp(with: mouse(.leftMouseUp, b, in: w))
        }

        dragCV(NSPoint(x: 300, y: 300), NSPoint(x: 300, y: 300))
        check(cv.selection == nil && !c.dockState.canOutput, "click without drag makes no selection")
        dragCV(NSPoint(x: 302, y: 302), NSPoint(x: 304, y: 305))
        check(cv.selection == nil, "tiny drag makes no selection")

        dragCV(NSPoint(x: 300, y: 300), NSPoint(x: 700, y: 600))
        check(cv.selection == CGRect(x: 300, y: 300, width: 400, height: 300), "drag makes selection (\(String(describing: cv.selection)))")
        check(c.dock.isVisible && c.dockState.canOutput && c.dockState.mode == .capturing, "dock appears with copy/save enabled")
        check(abs(c.dock.frame.minX - (screen.frame.minX + 708)) < 1 && abs(c.dock.frame.maxY - (screen.frame.minY + 600)) < 1,
              "dock snapped beside selection (\(c.dock.frame))")

        dragCV(NSPoint(x: 500, y: 450), NSPoint(x: 520, y: 470))
        check(cv.selection == CGRect(x: 320, y: 320, width: 400, height: 300), "drag inside moves selection before a tool is picked")
        dragCV(NSPoint(x: 720, y: 620), NSPoint(x: 760, y: 640))
        check(cv.selection == CGRect(x: 320, y: 320, width: 440, height: 320), "corner drag resizes (\(String(describing: cv.selection)))")

        c.send(.command(.selectTool(.spotlight)))
        check(c.tool != .spotlight, "spotlight not selectable in capture")
        c.send(.command(.selectTool(.arrow)))
        dragCV(NSPoint(x: 400, y: 400), NSPoint(x: 600, y: 500))
        check(v.model.strokes.count == 1 && v.model.strokes[0].tool == .arrow, "with a tool picked, drag inside draws")
        check(v.model.opacity(of: v.model.strokes[0], at: InkView.now + 100) == 1, "capture ink never fades")
        let before = cv.selection

        c.send(.command(.copy))
        await pause(0.2)
        check(c.session.mode == .idle && !(c.overlays.panels[id]?.isVisible ?? true), "copy ends capture and hides overlays")
        let data = NSPasteboard.general.data(forType: .png)
        let rep = data.flatMap { NSBitmapImageRep(data: $0) }
        let sel = before!
        check(rep?.pixelsWide == Int(sel.width * screen.backingScaleFactor) && rep?.pixelsHigh == Int(sel.height * screen.backingScaleFactor),
              "clipboard PNG at full Retina size (\(rep?.pixelsWide ?? 0)×\(rep?.pixelsHigh ?? 0))")
        var red = 0
        if let rep { for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            if let px = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), px.redComponent > 0.8, px.greenComponent < 0.4 { red += 1 }
        } } }
        check(red > 20, "clipboard image includes the arrow")

        c.format = .jpeg
        c.requestCapture()
        await pause(0.5)
        dragCV(NSPoint(x: 100, y: 100), NSPoint(x: 300, y: 250))
        c.send(.command(.save))
        await pause(0.2)
        let saved = c.lastSavedURL
        check(saved?.pathExtension == "jpg" && saved.map { FileManager.default.fileExists(atPath: $0.path) } == true,
              "save writes a dated JPEG to the folder (\(saved?.lastPathComponent ?? "nil"))")
        check(saved?.lastPathComponent.hasPrefix("Tracer ") == true, "file named by date and time")
        c.format = .png

        c.send(.penHotkey)
        drag(v, from: NSPoint(x: 200, y: 200), to: NSPoint(x: 400, y: 200))
        c.requestCapture()
        await pause(0.5)
        check(c.session.mode == .capturing && v.model.strokes.count == 1, "capture from drawing keeps the ink")
        c.send(.escape)
        check(c.session.mode == .idle && v.model.strokes.isEmpty, "escape cancels capture")
        try? FileManager.default.removeItem(at: tmp)
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
