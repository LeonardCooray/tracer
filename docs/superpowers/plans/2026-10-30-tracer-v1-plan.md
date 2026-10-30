# Tracer v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Tracer, a menu bar Mac app for drawing live over the screen with fading ink, plus region screenshots copied to the clipboard or saved to a folder at full Retina quality.

**Architecture:** A SwiftPM package with two targets. `TracerCore` holds everything testable without a screen: the ink model and fade timing, the session state machine and key mapping, rendering into a `CGContext`, geometry, image encoding, file naming and settings. `Tracer` is the AppKit app: one borderless, click-through-capable overlay panel per display, a SwiftUI dock, Carbon global hotkeys, ScreenCaptureKit capture and the settings window. The app turns user input into `SessionEvent`s, feeds them to the core state machine, and carries out the `SessionEffect`s it returns.

**Tech Stack:** Swift 6.4.2, SwiftPM, AppKit, SwiftUI (dock and settings), Core Graphics and ImageIO, ScreenCaptureKit, Carbon `RegisterEventHotKey`, `SMAppService`, Swift Testing (`import Testing`). There are no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-30-tracer-design.md` in the repo (copied in Task 1 from the workstation's `Lightshot REA Resources/2026-10-30-lightshot-rea-design.md`). Prior-art notes: `prior-art-research-2026-10-30.md`.

## Global Constraints

- Repo: public `LeonardCooray/tracer`, cloned at `/Users/leonard/src/tracer`. All work goes on branch `feat/v1`, never `main`; Leonard merges. Commits use `git -c user.name="Leonard Cooray" -c user.email="leonardcooray@gmail.com"`.
- Bundle ID `com.leonardcooray.tracer`, app name `Tracer`, minimum macOS 27.
- Build with SwiftPM and the Command Line Tools only (no Xcode project). Tests use Swift Testing; XCTest does not build with the Command Line Tools on this Mac.
- Menu bar app only (`LSUIElement`), no Dock icon.
- Permissions: Screen Recording only. Never require Accessibility or Input Monitoring; no `CGEventTap`, no `NSEvent.addGlobalMonitorForEvents` for keys.
- No network use of any kind.
- Screenshots are always full native (Retina) pixel resolution. PNG, or JPEG at compression quality 1.0.
- Live ink fades after a configurable delay, 1–10 s, default 3 s. Shift-drawn strokes stay until cleared. Ink on a frozen capture never fades.
- Spotlight and cursor ring are live-only and never appear in a saved or copied image.
- Launch at login uses `SMAppService.mainApp`, never a hand-written LaunchAgent.
- Code comments are one short line or none.
- Don't copy any code, icons or assets from Lightshot or ScreenBrush.

## Review Focus

- **Display added, removed or resized while the pen is on:** overlays rebuild for the new layout, ink on a removed display is dropped, and nothing crashes. (Task 10, manual check.)
- **Screen Recording permission denied or not yet granted:** the capture hotkey shows an alert that opens System Settings at Screen Recording. Live drawing keeps working. (Task 8.)
- **Save folder missing or unwritable** (deleted, or on an ejected drive): it's recreated if possible, otherwise the save falls back to `~/Pictures/Tracer` and a notification says so. Copying is unaffected. (Task 7 test `resolveSaveFolder`.)
- **Hotkey already taken by another app:** the failed registration shows in the menu and the settings window; the app never silently does nothing. (Tasks 5 and 9.)
- **A click without a drag, or a tiny drag, in capture mode:** a selection under 4×4 points counts as no selection. Copy and Save stay disabled, and there's no crash. (Task 7 test `tinySelectionIsNil`.)

---

## File Structure

```
tracer/
  Package.swift
  Resources/Info.plist
  scripts/bundle.sh                 # build release, assemble + sign build/Tracer.app
  docs/signing.md                   # Leonard's one-time self-signed cert steps
  docs/superpowers/specs/2026-10-30-tracer-design.md
  docs/superpowers/plans/2026-10-30-tracer-v1-plan.md
  Sources/TracerCore/
    Tool.swift          # Tool enum, key digits, capture availability
    InkStyle.swift      # RGBA, preset colours, widths, StrokeStyle
    Stroke.swift        # Stroke value type
    InkModel.swift      # strokes, fade timing, undo/clear, pruning
    Geometry.swift      # arrowhead, normalized/minimum selection, dock placement, size label
    InkRenderer.swift   # draws strokes into a CGContext
    Compositor.swift    # frozen image + ink + selection -> CGImage
    ImageOutput.swift   # ImageFormat, encode(), file naming, save-folder resolution
    Hotkey.swift        # Hotkey value type, display string, system-reserved check
    Session.swift       # AppMode state machine, SessionEvent -> [SessionEffect]
    KeyCommands.swift   # session key -> SessionCommand mapping
    Settings.swift      # TracerSettings Codable + SettingsStore
  Sources/Tracer/
    main.swift                 # NSApplication bootstrap, accessory policy
    AppController.swift        # owns Session, executes effects
    MenuBarController.swift
    HotkeyCenter.swift         # Carbon registration
    OverlayManager.swift       # one OverlayPanel per NSScreen
    OverlayPanel.swift
    InkView.swift              # mouse input, display-link redraw, spotlight, cursor ring
    DockView.swift             # SwiftUI dock (live + capture variants)
    PointerLabel.swift
    TextEntryController.swift
    ScreenCapturer.swift       # ScreenCaptureKit + permission
    CaptureView.swift          # selection drag/move/resize over frozen image
    OutputController.swift     # pasteboard + file save + notifications
    SettingsView.swift         # SwiftUI settings + hotkey recorder
  Tests/TracerCoreTests/
    InkModelTests.swift  InkRendererTests.swift  GeometryTests.swift
    SessionTests.swift   KeyCommandsTests.swift  ImageOutputTests.swift
    CompositorTests.swift  SettingsTests.swift  HotkeyTests.swift
```

Verification for app-side tasks: build, run `scripts/bundle.sh`, launch `build/Tracer.app`, exercise the feature, and take a screenshot (`screencapture -x`, if the terminal has Screen Recording permission; otherwise ask Leonard for one). Every report says plainly what wasn't exercised.

---

### Task 1: Repo, package skeleton, signed menu bar app

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/bundle.sh`, `docs/signing.md`, `.gitignore`, `README.md`, `Sources/Tracer/main.swift`, `Sources/Tracer/MenuBarController.swift`, `Sources/TracerCore/Tool.swift`, `Tests/TracerCoreTests/ToolTests.swift`, `docs/superpowers/specs/…`, `docs/superpowers/plans/…`

**Interfaces:**
- Produces: `public enum Tool: Int, CaseIterable, Codable, Sendable { case pen = 1, highlighter, arrow, rectangle, spotlight, text }` with `public var displayName: String` ("Pen", "Highlighter", "Arrow", "Rectangle", "Spotlight", "Text"), `public static func forDigit(_ d: Int) -> Tool?` and `public var availableInCapture: Bool` (false only for `.spotlight`).
- Produces: `scripts/bundle.sh [--debug]` writes `build/Tracer.app` and signs it with identity `$TRACER_SIGN_IDENTITY` (default `"Tracer Local Signing"`). If the identity is missing, it falls back to ad-hoc signing (`-`) with a warning.

- [ ] **Step 1:** With Leonard's go-ahead, create the repo with `gh repo create LeonardCooray/tracer --public --add-readme --license mit --description "Draw on your Mac's screen and take screenshots"`, clone it to `/Users/leonard/src/tracer` and `git switch -c feat/v1`. The MIT license is my call, so flag it in the PR.
- [ ] **Step 2:** Write `Tests/TracerCoreTests/ToolTests.swift`:
  ```swift
  @Test func digitsMapToTools() { #expect(Tool.forDigit(1) == .pen); #expect(Tool.forDigit(6) == .text); #expect(Tool.forDigit(0) == nil); #expect(Tool.forDigit(7) == nil) }
  @Test func spotlightIsLiveOnly() { #expect(!Tool.spotlight.availableInCapture); #expect(Tool.allCases.filter { !$0.availableInCapture } == [.spotlight]) }
  ```
- [ ] **Step 3:** Write `Package.swift` (tools version 6.0, `platforms: [.macOS("27.0")]`, targets `TracerCore`, executable `Tracer` depending on it, test target `TracerCoreTests`). Run `swift test` and expect it to fail with an undefined `Tool`.
- [ ] **Step 4:** Implement `Tool.swift`. Run `swift test` and expect PASS.
- [ ] **Step 5:** `main.swift` starts `NSApplication` with `.accessory` policy. `MenuBarController` adds an `NSStatusItem` (SF Symbol `scribble.variable`) with the menu items Draw, Capture, Settings…, Quit Tracer. Only Quit works in this task.
- [ ] **Step 6:** `Info.plist` holds `CFBundleIdentifier com.leonardcooray.tracer`, `CFBundleName Tracer`, `LSUIElement true`, `LSMinimumSystemVersion 27.0`, `CFBundleShortVersionString 0.1.0`. `bundle.sh` runs `swift build -c release`, copies the binary and plist into `build/Tracer.app/Contents/{MacOS,}`, then `codesign --force --options runtime --sign "$IDENTITY" build/Tracer.app`.
- [ ] **Step 7:** `docs/signing.md` gives Leonard's one-time steps. In Keychain Access, Certificate Assistant → Create a Certificate…, name `Tracer Local Signing`, Self Signed Root, type Code Signing. Then confirm with `security find-identity -v -p codesigning`.
- [ ] **Step 8:** Run `scripts/bundle.sh && open build/Tracer.app`. The menu bar icon should appear with no Dock icon, and Quit should exit. `codesign -dv build/Tracer.app` should show the identifier `com.leonardcooray.tracer`.
- [ ] **Step 9:** Copy the spec and this plan into `docs/superpowers/`, then commit with `feat: package skeleton, signed menu bar app`.

### Task 2: Ink model and fade timing

**Files:** Create `Sources/TracerCore/InkStyle.swift`, `Stroke.swift`, `InkModel.swift`; test `Tests/TracerCoreTests/InkModelTests.swift`

**Interfaces:**
- Consumes: `Tool`.
- Produces:
  - `public struct RGBA: Codable, Equatable, Sendable { r, g, b, a: Double }`
  - `public enum InkPalette { public static let presets: [RGBA] }`, holding red `#FF453A`, yellow `#FFD60A`, green `#30D158`, blue `#0A84FF` and white
  - `public struct StrokeStyle: Equatable, Sendable { color: RGBA; width: Double }`
  - `public func defaultWidth(for: Tool) -> Double` (pen 4, highlighter 18, arrow 4, rectangle 3.5, text 18 as the font size)
  - `public struct Stroke: Identifiable, Equatable, Sendable { id: UUID; tool: Tool; points: [CGPoint]; style: StrokeStyle; pinned: Bool; text: String?; finishedAt: TimeInterval? }`
  - `public enum FadeMode: Equatable, Sendable { case live(delay: Double), frozen }`
  - `public struct FadeSetting { public static let range = 1.0...10.0; public static let defaultDelay = 3.0; public static func clamp(_ v: Double) -> Double }`
  - `public final class InkModel` with:
    - `init(mode: FadeMode)`
    - `var mode`
    - `private(set) var strokes: [Stroke]`
    - `func begin(tool:style:at:pinned:)`
    - `func extend(to:)`
    - `func end(at time: TimeInterval)`
    - `func addText(_:at:style:time:)`
    - `func undo()`
    - `func clear()`
    - `func opacity(of: Stroke, at: TimeInterval) -> Double`
    - `func prune(at: TimeInterval)`
  - `public static let fadeOutDuration = 0.4`

- [ ] **Step 1:** Write failing tests:
  ```swift
  @Test func liveStrokeHoldsThenFades() { let m = InkModel(mode: .live(delay: 3)); m.begin(tool: .pen, style: s, at: .zero, pinned: false); m.extend(to: CGPoint(x: 10, y: 0)); m.end(at: 100)
    let k = m.strokes[0]; #expect(m.opacity(of: k, at: 102.9) == 1); #expect(m.opacity(of: k, at: 103.2) > 0 && m.opacity(of: k, at: 103.2) < 1); #expect(m.opacity(of: k, at: 103.4) == 0) }
  @Test func strokeInProgressIsOpaque() // no end() -> opacity 1 at any time
  @Test func pinnedNeverFades() // pinned: true, opacity 1 at t = 10_000
  @Test func frozenNeverFades() // mode .frozen, opacity 1 at t = 10_000
  @Test func pruneDropsOnlyFullyFaded() // two strokes ended at 100 and 105, delay 3, prune(at: 103.5) leaves only the second
  @Test func undoRemovesLastAndClearRemovesAll()
  @Test func fadeSettingClamps() { #expect(FadeSetting.clamp(0.2) == 1); #expect(FadeSetting.clamp(30) == 10); #expect(FadeSetting.clamp(4) == 4) }
  @Test func defaultWidths() { #expect(defaultWidth(for: .highlighter) == 18) }
  ```
- [ ] **Step 2:** Run `swift test --filter InkModelTests` and expect FAIL.
- [ ] **Step 3:** Implement. Opacity is 1 until `finishedAt + delay`, then falls linearly to 0 over `fadeOutDuration`. Drop a point in `extend` if it's within 0.5 pt of the previous one, so long holds don't grow without bound.
- [ ] **Step 4:** Run the tests and expect PASS, then commit with `feat(core): ink model with fade timing`.

### Task 3: Rendering into a CGContext

**Files:** Create `Sources/TracerCore/Geometry.swift` (arrowhead only in this task) and `InkRenderer.swift`; test `InkRendererTests.swift`

**Interfaces:**
- Consumes: `Stroke`, `InkModel.opacity`.
- Produces:
  - `public func arrowHead(from: CGPoint, to: CGPoint, width: Double) -> (CGPoint, CGPoint)`. Wings sit at ±28° from the shaft, with length `max(12, width * 3.5)`.
  - `public enum InkRenderer { public static func draw(_ strokes: [Stroke], in ctx: CGContext, opacity: (Stroke) -> Double) }`:
    - pen: a smoothed round-cap path
    - highlighter: a square-cap path at alpha 0.4 × colour alpha, with multiply blend
    - arrow: from the first point to the last, plus the head
    - rectangle: from the first point to the last
    - text: Core Text at `style.width` points, using the system font semibold
    - spotlight: never stored as a stroke, so it's skipped here

- [ ] **Step 1:** Write failing tests that render into a 100×100 RGBA bitmap context and read pixels back:
  ```swift
  @Test func penPaintsAlongPath() // red pen (10,50)->(90,50) width 4: pixel (50,50) is red; (50,10) is transparent
  @Test func opacityZeroPaintsNothing() // same stroke with opacity { _ in 0 }: every pixel alpha == 0
  @Test func rectangleIsOutlineOnly() // rect (20,20)->(80,80): pixel on the edge (20,50) is painted, centre (50,50) is not
  @Test func arrowHeadWingsAreSymmetric() { let (a, b) = arrowHead(from: .init(x: 0, y: 0), to: .init(x: 100, y: 0), width: 4); #expect(abs(a.y + b.y) < 0.001); #expect(a.x < 100 && b.x < 100) }
  @Test func highlighterIsTranslucent() // yellow highlighter over white background: pixel alpha/colour is between white and pure yellow
  ```
- [ ] **Step 2:** Run the tests and expect FAIL. Implement, then run them again and expect PASS.
- [ ] **Step 3:** Commit with `feat(core): ink renderer`.

### Task 4: Session state machine and key commands

**Files:** Create `Sources/TracerCore/Session.swift` and `KeyCommands.swift`; test `SessionTests.swift`, `KeyCommandsTests.swift`

**Interfaces:**
- Consumes: `Tool`.
- Produces:
  - `public enum AppMode: Equatable { case idle, drawing, capturing }`
  - `public enum SessionEvent { case penHotkey, captureHotkey, escape, command(SessionCommand), textEditingBegan, textEditingEnded, captureFinished }`
  - `public enum SessionCommand: Equatable { case selectTool(Tool), undo, clearAll, copy, save }`
  - `public enum SessionEffect: Equatable` with these cases:
    - `showOverlays(interactive: Bool)`
    - `hideOverlays`
    - `clearInk`
    - `setFadeMode(FadeMode)`
    - `freezeScreens`
    - `registerSessionKeys(capture: Bool)`
    - `unregisterSessionKeys`
    - `selectTool(Tool)`
    - `undo`
    - `clearAll`
    - `copySelection`
    - `saveSelection`
    - `restorePreviousApp`
  - `public struct Session { public private(set) var mode: AppMode; public private(set) var tool: Tool; public private(set) var isEditingText: Bool; public mutating func handle(_ e: SessionEvent) -> [SessionEffect] }`
  - `public enum SessionKey: Equatable { case digit(Int), escape, delete, undo, returnKey, copy, save }`
  - `public func command(for key: SessionKey, mode: AppMode, isEditingText: Bool) -> SessionCommand?`

- [ ] **Step 1:** Write failing tests that pin the agreed behaviour:
  ```swift
  @Test func penHotkeyTogglesDrawing() // idle --penHotkey--> drawing: effects == [.showOverlays(interactive: true), .setFadeMode(.live(delay: 3)), .registerSessionKeys(capture: false)]; again -> idle with [.hideOverlays, .clearInk, .unregisterSessionKeys, .restorePreviousApp]
  @Test func escapeLeavesDrawingAndClears() // drawing --escape--> idle, effects contain .clearInk
  @Test func captureFromIdleFreezes() // idle --captureHotkey--> capturing: [.freezeScreens, .showOverlays(interactive: true), .setFadeMode(.frozen), .registerSessionKeys(capture: true)]
  @Test func captureFromDrawingKeepsInk() // drawing --captureHotkey--> capturing: effects contain .freezeScreens and .setFadeMode(.frozen) and NOT .clearInk
  @Test func copyAndSaveEndCapture() // capturing --command(.copy)--> [.copySelection]; then --captureFinished--> idle with .hideOverlays, .clearInk
  @Test func escapeWhileEditingTextOnlyEndsText() // drawing, textEditingBegan, escape -> still drawing, isEditingText false, no .hideOverlays
  @Test func spotlightNotSelectableInCapture() // capturing --command(.selectTool(.spotlight))--> [] and tool unchanged
  @Test func keysMap() { #expect(command(for: .digit(3), mode: .drawing, isEditingText: false) == .selectTool(.arrow)); #expect(command(for: .delete, mode: .drawing, isEditingText: false) == .clearAll); #expect(command(for: .returnKey, mode: .capturing, isEditingText: false) == .copy); #expect(command(for: .save, mode: .capturing, isEditingText: false) == .save) }
  @Test func keysSuppressedWhileTyping() // digit, delete, undo, returnKey all nil when isEditingText
  @Test func copySaveOnlyInCapture() // returnKey/copy/save nil in .drawing
  ```
  `Session` takes `fadeDelay` in `init(fadeDelay: Double = FadeSetting.defaultDelay)` and has `mutating func setFadeDelay(_:)`. `command(for: .escape, …)` returns nil: the app sends `SessionEvent.escape` for that key instead.
- [ ] **Step 2:** Run the tests and expect FAIL. Implement, then run them again and expect PASS.
- [ ] **Step 3:** Commit with `feat(core): session state machine and key commands`.

### Task 5: Hotkeys, overlays and the live pen end to end

**Files:**
- Create: `Sources/Tracer/AppController.swift`, `HotkeyCenter.swift`, `OverlayManager.swift`, `OverlayPanel.swift`, `InkView.swift`
- Create: `Sources/TracerCore/Hotkey.swift`, test `HotkeyTests.swift`
- Modify: `MenuBarController.swift`

**Interfaces:**
- Consumes: `Session`, `InkModel`, `InkRenderer`, `SessionKey`.
- Produces:
  - `public struct Hotkey: Codable, Equatable, Sendable { keyCode: UInt32; modifiers: UInt32 }`, where `modifiers` uses Carbon masks
  - `public var displayString: String`, for example "⌥⇧D"
  - `public var isReservedBySystem: Bool`, true for ⇧⌘3, ⇧⌘4, ⇧⌘5 and ⇧⌘6
  - `public static let defaultPen`: ⌥⇧D, my call
  - `public static let defaultCapture`: ⌥⇧S, my call
  - `final class HotkeyCenter` with `func register(_: Hotkey, id: UInt32, handler: @escaping () -> Void) -> Bool` (false if Carbon refuses it), `func unregister(id:)`, and `func registerSessionKeys(capture: Bool, handler: @escaping (SessionKey) -> Void)`
  - `final class OverlayPanel: NSPanel`, which is borderless and `.nonactivatingPanel`, with level `.screenSaver`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, a clear background and `ignoresMouseEvents` toggled by `setInteractive(_:)`
  - `final class OverlayManager { func show(interactive: Bool); func hide(); var inkViews: [InkView] }`, with one panel per `NSScreen` and `inkView(for: NSScreen)`

- [ ] **Step 1:** Write failing `HotkeyTests`: `displayString` of `defaultPen == "⌥⇧D"`, ⇧⌘4 `isReservedBySystem`, `defaultCapture` is not reserved, and a JSON round-trip. Implement, then expect PASS.
- [ ] **Step 2:** In `AppController`, register both hotkeys at launch. If `register` returns false, show "⚠︎ Draw hotkey unavailable" (or "Capture") as a disabled menu item. Route the pen hotkey, the menu's Draw item and session keys into `Session.handle` and carry out each returned effect.
- [ ] **Step 3:** `InkView` handles mouse down, dragged and up into the `InkModel`, with the current tool and colour; Shift held at mouse-down means `pinned`. A `displayLink(target:selector:)` redraws while any stroke is fading and calls `prune`, and stops when nothing is fading. Draw with `InkRenderer` in `draw(_:)`.
- [ ] **Step 4:** Effects `restorePreviousApp` and `hideOverlays` set every panel's `ignoresMouseEvents` back to true and order it out. Record `NSWorkspace.shared.frontmostApplication` when entering drawing, and re-activate it on exit.
- [ ] **Step 5:** Bundle, launch, press ⌥⇧D and draw. The ink should fade about 3 s after mouse-up, and a Shift-drawn stroke should stay. Press ⌥⇧D, and clicks should reach the app underneath immediately. Repeat with Esc, and check ⌘Z and Delete. Take a screenshot.
- [ ] **Step 6:** Commit with `feat: global hotkeys, overlays and live pen`.

### Task 6: Dock, pointer label and the rest of the live tools

**Files:** Create `Sources/Tracer/DockView.swift`, `PointerLabel.swift`, `TextEntryController.swift`; modify `InkView.swift`, `AppController.swift`

**Interfaces:**
- Consumes: `Tool`, `InkPalette`, `SessionCommand`, `Session.isEditingText`.
- Produces: `struct DockView: View` (inputs: `tool`, `color`, `mode: AppMode`, `onCommand: (SessionCommand) -> Void`, `onColor: (RGBA) -> Void`), hosted in its own small non-activating panel; `TextEntryController.begin(at: CGPoint, in: OverlayPanel, style:)` → calls back `onCommit(String)` / `onCancel()`.

- [ ] **Step 1:** Build the dock to match the approved mockup C:
  - a vertical column of dark translucent glass with a 14 pt corner radius, the system font, and SF Symbols for the six tools in order
  - the preset colour dots below the tools
  - in live mode, it sits 10 pt from the right edge of the screen the pointer is on, vertically centred
  - it slides in over 0.18 s when drawing starts and out when drawing ends
  - right-clicking it opens `NSColorPanel` and a width slider from 2 to 24
- [ ] **Step 2:** `PointerLabel` is a small glass label offset 16 pt right and 16 pt down from the pointer. It shows "<Tool> · fades <n>s", or "<Tool> · stays" for a Shift stroke, and it isn't shown in capture mode.
- [ ] **Step 3:** Tools in `InkView`:
  - highlighter, arrow and rectangle come from the core renderer
  - spotlight dims the screen to 55% black with a 120 pt-radius clear circle at the pointer, drawn live and never stored
  - the cursor ring is a 28 pt ring drawn at the pointer whenever drawing is on
  - with the `cursorRingAlwaysOn` setting (Task 9), the ring also shows while idle: the overlays stay visible but click-through, with no dock or label
- [ ] **Step 4:** For text, a click places an `NSTextField` in the panel. The panel becomes key only while you type (`canBecomeKey` returns true only then), and the app sends `textEditingBegan` and `textEditingEnded`. Return or a click elsewhere commits through `InkModel.addText`, and Esc cancels the text only. When drawing ends, the previous app is re-activated.
- [ ] **Step 5:** Bundle, launch, and exercise all six tools with keys 1–6 and with dock clicks. Check that typing "1" in a text box types 1 rather than switching tools, and that Esc while typing leaves the pen on. Take screenshots.
- [ ] **Step 6:** Commit with `feat: dock, pointer label, all live tools`.

### Task 7: Output core: encoding, naming, folders, selection geometry, compositing

**Files:** Create `Sources/TracerCore/ImageOutput.swift`, `Compositor.swift`; extend `Geometry.swift`; test `ImageOutputTests.swift`, `CompositorTests.swift`, `GeometryTests.swift`

**Interfaces:**
- Consumes: `InkRenderer`, `Stroke`.
- Produces:
  - `public enum ImageFormat: String, Codable, CaseIterable { case png, jpeg }` with `fileExtension` and `utType`, plus `public func encode(_: CGImage, as: ImageFormat) -> Data?` (ImageIO, JPEG `kCGImageDestinationLossyCompressionQuality` 1.0)
  - `public func screenshotFileName(date: Date, format: ImageFormat, timeZone: TimeZone = .current) -> String`, which gives `"Tracer 2026-10-30 at 14.05.09.png"`
  - `public func uniqueURL(in folder: URL, fileName: String, exists: (URL) -> Bool) -> URL`, which appends " (2)", " (3)" and so on
  - `public func resolveSaveFolder(preferred: URL, fallback: URL, fm: FileManager) -> (url: URL, usedFallback: Bool)`
  - `public func selectionRect(from: CGPoint, to: CGPoint) -> CGRect?`, which is nil under 4×4 pt
  - `public func dockOrigin(selection: CGRect, dockSize: CGSize, screen: CGRect, gap: Double = 8) -> CGPoint`, which places the dock to the right of the selection, flips it left when it doesn't fit, and clamps it inside `screen`
  - `public func sizeLabel(selection: CGRect, scale: Double, format: ImageFormat) -> String`, which gives `"1240 × 680 · PNG"` in pixels
  - `public enum Compositor { public static func image(base: CGImage, baseScale: Double, strokes: [Stroke], selection: CGRect) -> CGImage? }`, which crops in pixels and draws the ink at full opacity (`selection` is in the base image's point space)

- [ ] **Step 1:** Write failing tests:
  ```swift
  @Test func fileNameFormat() // 2026-10-30 14:05:09 UTC, .png, UTC tz -> "Tracer 2026-10-30 at 14.05.09.png"
  @Test func uniqueNameIncrements() // exists returns true for "x.png" and "x (2).png" -> "x (3).png"
  @Test func resolveSaveFolder() // preferred inside a temp dir that is created if missing -> usedFallback false; preferred under a read-only temp dir -> fallback, usedFallback true
  @Test func tinySelectionIsNil() { #expect(selectionRect(from: .init(x: 5, y: 5), to: .init(x: 7, y: 8)) == nil); #expect(selectionRect(from: .init(x: 50, y: 50), to: .init(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 30)) }
  @Test func dockFlipsNearRightEdge() // selection hugging the screen's right edge -> dock origin x < selection.minX
  @Test func dockClampsVertically() // selection at the top edge -> dock fully inside screen
  @Test func sizeLabelUsesPixels() { #expect(sizeLabel(selection: CGRect(x: 0, y: 0, width: 620, height: 340), scale: 2, format: .png) == "1240 × 680 · PNG") }
  @Test func compositeIsFullResolution() // base 200×200 px at scale 2, selection 10,10,50,50 pt -> output 100×100 px
  @Test func compositeIncludesInk() // red stroke across the selection -> output has red pixels
  @Test func jpegRoundTrips() // encode(.jpeg) -> CGImageSource reads same width/height; png likewise
  ```
- [ ] **Step 2:** Run the tests and expect FAIL. Implement, then run them again and expect PASS.
- [ ] **Step 3:** Commit with `feat(core): image output, selection geometry, compositor`.

### Task 8: Capture mode

**Files:** Create `Sources/Tracer/ScreenCapturer.swift`, `CaptureView.swift`, `OutputController.swift`; modify `AppController.swift`, `DockView.swift`, `MenuBarController.swift`

**Interfaces:**
- Consumes: `Session` capture events and effects, `selectionRect`, `dockOrigin`, `sizeLabel`, `Compositor.image`, `encode`, `screenshotFileName`, `uniqueURL`, `resolveSaveFolder`.
- Produces:
  - `final class ScreenCapturer`:
    - `func hasPermission() -> Bool`, using `CGPreflightScreenCaptureAccess`
    - `func requestPermission()`
    - `func captureAll(excluding: [NSWindow]) async throws -> [CGDirectDisplayID: (image: CGImage, scale: Double)]`, using `SCShareableContent` and `SCScreenshotManager.captureImage`, with a `SCStreamConfiguration` at full native pixel size and Tracer's own windows excluded
  - `final class OutputController`:
    - `func copy(_: CGImage, format: ImageFormat) -> Bool`, which writes the encoded data to `NSPasteboard.general` as the format's type
    - `func save(_: CGImage, format: ImageFormat, folder: URL) -> URL?`, which posts a notification when the fallback folder was used

- [ ] **Step 1:** For `freezeScreens`:
  - if permission is missing, show an alert, "Tracer needs Screen Recording permission to take screenshots", with an "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`), and leave the mode as it was
  - otherwise, capture every display, show each frozen image under its overlay's ink, and switch the ink model to `.frozen`
- [ ] **Step 2:** `CaptureView` dims everything outside the selection to 45% black, with a 1.5 pt white outline and four corner handles. You drag to create a selection, drag inside it to move it and drag a handle to resize it, and the ink stays attached to the image.
- [ ] **Step 3:** The dock (mockup B) snaps beside the selection through `dockOrigin`, showing the tools without spotlight and then Copy (accent) and Save. `sizeLabel` sits under the selection, with the hint "↵ copy · ⌘S save · esc". Copy and Save are disabled while the selection is nil.
- [ ] **Step 4:** Copy or Save runs `Compositor.image`, then `OutputController`, then `captureFinished`. In the menu, Capture triggers the same flow as the capture hotkey.
- [ ] **Step 5:** Bundle and launch, then check these cases:
  - Leonard grants Screen Recording once; check that relaunching after a rebuild doesn't ask again (this proves the signing works)
  - from idle: ⌥⇧S, drag, draw an arrow, Return; paste into Preview and check it's full Retina size with the arrow and no spotlight
  - from drawing: ink present, ⌥⇧S, the ink is captured; ⌘S saves the file to the folder with the date name
  - a click without a drag leaves Copy disabled
  - JPEG format works
- [ ] **Step 6:** Commit with `feat: capture mode with copy and save`.

### Task 9: Settings and launch at login

**Files:** Create `Sources/TracerCore/Settings.swift`, `Sources/Tracer/SettingsView.swift`; test `SettingsTests.swift`; modify `AppController.swift`, `MenuBarController.swift`

**Interfaces:**
- Consumes: `Hotkey`, `ImageFormat`, `FadeSetting`.
- Produces:
  - `public struct TracerSettings: Codable, Equatable { penHotkey; captureHotkey; fadeDelay: Double; saveFolder: URL; format: ImageFormat; launchAtLogin: Bool; cursorRingAlwaysOn: Bool }`
  - `public static let defaults`: ⌥⇧D, ⌥⇧S, 3, `~/Pictures/Tracer`, `.png`, false, false
  - `public func validated() -> TracerSettings`, which clamps the fade and swaps a reserved or duplicate hotkey back to its default
  - `public final class SettingsStore { init(defaults: UserDefaults); func load() -> TracerSettings; func save(_:) }`, under the key `"settings.v1"`

- [ ] **Step 1:** Write failing tests:
  - `defaults` round-trips through the store, using a suite-named `UserDefaults`
  - a corrupt stored blob loads `defaults`
  - `validated()` clamps a fade of 0 to 1
  - the pen and capture hotkeys set to the same key reset to their defaults
  - ⇧⌘4 resets
- [ ] **Step 2:** Run the tests and expect FAIL. Implement, then run them again and expect PASS.
- [ ] **Step 3:** `SettingsView` is a SwiftUI form in a normal window opened from the menu:
  - two hotkey recorders, each of which records the next key combination while focused and shows an inline warning if it's reserved or Carbon refuses it
  - a fade slider from 1 to 10 s
  - the save folder with a Choose… button (`NSOpenPanel`)
  - a PNG/JPEG picker
  - a "Launch at login" toggle that calls `SMAppService.mainApp.register()` or `unregister()` and shows any error inline
  - a "Show cursor ring when not drawing" toggle
  - changes apply immediately: the hotkeys re-register and the fade goes to `Session.setFadeDelay`
- [ ] **Step 4:** Bundle and launch. Check that changing a hotkey works without a relaunch, that settings survive a relaunch, and that the launch-at-login toggle reflects `SMAppService.mainApp.status`. If SentinelOne flags anything, report it to Leonard and don't work around it.
- [ ] **Step 5:** Commit with `feat: settings and launch at login`.

### Task 10: Multiple displays, final pass and PR

**Files:** Modify `OverlayManager.swift`, `DockView.swift`, `README.md`

- [ ] **Step 1:** `OverlayManager` observes `NSApplication.didChangeScreenParametersNotification`. It rebuilds the panels, keeps the ink on screens that still exist (keyed by `CGDirectDisplayID`), and drops the rest. The live dock follows the screen the pointer is on, checked on mouse move.
- [ ] **Step 2:** If an external display is available, check drawing and capture on it and while unplugging it with the pen on. If none is available, say so in the PR as not verified.
- [ ] **Step 3:** The README covers what Tracer does, the default keys, the build (`scripts/bundle.sh`), signing (a link to `docs/signing.md`) and the permissions.
- [ ] **Step 4:** Run `swift test` for all tests, then `scripts/bundle.sh`, then a full smoke run of Tasks 5, 6 and 8's checks. Push `feat/v1` and open a PR against `main`. The PR lists what was verified, what wasn't (for example, the external display) and the MIT license as my call. Don't merge.
