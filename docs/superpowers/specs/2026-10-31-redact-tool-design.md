# Redact tool (short design)

31 Oct 2026. Small change; agreed with Leonard in conversation.

## Why

Screenshots from the SentinelOne, NinjaOne and AWS consoles carry hostnames, IPs, account IDs and tokens. Before pasting one into Slack or Jira, the sensitive parts need hiding in Tracer itself, so the copied or saved image is safe as it leaves the app.

## Goals

- **Leonard:** a redacted area must be unrecoverable, not just hard to read at a glance.
- **Leonard:** you draw the boxes yourself; Tracer doesn't hunt for sensitive text.
- Drag a box over the frozen screenshot in capture mode and everything under it is replaced.

## Non-goals

- Automatic detection of IPs, hostnames, emails or keys (Leonard ruled it out; roughly triples the work).
- Redaction in live drawing mode. The screen keeps changing under live ink, so it would need continuous screen recording.
- Editing or moving a redact box after it's drawn. No other shape can be edited either.

## Anti-goals

- Blur or pixelation. A blur over text can be partly reversed and small pixel blocks can be guessed back (Depix), so neither meets "unrecoverable".
- Any output where the original pixels survive under the redaction, such as a layer or a semi-transparent fill.

## Approaches

1. **A redact box is a stroke (chosen by Leonard).** A new `Tool.redact`. On mouse-up the box's fill colour is worked out once from the frozen frame and stored on the stroke; from then on it renders as a plain opaque filled rectangle. Undo, redo, Delete, the dock, number keys and the compositor all work as they do for other tools. Trade-off: the colour is fixed at mouse-up, which is fine because the frozen frame can't change.
2. **Paint redactions into the frozen frame.** The preview is the literal output, but undo needs a second history of frame copies kept in step with ink undo across mixed ⌘Z, which is where bugs would come from. Not safer than 1, whose output is already one flat image.
3. **Compute the fill on every redraw.** The renderer would take the frozen frame and average under each box every frame. More work per redraw for no gain over 1.

## Behaviour

- **Key and dock (my call):** in capture mode, key 5 and the dock's fifth slot are Redact, taking the place spotlight leaves free there. In live mode, 5 stays Spotlight and Redact never appears. The dock icon is a filled rectangle.
- **Drawing (my call):** drag a box like the rectangle tool. Boxes under about 2 pt on either side are dropped, like a too-short arrow. A box may extend past the selection; the output crops it.
- **Fill (my call):** the mean colour of the frozen frame's pixels under the box, at full opacity, with no outline. It must be a true mean over the box's pixels at native resolution, not one sampled pixel, so it reads as part of the page. The dock's colour swatches and widths don't apply to Redact.
- **Order (my call):** redact boxes always draw before all other ink, on screen and in the output, so an arrow pointing at a redacted field stays visible even if the box was drawn after it.
- **Undo (my call):** ⌘Z, ⌘⇧Z and Delete treat a redact box like any other stroke. Capture never fades ink, so boxes stay until undone or the capture ends.
- **Multiple displays (my call):** the fill comes from the frozen frame of the display the box is drawn on.
- **Mode changes (my call):** capture always ends in idle, so redact boxes never reach live mode. If Redact is the selected tool when live drawing starts, the tool falls back to Pen, mirroring how Spotlight falls back to Pen on entering capture.

## Constraints

- Ink stays smooth at 120 Hz. If averaging a large box on every drag event costs too much, the builder may preview with a cheaper estimate during the drag, as long as the exact mean is used from mouse-up on.
- The copied and saved image is one flat bitmap with the fill baked in (already true of `Compositor`).
- No new permissions. No SwiftUI or Observation macros (toolchain quirk).

## Where it touches

- `TracerCore/Tool.swift`: `.redact`, availability per mode, digit mapping that depends on mode.
- `TracerCore/KeyCommands.swift`, `Session.swift`: mode-aware digit 5; fall back from Redact on entering live mode.
- `TracerCore/InkRenderer.swift`: opaque filled rect for `.redact`; `inkBounds` for it; redact strokes drawn first.
- `TracerCore/Compositor.swift`: same ordering.
- `Tracer/InkView.swift` / `AppController.swift`: work out the fill from the frozen frame at mouse-up and give the in-progress box a fill while dragging.
- `Tracer/DockView.swift`: dock slot and icon.

## Verification

- Unit tests: the mean colour over a known region; a composited image whose redacted region is exactly one colour over a checkerboard base, with no original pixel left; an arrow drawn before a redact box still on top; digit 5 maps to Redact in capture and Spotlight live; the fall-back to Pen on entering live.
- `--self-test capture`: Redact selectable by key 5 and the dock; a dragged box fills with the frame's mean colour on screen.
- Leonard's hand-check: redact a real console screenshot, paste it into Slack and save a PNG, and confirm nothing shows through.

## Left to the builder

- How the mean is computed (Core Graphics downsample, vImage or a plain loop), as long as it's a true mean at native resolution.
- The exact dock icon and the 2 pt minimum.
- Where the fill colour lives on the stroke (`style.color` is the obvious place).
