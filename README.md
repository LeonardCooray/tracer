# Tracer

Draw on your Mac's screen to point things out, then take screenshots of what you marked up.

Tracer lives in the menu bar. Press a hotkey, draw over whatever's on screen with ink that fades on its own, and press it again to hand the mouse straight back to your apps. A second hotkey freezes the screen so you can drag out a region and copy or save it at full Retina resolution, ink included. Nothing leaves your Mac.

## Keys

| Key | What it does |
|---|---|
| ⌥⇧D | Turn the pen on or off (turning it off clears the ink) |
| ⌥⇧S | Capture a region (works while drawing, keeping the ink) |
| 1–6 | Pen, highlighter, arrow, rectangle, spotlight, text |
| Shift while drawing | Keep that stroke instead of letting it fade |
| ⌘Z / Delete | Undo the last stroke / clear everything |
| Esc | Leave drawing or cancel a capture |
| Return or ⌘C | Copy the selection (capture mode) |
| ⌘S | Save the selection to your folder (capture mode) |

Both hotkeys can be changed in Settings. The spotlight and cursor ring are for pointing live and never appear in screenshots.

## Build

Needs macOS 27 and the Xcode Command Line Tools (full Xcode isn't required).

```bash
scripts/test.sh          # unit tests
scripts/bundle.sh        # builds and signs build/Tracer.app
open build/Tracer.app
```

Use `scripts/test.sh` rather than `swift test`. The Command Line Tools build sometimes loses the Swift Testing plugin path, and the script passes it explicitly. For the same reason, the app code avoids SwiftUI macros such as `@State`.

A debug build has a smoke test that drives the real overlays: `scripts/bundle.sh --debug`, then `build/Tracer.app/Contents/MacOS/Tracer --self-test live`. The other suites are `tools`, `capture`, `settings` and `displays`.

## Signing and permissions

Screenshots need **Screen Recording** permission, which macOS ties to the app's signature. Create the one-time self-signed certificate in [docs/signing.md](docs/signing.md) so the permission survives rebuilds. Without it, `bundle.sh` signs ad hoc and macOS asks again after every build.

Tracer never asks for Accessibility or Input Monitoring. Hotkeys use the system hotkey API, and drawing works without any permission.

## Design

The design and the implementation plan are in [docs/superpowers](docs/superpowers).
