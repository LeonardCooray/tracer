# Redact Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A capture-only Redact tool that covers a dragged box with an opaque fill of the frozen frame's mean colour, so copied and saved screenshots can't leak what was under it.

**Architecture:** `Tool.redact` is an ordinary stroke whose `style.color` is set from the frozen frame (estimate while dragging, exact mean at mouse-up). `InkRenderer` fills it and always draws redact strokes before other ink, which covers both the on-screen `InkView` and `Compositor`. Which tools exist, and which digit picks which, becomes a function of `AppMode`.

**Tech Stack:** Swift, AppKit, Core Graphics, Swift Testing (`scripts/test.sh`), the DEBUG `--self-test` harness.

**Spec:** `docs/superpowers/specs/2026-10-31-redact-tool-design.md`

## Global Constraints

- Branch `feat/redact`; commits as leonardcooray@gmail.com; never commit to `main`.
- Run tests with `scripts/test.sh`, never bare `swift test`.
- No SwiftUI or Observation macros (`@State`, `@Observable`) in app code.
- Code comments: one short line or none.
- No new permissions. Ink stays smooth at 120 Hz.
- Output stays one flat bitmap; no blur, pixelation or translucent fill anywhere in the redact path.
- Self-tests use the isolated `com.leonardcooray.tracer.selftest` defaults; never touch `com.leonardcooray.tracer`.
- Build test apps in a scratch worktree, not the main checkout: Leonard's installed copy is `/Applications/Tracer.app`, but `build/Tracer.app` must not be left ad hoc signed.

## Review Focus

1. **A box partly off the display edge**: the mean covers only the part inside the frame; a box wholly outside gives no fill and no stroke. (Task 2 test `meanColorClipsToImage`.)
2. **A non-Retina external display (scale 1)**: the mean reads the right pixels. (Task 2 test `meanColorHonoursScale`.)
3. **A frame in a wide-gamut colour space**: the fill matches the page when drawn as sRGB, rather than shifting hue. (Task 2 test `meanColorConvertsToSRGB`.)
4. **Drag before the frozen frame has arrived** (`frozenFrame == nil`): no redact stroke starts. (Task 4 self-test check "no redact before frames".)
5. **Undo then redo of a redact box**: it comes back with its fill colour, not the dock colour. (Task 4 self-test check "redo keeps the fill".)

---

### Task 1: Redact stroke rendering

**Files:**
- Modify: `Sources/TracerCore/Tool.swift`, `Sources/TracerCore/InkStyle.swift`, `Sources/TracerCore/InkRenderer.swift`, `Sources/Tracer/DockView.swift` (symbol only)
- Test: `Tests/TracerCoreTests/InkRendererTests.swift`, `Tests/TracerCoreTests/CompositorTests.swift`, `Tests/TracerCoreTests/ToolTests.swift`

**Interfaces:**
- Produces: `Tool.redact` (raw value 7, `displayName` "Redact"); `InkRenderer.minimumRedactSide = 2.0`; `public func isTooSmall(_ s: Stroke) -> Bool` in `InkRenderer.swift`; `InkRenderer.draw` draws all `.redact` strokes first, in their original relative order, then the rest.

- [ ] **Step 1: Write the failing tests**

```swift
// InkRendererTests
@Test func redactFillsOpaque() {
    let c = Canvas(background: RGBA(hex: 0x000000))
    let s = Stroke(tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)],
                   style: StrokeStyle(color: RGBA(hex: 0x808080), width: 0), finishedAt: 0)
    InkRenderer.draw([s], in: c.ctx) { _ in 1 }
    #expect(c.pixel(35, 25) == (128, 128, 128, 255))
    #expect(c.pixel(5, 5) == (0, 0, 0, 255))
}

@Test func redactDrawsUnderOtherInk() {
    let c = Canvas()
    let arrow = Stroke(tool: .arrow, points: [CGPoint(x: 0, y: 50), CGPoint(x: 99, y: 50)],
                       style: StrokeStyle(color: RGBA(hex: 0xFF0000), width: 6), finishedAt: 0)
    let box = Stroke(tool: .redact, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)],
                     style: StrokeStyle(color: RGBA(hex: 0xFFFFFF), width: 0), finishedAt: 1)
    InkRenderer.draw([arrow, box], in: c.ctx) { _ in 1 }
    #expect(c.pixel(50, 50).r > 200 && c.pixel(50, 50).g < 80)
}

@Test func tooSmallStrokes() {
    let st = StrokeStyle(color: RGBA(hex: 0), width: 0)
    #expect(isTooSmall(Stroke(tool: .redact, points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 1.5)], style: st)))
    #expect(!isTooSmall(Stroke(tool: .redact, points: [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 2)], style: st)))
    #expect(isTooSmall(Stroke(tool: .arrow, points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], style: st)))
    #expect(!isTooSmall(Stroke(tool: .pen, points: [CGPoint(x: 0, y: 0)], style: st)))
}

@Test func redactBounds() {
    let s = Stroke(tool: .redact, points: [CGPoint(x: 60, y: 40), CGPoint(x: 10, y: 10)], style: StrokeStyle(color: RGBA(hex: 0), width: 0))
    #expect(inkBounds(of: s) == CGRect(x: 9, y: 9, width: 52, height: 32))
}

// CompositorTests
// compositeRedactIsOneColour: base is a 200 px checkerboard of 1 px black/white squares, baseScale 2;
// a redact stroke (10,10)-(40,40) coloured 0x808080; selection (0,0,50,50).
// Expect every output pixel in x, y 20...79 to be exactly (128, 128, 128, 255).

// ToolTests: update displayNames to include "Redact" last
```

- [ ] **Step 2: Run to verify they fail**

Run: `scripts/test.sh`
Expected: compile failure on `.redact` / `isTooSmall`.

- [ ] **Step 3: Implement**
  - `Tool`: add `redact` after `text`; `displayName` "Redact". Leave `availableInCapture`/`forDigit` for Task 3, but `availableInCapture` stays `self != .spotlight`.
  - `defaultWidth(for: .redact)` → `0`.
  - `InkRenderer.draw`: `.redact` fills `CGRect` from first to last point with the stroke colour at alpha 1, ignoring `opacity` and `highlighterBlend`; iterate redact strokes before the others.
  - `inkBounds(.redact)`: box of first and last point padded by 1.
  - `isTooSmall`: arrow shorter than `minimumArrowLength`, or redact with either side under `minimumRedactSide`; everything else false.
  - `DockView` `symbol`: `.redact` → `"rectangle.fill"`.

- [ ] **Step 4: Run tests**

Run: `scripts/test.sh`
Expected: all pass.

- [ ] **Step 5: Commit** — `feat: redact strokes render as opaque fills beneath other ink`

### Task 2: Mean colour of a frozen-frame region

**Files:**
- Create: `Sources/TracerCore/Redaction.swift`
- Modify: `Sources/TracerCore/Compositor.swift`, `Sources/TracerCore/InkModel.swift`
- Test: `Tests/TracerCoreTests/RedactionTests.swift`, `Tests/TracerCoreTests/InkModelTests.swift`

**Interfaces:**
- Produces: `public func meanColor(of image: CGImage, scale: Double, in rect: CGRect, maxSide: Int? = nil) -> RGBA?` — `rect` in the image's point space, origin bottom-left (same convention as `Compositor.image`); returns sRGB with `a == 1`, or nil when the rect misses the image. `maxSide` downsamples so neither side exceeds it (drag preview); nil means every native pixel. `InkModel.setActiveColor(_ color: RGBA)` sets the active stroke's `style.color`, no-op when not drawing.
- Shared helper: move Compositor's point-to-pixel crop into `func pixelCrop(_ rect: CGRect, scale: Double, image: CGImage) -> CGRect?` (top-left pixel rect, integral, clipped, nil if empty) and use it from both.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func meanColorOfHalfBlackHalfWhite() // 100 px image, left 50 px black, right white; scale 1; rect (25,0,50,100) → r,g,b each within 0.01 of 0.5, a == 1
@Test func meanColorClipsToImage()       // all-white 100 px image, rect (90,90,50,50) → white; rect (200,200,10,10) → nil
@Test func meanColorHonoursScale()       // 200 px image, left 100 px black, right white. scale 2: rect (0,0,50,100) → black; rect (25,0,50,100) → 0.5 grey. scale 1: rect (50,0,100,200) → 0.5 grey
@Test func meanColorConvertsToSRGB()     // 50 px image in Display P3 filled with CGColor(srgbRed:0.2,green:0.4,blue:0.6) → mean within 0.02 of (0.2,0.4,0.6)
@Test func meanColorDownsampleIsClose()  // half/half image 400 px, maxSide 16 → within 0.05 of 0.5
@Test func setActiveColorRecolours()     // begin redact, setActiveColor(0x123456), end → strokes[0].style.color == RGBA(hex: 0x123456); after end, setActiveColor changes nothing
```

- [ ] **Step 2: Run to verify they fail**

Run: `scripts/test.sh`
Expected: compile failure on `meanColor`.

- [ ] **Step 3: Implement** `meanColor`: crop with `pixelCrop`, draw into an 8-bit sRGB `premultipliedLast` context (native size, or scaled to `maxSide` with `.medium` interpolation), then average r, g, b over all pixels. `setActiveColor` in `InkModel`. Refactor `Compositor.image` onto `pixelCrop` without changing its behaviour.

- [ ] **Step 4: Run tests**

Run: `scripts/test.sh`
Expected: all pass, including the existing Compositor tests.

- [ ] **Step 5: Commit** — `feat: mean colour of a frozen-frame region for redaction`

### Task 3: Tools depend on the mode

**Files:**
- Modify: `Sources/TracerCore/Tool.swift`, `Sources/TracerCore/KeyCommands.swift`, `Sources/TracerCore/Session.swift`, `Sources/Tracer/DockView.swift`
- Test: `Tests/TracerCoreTests/ToolTests.swift`, `Tests/TracerCoreTests/KeyCommandsTests.swift`, `Tests/TracerCoreTests/SessionTests.swift`

**Interfaces:**
- Produces: `public static func tools(for mode: AppMode) -> [Tool]` — `.capturing`: `[.pen, .highlighter, .arrow, .rectangle, .redact, .text]`; otherwise `[.pen, .highlighter, .arrow, .rectangle, .spotlight, .text]`. `public static func forDigit(_ d: Int, mode: AppMode) -> Tool?` (index `d - 1` into that list). `public func isAvailable(in mode: AppMode) -> Bool`. `availableInCapture` and the one-argument `forDigit` are removed.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func digitFiveDependsOnMode() {
    #expect(Tool.forDigit(5, mode: .capturing) == .redact)
    #expect(Tool.forDigit(5, mode: .drawing) == .spotlight)
    #expect(Tool.forDigit(6, mode: .capturing) == .text)
    #expect(Tool.forDigit(7, mode: .capturing) == nil && Tool.forDigit(0, mode: .drawing) == nil)
}
@Test func availabilityByMode() {
    #expect(!Tool.redact.isAvailable(in: .drawing) && Tool.redact.isAvailable(in: .capturing))
    #expect(!Tool.spotlight.isAvailable(in: .capturing) && Tool.spotlight.isAvailable(in: .drawing))
}
// KeyCommandsTests: command(for: .digit(5), mode: .capturing, isEditingText: false) == .selectTool(.redact); .drawing → .selectTool(.spotlight)
// SessionTests: capture hotkey, selectTool(.redact) → tool == .redact; escape; pen hotkey → tool == .pen and effects contain .selectTool(.pen)
// SessionTests: in .drawing, command(.selectTool(.redact)) → no effects, tool unchanged
```

Replace `digitsMapToTools` and `spotlightIsLiveOnly` with these.

- [ ] **Step 2: Run to verify they fail**

Run: `scripts/test.sh`
Expected: compile failure on `forDigit(_:mode:)`.

- [ ] **Step 3: Implement**
  - `KeyCommands`: `Tool.forDigit(d, mode: mode)`.
  - `Session`: rename `fallBackFromSpotlight()` to `fallBackIfUnavailable()` using `tool.isAvailable(in: mode)` after `mode` is set; call it on `(.idle, .penHotkey)` as well as both capture entries; `apply(.selectTool)` rejects `!t.isAvailable(in: mode)`.
  - `DockView`: `tools` is `Tool.tools(for: state.mode)`; help text uses the tool's 1-based position in that list, not `rawValue` (so Redact reads "Redact (5)").

- [ ] **Step 4: Run tests**

Run: `scripts/test.sh`
Expected: all pass.

- [ ] **Step 5: Commit** — `feat: key 5 and the dock's fifth slot are Redact while capturing`

### Task 4: Draw redact boxes in capture

**Files:**
- Modify: `Sources/Tracer/InkView.swift`, `Sources/Tracer/AppController.swift`, `Sources/Tracer/DebugSelfTest.swift`

**Interfaces:**
- Consumes: `meanColor(of:scale:in:maxSide:)`, `InkModel.setActiveColor`, `isTooSmall`, `Tool.redact`.
- Produces: `InkView.frozenFrame: FrozenFrame?`; self-test suite `redact`.

- [ ] **Step 1: Write the self-test suite `redact`** (wired into `runIfRequested`), with a `HalfCapturer` whose frames are black on the left half and white on the right. Checks:
  - "no redact before frames": set `v.frozenFrame = nil`, select Redact, drag inside the selection → no stroke; restore the frame.
  - "key 5 picks redact": `handleSessionKey`-equivalent via `c.send(.command(command(for: .digit(5), mode: .capturing, isEditingText: false)!))` → `c.tool == .redact`; dock tool list has `.redact` fifth.
  - "box straddling the halves fills mid grey": drag a box centred on the screen's midline → stroke colour within 0.03 of 0.5 grey; `pixel(v, at: centre)` is opaque mid grey.
  - "box over white fills white": box wholly in the right half → fill white.
  - "tiny box dropped": a 1 pt-tall drag leaves no new stroke.
  - "arrow stays on top": draw an arrow, then a redact box over its middle → the arrow's pixel at the overlap is red.
  - "redo keeps the fill": ⌘Z the last box, ⌘⇧Z → restored stroke's colour equals the colour before undo.
  - "copied image is flat": copy, read the PNG; every sampled pixel inside the mid-grey box (inset 2 px) is the same colour.
  - "pen hotkey after capture falls back to pen": select Redact, Esc, pen hotkey → `c.tool == .pen`.

- [ ] **Step 2: Build and run it to see it fail**

Run (in a scratch worktree): `scripts/bundle.sh --debug && build/Tracer.app/Contents/MacOS/Tracer --self-test redact`
Expected: FAIL lines for the fill checks.

- [ ] **Step 3: Implement**
  - `InkView.frozenFrame`; in `mouseDown` with `.redact`, return without beginning a stroke when `frozenFrame` is nil.
  - `mouseDragged` for `.redact`: `model.setActiveColor` from `meanColor(..., maxSide: 64)` of the current box, before invalidating.
  - `endActiveStroke`: for `.redact`, set the exact mean (`maxSide: nil`) before `model.end`; replace the inline arrow check with `isTooSmall`.
  - `AppController.freeze()`: set `overlays.inkViews[id]?.frozenFrame = frame` alongside the frozen view; `.hideOverlays`: clear every ink view's `frozenFrame`.

- [ ] **Step 4: Run the suites**

Run: `--self-test redact`, then `capture`, `tools`, `review`, `regress`, `keys`.
Expected: `redact` all PASS; the others unchanged from `main` (live/settings/review each fail one hotkey check only while Leonard's Tracer is running).

- [ ] **Step 5: Commit** — `feat: drag a redact box over a capture`

### Task 5: Docs, full verification, PR

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**: under Capture a region add a bullet "Redact: drag a box to cover anything sensitive with a solid block in the page's own colour (it can't be undone in the saved image)"; in "While capturing" add `| 5 | Redact |`; add `redact` to the self-test suite list.
- [ ] **Step 2: Verify**: `scripts/test.sh` (all pass, count up from 87), `scripts/bundle.sh --debug` and the suites above in the scratch worktree.
- [ ] **Step 3: Commit, push `feat/redact`, open a PR** listing what was verified and Leonard's hand-check: redact a real console screenshot, paste into Slack, save a PNG and a JPEG, confirm nothing shows through.
