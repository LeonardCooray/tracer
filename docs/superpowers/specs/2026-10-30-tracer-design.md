# Tracer (Lightshot REA): design

*30 Oct 2026. Agreed with Leonard in conversation. "My call" marks what Claude proposed; Leonard accepted those as part of a full playback of the behaviour ("this sounds good") rather than choosing each one. Prior-art research is in `prior-art-research-2026-10-30.md` next to this file. Approved by Leonard on 30 Oct 2026.*

## Intent

Leonard wants a Mac app for the moment he wants to point something out on screen: press a key, draw over whatever is running, then get out of the way. It also takes Lightshot-style region screenshots that include the drawing. It borrows the good ideas from Lightshot (fast region capture, a toolbar right beside the selection, instant copy) and ScreenBrush (live drawing, fading ink, keyboard control), with a cleaner, more modern UI than either.

It's a personal tool on Leonard's own Mac, not a product for sale.

## Goals

- Drawing live over any app, full-screen apps included, on every connected display.
- Pointing tools that suit a quick "look here": fading ink, spotlight, cursor highlight, arrows and boxes.
- Region screenshots at full Retina resolution, copied to the clipboard (main action) or saved to a folder (secondary), each on a key.
- Keyboard-first: every common action has a key; the UI stays small and out of the way.
- Feels like a well-made native Mac app.

## Non-goals (first version)

- Share links, uploading or any network use. Nothing leaves the Mac.
- Scrolling capture, window capture, screen recording or video.
- A separate image editor after capture (crop, blur, layers, filters).
- Whiteboard mode, zoom/magnifier, numbered badges, presentation remote.
- Windows or Linux.

## Anti-goals

- A toolbar or ink that gets in the way: if switching the pen off doesn't instantly hand the mouse back to the apps underneath, it has failed.
- Laggy ink. Strokes must track the pointer smoothly on the 120 Hz built-in display.
- Copying Lightshot's or ScreenBrush's code, icons, assets or branding. We study behaviour, we write our own.

## Constraints

- Leonard's Mac: MacBook Pro, Apple M5 Pro, macOS 27.2, built-in 3024×1964 Liquid Retina XDR display (ProMotion). External displays must work too.
- Toolchain: Swift 6.4.2 with the Xcode Command Line Tools only; no full Xcode installed. The build must work with SwiftPM from the command line.
- No code-signing identities exist on the Mac yet.
- The Mac runs SentinelOne. In Sep 2026 S1 flagged a LaunchAgent persistence install (Candledeck) as malware. An app that captures the screen, registers global hotkeys and starts at login may be flagged similarly.
- Screenshots need macOS Screen Recording permission, which macOS ties to the app's code signature.
- Code comments are one short line or none. Public commits use leonardcooray@gmail.com. Work goes on feature branches with PRs; Leonard merges.

## Approaches considered

1. **Native Swift app (chosen).** AppKit borderless overlay panels per display for ink, ScreenCaptureKit for screenshots, Carbon `RegisterEventHotKey` for global hotkeys, SwiftUI for the settings window. Reliable click-through toggling, smooth drawing, small app, native look. Cost: all Swift, no web UI.
2. **Tauri (web UI in a native shell).** UI in HTML/JS like Candledeck. Rejected: transparent click-through overlays are the weak spot on macOS, and native code is still needed for hotkeys, capture and the overlay, so it fights the core feature.
3. **Electron.** Rejected for the same overlay problems plus a ~150 MB app.

Leonard picked 1 because the overlay is the core of the app and native is strongest there.

## What was decided

### Live drawing mode

- **Toggle (my call):** one global hotkey turns the pen on; pressing it again or Esc turns it off, clears all ink and makes the overlay click-through again. No half-drawing, half-clicking state.
- **Toolbar (Leonard: mockup C):** a slim vertical dock of tools on the screen edge that slides in when the pen is on and slides away when it's off, appearing on whichever display the pointer is on. A small label beside the pointer shows the current tool and fade time (for example "Rectangle · fades 3s").
- **Tools, switched with number keys 1–6 (my call on the list and order):** 1 pen, 2 highlighter (wide, semi-transparent), 3 arrow, 4 rectangle, 5 spotlight (dims everything except a circle around the pointer), 6 text.
- **Cursor highlight (my call):** a ring that follows the pointer; can stay on with the pen off.
- **Ink (my call):** strokes fade after 3 s by default, adjustable 1–10 s in settings. Holding Shift while drawing keeps a stroke until cleared. ⌘Z undoes the last stroke, Delete clears all. A few preset colours at the bottom of the dock; right-click the dock for a full colour picker and stroke widths.
- **Displays (my call, from the research):** every connected display from the first version.

### Screenshot mode

- **Leonard:** screenshots are a full feature in the first version. Output is copy to clipboard (main) and save to folder (secondary), both on keys. No share links or uploads. Always highest quality at full Retina size; the user picks PNG or JPEG.
- **Toolbar (Leonard: mockup B):** the same slim dock snaps to the edge of the selection, with the drawing tools on top and Copy and Save at the bottom. The size and format show beneath the selection (for example "1240 × 680 · PNG"), with a key hint. The dock flips to the other side near screen edges.
- **Keys (my call):** a separate global capture hotkey; drag a region; Return or ⌘C copies, ⌘S saves, Esc cancels. Same drawing tools work on the selection.
- **From live mode (my call):** pressing the capture hotkey while the pen is on freezes the screen with the ink on it, then you drag the region.
- **Saving (my call):** to a folder chosen in settings, files named by date and time, no save dialog.

### Settings and app shell

- **My call:** menu bar icon (no Dock icon) with a settings window for both hotkeys, fade time, save folder, image format and launch at login. Launch at login uses Apple's `SMAppService` rather than a hand-written LaunchAgent, to give S1 the least to object to.

### Settled after the builder check (my calls)

- **Ink in screenshot mode never fades.** It's drawn on a frozen image, so arrows and boxes stay until Esc, undo or Delete. Fading applies only in live mode.
- **The spotlight and cursor ring are live-only.** They never appear in a screenshot. Ink drawn live before a freeze is captured as it looked at the moment of the freeze.
- **The selection can be moved and resized after drawing.** The ink belongs to the frozen image, not the selection, so it stays put.
- **Text tool:** click to place a text box. The app takes keyboard focus while you type, and while typing the tool keys, Delete and ⌘Z act on the text, not the ink. Return or a click elsewhere finishes the text and Esc cancels only that text. In live mode, text starts fading once it's finished. Focus goes back to the previous app when the pen turns off.
- **No Accessibility or Input Monitoring permission**, as a firm rule. Hotkeys use Carbon `RegisterEventHotKey`. While the pen is on, the tool keys, Esc, Delete and ⌘Z are registered as temporary hotkeys and released when it turns off. Screen Recording is the only permission the app asks for.
- **SentinelOne:** build normally. If S1 flags the app, Leonard marks it as a false positive himself, as he did for Candledeck.
- **Minimum macOS:** the current release, macOS 27.
- **Device management:** the Mac isn't MDM-enrolled (checked 30 Oct 2026), so nothing should stop Leonard granting Screen Recording.

## Left to the builder

- Internal architecture, module layout, and whether ink renders with Core Animation layers, Core Graphics or Metal, as long as it's smooth at 120 Hz.
- How the frozen frame and ink are composited into the final image, as long as the output is full native resolution and includes the ink.
- Default hotkeys (avoid clashing with macOS's own ⇧⌘3/4/5), default colours, stroke widths and JPEG settings, consistent with "highest quality".
- Exact dock, label and selection styling, following the approved mockups (dark translucent glass, rounded corners, system font).
- How the `.app` bundle is assembled and signed from SwiftPM, and the test approach.
- How REA is used, if at all, to study ScreenBrush or Lightshot behaviour during the build.

## Open questions

*(none)*

## Decided after the builder check (Leonard)

- **Signing:** Leonard creates a free self-signed code-signing certificate once in Keychain Access, following steps Claude provides. Every build is signed with it, so Screen Recording permission survives rebuilds.
- **Name:** **Tracer**. Bundle ID `com.leonardcooray.tracer` (my call).
- **Code location:** a public GitHub repo `LeonardCooray/tracer`, cloned at `/Users/leonard/src/tracer`. Commits use leonardcooray@gmail.com. Notes from studying other apps describe behaviour only, with no copied code or assets.
