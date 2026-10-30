#if DEBUG
import AppKit
import TracerCore

// Debug-only smoke test: `Tracer --self-test live` drives the real overlays and prints PASS/FAIL lines.
@MainActor
enum DebugSelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--self-test") }

    // Self-tests never touch the real preferences.
    static func isolatedDefaults() -> UserDefaults {
        let name = "com.leonardcooray.tracer.selftest"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func runIfRequested(_ c: AppController) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-test"), i + 1 < args.count else { return }
        Task { @MainActor in
            switch args[i + 1] {
            case "live": await live(c)
            case "tools": await tools(c)
            case "capture": await capture(c)
            case "settings": await settings(c)
            case "displays": await displays(c)
            case "review": await review(c)
            case "text": await textEdits(c)
            case "capture2": await capture2(c)
            case "displays2": await displays2(c)
            case "keys": await keys(c)
            case "redraw": await redraw(c)
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
        await pause(0.4)
        check(v.window?.isKeyWindow != true, "overlay gives up key status after text")

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

    static func settings(_ c: AppController) async {
        let original = c.settings
        defer { c.update(original) }
        var s = original
        s.penHotkey = Hotkey(keyCode: KeyCode.d, modifiers: Hotkey.control | Hotkey.option)
        s.fadeDelay = 5
        s.format = .jpeg
        c.update(s)
        check(c.hotkeyWarnings.isEmpty, "changed hotkey registers without relaunch \(c.hotkeyWarnings)")
        check(c.store.load() == c.settings, "settings persisted")
        check(c.format == .jpeg, "format applied")
        c.send(.penHotkey)
        check(c.overlays.inkViews.values.allSatisfy { $0.model.mode == .live(delay: 5) }, "fade delay applied to new drawing")
        c.send(.penHotkey)

        var bad = c.settings
        bad.captureHotkey = Hotkey(keyCode: KeyCode.four, modifiers: Hotkey.shift | Hotkey.command)
        c.update(bad)
        check(c.settings.captureHotkey == .defaultCapture, "reserved ⇧⌘4 rejected")

        var ring = c.settings
        ring.cursorRingAlwaysOn = true
        c.update(ring)
        await pause(0.2)
        let panels = Array(c.overlays.panels.values)
        check(panels.allSatisfy { $0.isVisible && $0.ignoresMouseEvents }, "idle cursor ring shows click-through overlays")
        check(c.overlays.inkViews.values.allSatisfy { $0.showsCursorRing && !$0.showsPointerLabel }, "ring on, label off while idle")
        c.send(.penHotkey)
        check(panels.allSatisfy { !$0.ignoresMouseEvents }, "drawing still takes the mouse with ring setting on")
        c.send(.penHotkey)
        await pause(0.2)
        check(panels.allSatisfy { $0.isVisible && $0.ignoresMouseEvents }, "back to click-through ring after drawing")
        ring.cursorRingAlwaysOn = false
        c.update(ring)
        check(panels.allSatisfy { !$0.isVisible }, "ring off hides overlays")

        c.settingsWindow.show()
        await pause(0.5)
        let w = c.settingsWindow.window
        check(w?.isVisible == true && w?.title == "Tracer Settings", "settings window opens")
        check((w?.frame.height ?? 0) > 200, "settings window has content (\(w?.frame.size ?? .zero))")
        w?.close()
    }

    static func displays(_ c: AppController) async {
        c.send(.penHotkey)
        await pause(0.4)
        guard let (id, v) = c.overlays.inkViews.first else { return }
        drag(v, from: NSPoint(x: 200, y: 300), to: NSPoint(x: 600, y: 300), shift: true)
        c.screensChanged()
        await pause(0.4)
        check(c.overlays.inkViews[id] === v && v.model.strokes.count == 1, "display change keeps ink on remaining screens")
        check(c.overlays.panels.count == NSScreen.screens.count, "overlay count matches displays after change")
        check(c.overlays.panels.values.allSatisfy { $0.isVisible && !$0.ignoresMouseEvents }, "overlays stay up and interactive")
        check(c.dock.isVisible, "dock still shown")
        c.send(.command(.undo))
        check(v.model.strokes.isEmpty, "undo still works after display change")
        c.send(.penHotkey)

        c.capturer = FakeCapturer()
        c.requestCapture()
        await pause(0.4)
        c.screensChanged()
        check(c.session.mode == .capturing, "a no-op screen notification keeps the capture")
        c.screensChanged(force: true)
        check(c.session.mode == .idle, "display change cancels an in-progress capture")
        check(c.overlays.panels.values.allSatisfy { !$0.isVisible }, "overlays hidden after cancelled capture")
    }

    final class DeniedCapturer: ScreenCapturing {
        var hasPermission: Bool { false }
        func requestPermission() {}
        func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] { [:] }
    }

    static func review(_ c: AppController) async {
        var alerts: [(String, AppMode, Bool)] = []
        c.presentAlert = { title, _, _ in
            alerts.append((title, c.session.mode, c.overlays.panels.values.contains { $0.isVisible && !$0.ignoresMouseEvents }))
        }

        // Permission alert while drawing must be reachable: no interactive overlay above it.
        c.markScreenRecordingPromptShown()
        c.capturer = DeniedCapturer()
        c.send(.penHotkey)
        c.requestCapture()
        check(alerts.count == 1 && alerts[0].1 == .idle && !alerts[0].2, "permission alert shown with no interactive overlay above it")
        if c.session.mode != .idle { c.send(.escape) }

        // Copy/Save with no selection are no-ops.
        c.capturer = FakeCapturer()
        c.requestCapture()
        await pause(0.4)
        c.send(.command(.copy))
        check(c.session.mode == .capturing, "copy with no selection keeps capture open")
        c.send(.command(.save))
        check(c.session.mode == .capturing, "save with no selection keeps capture open")

        // A failed save keeps the capture and says so.
        guard let (_, cv) = c.overlays.captureViews.first, let w = cv.window else { return }
        func dragCV(_ a: NSPoint, _ b: NSPoint, flags: NSEvent.ModifierFlags = []) {
            cv.mouseDown(with: mouse(.leftMouseDown, a, in: w, flags: flags))
            for t in stride(from: 0.25, through: 1, by: 0.25) {
                cv.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), in: w, flags: flags))
            }
            cv.mouseUp(with: mouse(.leftMouseUp, b, in: w, flags: flags))
        }
        dragCV(NSPoint(x: 300, y: 300), NSPoint(x: 700, y: 600))
        let fm = FileManager.default
        let locked = fm.temporaryDirectory.appendingPathComponent("tracer-locked-\(UUID().uuidString)")
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let savedFolder = c.saveFolder
        c.saveFolder = locked.appendingPathComponent("a")
        c.output.fallbackFolder = locked.appendingPathComponent("b")
        alerts.removeAll()
        c.send(.command(.save))
        check(c.session.mode == .capturing, "failed save keeps capture open")
        check(alerts.count == 1, "failed save shows a message (\(alerts.map(\.0)))")
        c.saveFolder = savedFolder
        c.output.fallbackFolder = OutputController.defaultFolder
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try? fm.removeItem(at: locked)

        // Selection can be moved after a tool is picked, by dragging its outline.
        c.send(.command(.selectTool(.arrow)))
        dragCV(NSPoint(x: 400, y: 400), NSPoint(x: 500, y: 450))
        let inkCount = c.overlays.inkViews.values.first?.model.strokes.count
        let before = cv.selection!
        dragCV(NSPoint(x: before.minX + 100, y: before.maxY), NSPoint(x: before.minX + 140, y: before.maxY - 30))
        check(cv.selection == before.offsetBy(dx: 40, dy: -30), "outline drag moves selection after drawing (\(String(describing: cv.selection)))")
        check(c.overlays.inkViews.values.first?.model.strokes.count == inkCount, "moving doesn't draw")

        // JPEG copies paste everywhere.
        c.format = .jpeg
        c.send(.command(.copy))
        let types = NSPasteboard.general.types ?? []
        check(types.contains(NSPasteboard.PasteboardType("public.jpeg")) && types.contains(.tiff), "JPEG copy also offers TIFF (\(types.map(\.rawValue)))")
        c.format = .png

        // Leaving Settings mid-recording restores the global hotkeys.
        c.settingsWindow.show()
        await pause(0.3)
        c.settingsModel.onRecording(true)
        check(!c.globalHotkeysRegistered, "recording suspends global hotkeys")
        c.settingsWindow.window?.close()
        await pause(0.2)
        check(c.globalHotkeysRegistered, "closing Settings mid-recording restores global hotkeys")

        // Failed registration wording.
        let squatter = HotkeyCenter()
        _ = c.hotkeyWarnings
        c.settingsModel.onRecording(true)
        _ = squatter.register(c.settings.penHotkey, id: 77) {}
        c.settingsModel.onRecording(false)
        check(c.hotkeyWarnings.first?.contains("couldn't be registered") == true, "failed hotkey says it couldn't be registered (\(c.hotkeyWarnings))")
        squatter.unregister(id: 77)
        c.settingsModel.onRecording(false)
    }

    static func textEdits(_ c: AppController) async {
        c.send(.penHotkey)
        await pause(0.3)
        guard let v = c.overlays.inkViews.values.first else { return }
        func type(_ s: String) { v.subviews.compactMap { $0 as? NSTextField }.first?.stringValue = s }

        c.send(.command(.selectTool(.text)))
        v.onTextClick?(v, NSPoint(x: 300, y: 300))
        type("first")
        v.onTextClick?(v, NSPoint(x: 600, y: 600))
        check(v.model.strokes.last?.text == "first", "click elsewhere commits the text")
        check(!c.text.isEditing, "click elsewhere doesn't open another box")
        check(c.sessionKeyCount > 0, "session keys back after the click-away commit")

        v.onTextClick?(v, NSPoint(x: 300, y: 400))
        type("before capture")
        c.capturer = FakeCapturer()
        c.requestCapture()
        await pause(0.4)
        check(v.model.strokes.contains { $0.text == "before capture" }, "capture hotkey while typing keeps the text")
        check(!c.text.isEditing && !c.session.isEditingText, "capture hotkey while typing closes the box")
        check(c.sessionKeyCount > 0, "capture keys registered after the box closes")

        c.send(.command(.selectTool(.text)))
        if let cv = c.overlays.captureViews.values.first, let w = cv.window {
            cv.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100), in: w))
            cv.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 400, y: 400), in: w))
        }
        v.onTextClick?(v, NSPoint(x: 200, y: 200))
        check(c.text.isEditing, "typing in capture")
        c.screensChanged(force: true)
        check(!c.text.isEditing && c.session.mode == .idle, "display change mid-typing closes the box and the capture")
        c.requestCapture()
        await pause(0.4)
        check(c.sessionKeyCount > 0, "next capture still has its keys")
        c.send(.escape)
    }

    final class CountingDenied: ScreenCapturing {
        var requests = 0
        var hasPermission: Bool { false }
        func requestPermission() { requests += 1 }
        func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] { [:] }
    }

    struct Boom: Error {}

    final class FailingCapturer: ScreenCapturing {
        var hasPermission: Bool { true }
        func requestPermission() {}
        func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] { throw Boom() }
    }

    final class SlowCapturer: ScreenCapturing {
        let delay: Double, scale: Double
        init(delay: Double, scale: Double) { self.delay = delay; self.scale = scale }
        var hasPermission: Bool { true }
        func requestPermission() {}
        func captureAll() async throws -> [CGDirectDisplayID: FrozenFrame] {
            try await Task.sleep(for: .seconds(delay))
            var out = try await FakeCapturer().captureAll()
            for (k, f) in out { out[k] = FrozenFrame(image: f.image, scale: scale) }
            return out
        }
    }

    static func capture2(_ c: AppController) async {
        var alerts: [String] = []
        c.presentAlert = { t, _, _ in alerts.append(t) }
        c.resetScreenRecordingPrompt()

        let denied = CountingDenied()
        c.capturer = denied
        c.requestCapture()
        check(denied.requests == 1 && alerts.isEmpty, "first capture shows only the system prompt (\(alerts))")
        c.requestCapture()
        check(alerts.count == 1, "later captures show Tracer's alert")

        alerts.removeAll()
        c.capturer = FailingCapturer()
        c.requestCapture()
        await pause(0.3)
        check(alerts.first == "Couldn't capture the screen", "a capture error isn't blamed on permission (\(alerts))")
        check(c.session.mode == .idle, "failed capture returns to idle")

        c.capturer = SlowCapturer(delay: 0.6, scale: 7)
        c.requestCapture()
        await pause(0.1)
        check(c.overlays.panels.values.allSatisfy { $0.ignoresMouseEvents }, "no clicks reach the overlay before frames arrive")
        c.send(.escape)
        c.capturer = SlowCapturer(delay: 0.1, scale: 2)
        c.requestCapture()
        await pause(1.0)
        check(c.frames.values.allSatisfy { $0.scale == 2 }, "a stale capture can't replace the newer one")
        check(c.overlays.panels.values.allSatisfy { !$0.ignoresMouseEvents }, "overlay takes clicks once frames arrive")
        c.send(.escape)
    }

    static func displays2(_ c: AppController) async {
        let original = c.settings
        defer { c.update(original) }
        var s = original
        s.fadeDelay = 5
        c.update(s)
        c.send(.penHotkey)
        await pause(0.3)
        c.overlays.forgetPanels()
        c.screensChanged(force: true)
        check(!c.overlays.inkViews.isEmpty && c.overlays.inkViews.values.allSatisfy { $0.model.mode == .live(delay: 5) },
              "overlays added mid-drawing use the fade setting")

        guard let screen = NSScreen.screens.first else { return }
        c.dock.setFrame(c.dock.frame.offsetBy(dx: -5000, dy: 0), display: false)
        c.screensChanged(force: true)
        await pause(0.4)
        check(screen.visibleFrame.contains(c.dock.frame), "dock moves back on screen after a display change (\(c.dock.frame))")

        guard let v = c.overlays.inkViews.values.first else { return }
        c.send(.command(.selectTool(.spotlight)))
        v.setPointer(nil)
        check((pixel(v, at: NSPoint(x: 100, y: 100))?.alphaComponent ?? 0) > 0.4, "spotlight dims displays the pointer isn't on")
        c.send(.command(.selectTool(.pen)))
        c.send(.penHotkey)

        c.dock.slideIn(onRightEdgeOf: screen)
        c.dock.slideOut()
        c.dock.slideIn(onRightEdgeOf: screen)
        await pause(0.5)
        check(c.dock.isVisible, "a quick off/on leaves the dock showing")
        c.dock.orderOut(nil)
    }

    static func keys(_ c: AppController) async {
        c.send(.penHotkey)
        await pause(0.3)
        guard let v = c.overlays.inkViews.values.first, let w = v.window else { return }
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100), in: w))
        v.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 300, y: 100), in: w))
        c.send(.command(.selectTool(.spotlight)))
        check(!v.model.isDrawing && v.model.strokes.last?.finishedAt != nil, "switching tool mid-drag finishes the stroke")
        c.send(.command(.undo))
        check(v.model.strokes.isEmpty, "undo removes the stroke finished by the tool switch")
        c.send(.command(.selectTool(.pen)))
        c.send(.penHotkey)

        let squatter = HotkeyCenter()
        _ = squatter.register(Hotkey(keyCode: KeyCode.one, modifiers: 0), id: 88, exclusive: true) {}
        c.send(.penHotkey)
        check(c.sessionKeyWarnings.contains { $0.contains("1") }, "session keys that can't register are reported (\(c.sessionKeyWarnings))")
        c.send(.penHotkey)
        squatter.unregister(id: 88)
        c.send(.penHotkey)
        check(c.sessionKeyWarnings.isEmpty, "warning clears once the key is free")
        c.send(.penHotkey)
    }

    static func redraw(_ c: AppController) async {
        c.send(.penHotkey)
        await pause(0.3)
        guard let v = c.overlays.inkViews.values.first, let w = v.window else { return }
        let full = v.bounds.width * v.bounds.height
        func share() -> CGFloat {
            let f = v.largestInvalidation / full
            return f.isFinite ? min(f, 1) : 1
        }
        func fraction(_ body: () -> Void) -> CGFloat {
            v.largestInvalidation = 0
            body()
            return share()
        }
        let move = fraction { v.mouseMoved(with: mouse(.mouseMoved, NSPoint(x: 400, y: 400), in: w)) }
        check(move < 0.05, "pointer move redraws only around the pointer (\(Int(move * 100))% of screen)")
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 400, y: 400), in: w))
        let dragF = fraction { v.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 420, y: 410), in: w)) }
        check(dragF < 0.05, "drawing redraws only the new ink (\(Int(dragF * 100))% of screen)")
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 420, y: 410), in: w))
        await pause(3.1)
        v.largestInvalidation = 0
        await pause(0.3)
        check(share() < 0.05, "fading redraws only the fading ink (\(Int(share() * 100))%)")
        c.send(.penHotkey)
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
