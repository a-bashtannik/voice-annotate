# voice-annotate — Spec v0.3

A macOS menu bar utility: press a hotkey, talk, point and draw on screen, and get an
agent-ready bundle (annotated images + timestamped transcript with grounded references to
every drawing) on the clipboard. Fully local, free, no API keys.

## 1. Goals

- One hotkey to start, one to finish. No dialogs in the hot path.
- Two modes:
  - **Snapshot** — freeze the screen, draw on it while talking. Multi-shot: hide the
    overlay, navigate, grab the next shot, keep talking — all in one capture.
  - **Walkthrough** — record the screen while you keep using the computer; draw on top
    whenever you want (hold-to-draw or toggle).
- Every annotation (circle, arrow, box, highlight, underline, pin, freehand) is numbered,
  burned into the image, *and* referenced in the transcript at the moment it was drawn,
  with its location in image pixel coordinates.
- Output pastes usefully into any agent: Claude Code (terminal), claude.ai / ChatGPT web,
  Cursor / IDE chats.
- Transcription: WhisperKit (MIT, on-device, Apple Silicon optimized), word-level
  timestamps, custom vocabulary prompt.
- Bundle on the clipboard within ~2–4 s after finishing (model kept warm).

Non-goals: cloud anything, editing past captures, non-English, Windows/Linux.

## 2. User flows

### 2.1 Snapshot (default `⌃⌥⌘S`)
1. Hotkey → screenshot of the display under the cursor (native resolution); mic starts.
2. Full-screen overlay shows the frozen frame; floating toolbar at the top (timer, mic
   level, tools, colors, undo, next-shot, finish, cancel).
3. Draw while talking. Keys: `P` smart pen · `A` arrow · `R` rectangle · `O` ellipse ·
   `H` highlighter · `N` pin · `1–6` colors · `⌘Z` undo · `⌫` delete last.
4. `Tab` → **next shot**: overlay hides, audio keeps recording, HUD says "navigate, then
   press ⌃⌥⌘S for the next shot". Hotkey → new screenshot, overlay returns.
5. `Enter` (or hotkey ⌃⌥⌘F) → finish. `Esc` → cancel & discard.
6. Focus returns to the app that was frontmost before capture so you can paste immediately.

### 2.2 Walkthrough (default `⌃⌥⌘R`)
1. Hotkey → records the display under the cursor + mic. HUD at top: rec dot, timer, mic
   level, draw-mode state, tools/colors, finish, cancel.
2. Transparent overlay above everything, click-through by default.
3. **Draw mode**: hold `⌃⌥` (configurable; polled via `CGEventSource.flagsState`, no
   permission needed) or toggle with `⌃⌥⌘D`. While on, the overlay takes the mouse.
4. Strokes fade after 3 s (configurable), pins after 5 s — laser-pointer feel.
5. Overlay is *in* the capture (annotations burned into frames); HUD/toasts are excluded
   via `SCContentFilter(excludingWindows:)` + `sharingType = .none`.
6. Same hotkey (or `⌃⌥⌘F`) → stop. Auto-stop at max length (default 10 min).

### 2.3 Multiple displays
All connected displays take part (setting "Capture all displays", default on):
- **Snapshot** freezes every display at once; draw on any of them (the overlay under the
  pointer takes focus on click). Frames = the display the cursor was on + every display that
  was annotated, per round.
- **Walkthrough** records every display in parallel (one ScreenCaptureKit stream + HEVC file
  each) with a click-through overlay on each. The cursor's display over time is the user's
  focus: optional keyframes only come from the display the cursor was on (±1 s), a stay of
  ≥ 2 s on another display adds a "display switch" frame, start/end frames come from the
  first/last display. Annotations are always kept wherever they were drawn. The HUD follows
  the cursor. Frames are numbered chronologically across displays and labelled with the
  display name in `capture.md`; `events.json` lists each display's canvas size.

### 2.4 After finishing
HUD toast: "Transcribing…" → "Copied ✓ 9 frames · 3 annotations · 142 words". Menu bar
→ *Recent captures* → copy again in another format / reveal in Finder.

## 3. Annotations

| Tool | Description in transcript |
|---|---|
| Smart pen (freehand) | auto-classified on release: closed loop → **circled** region; near-straight → **underline/line**; else **drawing over** region |
| Arrow | **arrow** from (x,y) **pointing at** (x,y) |
| Rectangle | **box around** (x1,y1)–(x2,y2) |
| Ellipse | **circled** region (x1,y1)–(x2,y2) |
| Highlighter | **highlighted** region |
| Pin | **pin** at (x,y) |

Each annotation gets a sequential number `#n` per capture, drawn as a badge next to it
(pins *are* the badge). In the transcript it appears as
`[#3 circled (412,230)–(640,310) in frame 2]`, inserted at the word being spoken when
drawing started. All coordinates are in the output image's pixel space, top-left origin.

## 4. Walkthrough → keyframe storyboard

Agents don't take video, so a walkthrough becomes an adaptive set of keyframes.

**Live analysis** (ScreenCaptureKit stream, up to 10 fps, frames only on change): each
frame → 64×40 luminance thumbnail; mean-abs-diff vs previous.

**Candidates** (session time):
- **Settle** after an activity burst (consecutive changing frames) — scored by net change
  between before/after thumbnails; long bursts (scrolling, video) emit every 4 s.
- **Annotation burst end** (+150 ms, so the stroke is rendered) — *always kept*; bursts
  merge annotations drawn ≤ 1.5 s apart without a screen change, so one frame shows all.
- **Click** (global mouse monitor, no permission needed) → next settle or +500 ms.
- **Speech segment start**, low weight; **first** and **last** frame always.
- **Periodic fallback** every 15 s of no other candidate.

**Selection**: annotation frames first, then by score with ≥ 1.2 s spacing; an optional
frame is dropped if it looks identical to its chronological neighbours (so returning to an
earlier view is kept), and the end frame is dropped if it shows nothing new. Budget:
`max(6, duration / 5 s)`, capped by the *max frames* setting (default 30), shared across
displays.

**Detail crops**: on large displays (output < 0.8 px per point, e.g. a 3008 pt wide 4K/6K
screen at 1568 px) frames with annotations get an extra native-resolution crop around them. Frames are extracted from the recorded HEVC file
post-hoc with `AVAssetImageGenerator` (zero tolerance), downscaled to 1568 px long edge.

## 5. Bundle

`~/.voice-annotate/captures/2026-11-02_14-03-12/` (no spaces in paths so terminals and
agents handle them; auto-pruned after 14 days)

```
capture.md         # what the agent reads
frame_01.png …     # annotated keyframes / shots
audio.m4a
recording.mp4      # walkthrough: video + mic audio (muxed in background);
                   # recording_displayN.mp4 per display when several were recorded
events.json        # full timeline: words, annotations (+geometry), clicks, frames
```

`capture.md`:

```markdown
# Screen capture · walkthrough · 0:47 · 2026-11-02 14:03

The user recorded their screen while talking. Numbered marks (#1, #2, …) in the images are
the user's own annotations; each appears in the transcript where it was drawn. Coordinates
are pixels in the referenced image (origin top-left).

Frames (1568×1018 px):
- frame 1 · 00:00 · /Users/…/frame_01.png
- frame 2 · 00:06 · /Users/…/frame_02.png

## Transcript

**[00:00 · frame 1]** So I'm on the settings page and when I click save [click at (812,440)]

**[00:06 · frame 2]** this error shows up [#1 circled (400,220)–(620,300)] even though…
```

## 6. Clipboard

Default **Universal** write — one pasteboard write, multiple items:
1. item 0: `public.utf8-plain-text` = `capture.md` (absolute image paths) → terminals,
   Claude Code (reads/attaches the paths).
2. items 1…N: `public.file-url` + `public.png` per image → browsers/Electron accept them as
   attachments.

*Copy as…* (menu, per recent capture): **Text + paths**, **Images + text** (images first),
**Images only**, **Composite** (single tall image: frames + transcript rendered beneath, for
targets that take one image), **Markdown file** (the .md file itself as file URL).

## 7. Architecture

Swift 6 toolchain (Swift 5 language mode), SwiftPM, macOS 26+, `LSUIElement` agent app,
assembled into a signed `.app` by `scripts/build-app.sh`.

- `VoiceAnnotateCore` (pure, unit-tested): models, shape classifier, keyframe selector,
  transcript interleaver, markdown composer, geometry mapping.
- `VoiceAnnotate` (app): hotkeys (Carbon `RegisterEventHotKey`), `SessionController`
  state machine, `ScreenCapturer` (SCScreenshotManager + SCStream → AVAssetWriter HEVC
  + live thumbnails), `AudioRecorder` (AVAudioEngine → 16 kHz mono + m4a), overlay
  (`NSPanel` + custom `NSView`, shared `AnnotationRenderer` for on-screen and offline
  rendering), HUD (SwiftUI in `NSPanel`), `Transcriber` (WhisperKit, preloaded at launch,
  model in `~/.voice-annotate/models`), `BundleWriter`, `ClipboardWriter`, settings window,
  onboarding/permissions window, launch-at-login (`SMAppService`).

Clock: everything is in host time (`mach_absolute_time` seconds — same base as
`CACurrentMediaTime`, SCStream PTS, `AVAudioTime.hostTime`, `NSEvent.timestamp`) minus
session start.

## 8. Permissions

| Permission | For | If denied |
|---|---|---|
| Screen Recording | both modes | can't capture → onboarding window explains + opens Settings |
| Microphone | voice | capture continues without transcript |

No Accessibility / Input Monitoring needed (hotkeys via Carbon, modifier polling via
`CGEventSource`, mouse-down global monitor).

Signed with the stable Apple Development identity so TCC grants survive rebuilds.

## 9. Settings

Hotkeys (recorder) · Whisper model (default `openai_whisper-large-v3-v20240930_turbo_632MB`,
alternatives small.en / base.en) · compute (Auto / GPU / Neural Engine) · custom vocabulary · max frames · image long edge ·
max walkthrough length · fade duration · draw-mode modifier · keep clean originals ·
default clipboard format · retention days · sounds · launch at login.

## 10. Risks

- Mixed pasteboards are interpreted differently per app → *Copy as…* formats.
- First Neural Engine compile of the large encoder takes ~10 min on an M1 Pro (cached
  afterwards, invalidated when the binary changes). **Auto** compute loads a GPU-encoder build
  first (~15 s cold, ~3 s warm; ~0.25× real time) and swaps in the Neural Engine build
  (~0.08× real time) once it has compiled in the background.
- Overlay vs. fullscreen apps / Stage Manager → `canJoinAllSpaces` + `fullScreenAuxiliary`.
- Displays connected/disconnected mid-capture are not handled (the display list is fixed at
  start).
- Recordings can contain secrets → local only, auto-pruned.
