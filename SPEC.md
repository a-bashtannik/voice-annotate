# voice-annotate — Spec v0.1

A macOS menu bar utility: press a hotkey, talk, point at things on screen, and get an
agent-ready bundle (annotated images + timestamped transcript) on the clipboard.

## 1. Goals / non-goals

**Goals**
- One hotkey to start, one to finish. Zero dialogs in the hot path.
- Two modes: **Snapshot** (freeze screen, draw on it) and **Walkthrough** (record while
  you keep using the computer, draw on top when needed).
- Output that *any* agent can consume: Claude Code (terminal), claude.ai / ChatGPT web,
  Cursor/IDE agents.
- Fully local and free: no API keys, no network.
- Fast: bundle on clipboard < 2 s after finishing a 30 s Snapshot capture.

**Non-goals (v1)**
- Sending video to agents (almost none accept it — see §4).
- Cloud sync, sharing links, editing past captures, Windows/Linux.
- Languages other than English.

## 2. User flows

### 2.1 Snapshot mode (default hotkey `⌃⌥⌘S`)
1. Hotkey → instant screenshot of the display under the cursor; mic starts recording.
2. A borderless full-screen overlay shows the frozen frame with a small floating toolbar
   (recording indicator, tools, timer).
3. User talks and draws. Tools: pen, arrow, rectangle, highlighter, **numbered pin**
   (click → drops ①, ②, …), undo (`⌘Z`).
4. `Enter` or hotkey again → finish. `Esc` → cancel and discard.
5. Transcribe → compose bundle → copy to clipboard → small HUD toast "Copied ✓ (3 pins, 42 words)".

### 2.2 Walkthrough mode (default hotkey `⌃⌥⌘R`)
1. Hotkey → screen recording of the display under the cursor + mic start. A small HUD shows
   recording state and elapsed time.
2. A transparent overlay sits above all windows but **passes clicks through** — the user
   keeps navigating normally.
3. **Draw mode** is toggled by holding a modifier (default: `fn`/`⌥`, see risk R3) or
   tapping `⌃⌥⌘D`. While active, the overlay captures the mouse; strokes fade after ~2.5 s
   (laser-pointer style). Pins persist until the next significant screen change.
4. The overlay is *included* in the capture, so annotations are burned into frames for free.
   The HUD/toolbar window is *excluded* (`SCContentFilter` exclusion).
5. Hotkey again → stop → keyframe extraction (§4) → transcribe → bundle → clipboard.
6. Hard cap: 5 min (configurable), with a warning at 4:30.

## 3. Architecture

Native Swift 6 / SwiftUI app, `LSUIElement` (menu bar only), macOS 26+.

```
┌───────────────────────── App (MenuBarExtra) ─────────────────────────┐
│ HotkeyService ──► SessionController (state machine per capture)      │
│                     │                                                │
│   ┌─────────────────┼──────────────────┬───────────────────┐         │
│   ▼                 ▼                  ▼                   ▼         │
│ CaptureService   AudioRecorder    OverlayController    EventLogger   │
│ (ScreenCaptureKit) (AVAudioEngine)  (NSWindow + Canvas)  (clicks, pins,│
│                                                         strokes, t)  │
│   └──────────────┬──┴──────────────────┴───────────────────┘         │
│                  ▼                                                   │
│        Pipeline: KeyframeSelector → Transcriber → BundleComposer     │
│                  ▼                                                   │
│             ClipboardWriter                                          │
└──────────────────────────────────────────────────────────────────────┘
```

| Component | Tech | Notes |
|---|---|---|
| Hotkeys | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) | Carbon `RegisterEventHotKey` underneath — no Accessibility permission needed; user-rebindable. |
| Screenshot | `SCScreenshotManager.captureImage` | Display under cursor. |
| Screen video | `SCStream` → `AVAssetWriter` (HEVC, 10 fps, native res capped at 1920 px wide) | Low fps keeps files small; we only need keyframes. Frames also tapped live for keyframe scoring. |
| Audio | `AVAudioEngine` input tap → 16 kHz mono buffer + `.m4a` file | Same buffer is fed to the transcriber. |
| Overlay | Borderless `NSPanel`, `.screenSaver` level, `canJoinAllSpaces`; `ignoresMouseEvents` toggled for pass-through | SwiftUI `Canvas` for strokes. Every stroke/pin is timestamped. |
| Click logging | `NSEvent.addGlobalMonitorForEvents(.leftMouseDown)` | Optional; needs Accessibility. Used as keyframe signal + "[click at (x,y)]" in transcript. Degrades gracefully if denied. |
| Transcription | **Apple `SpeechAnalyzer` + `SpeechTranscriber`** (macOS 26) | Free, on-device, word-level `audioTimeRange`. Model assets via `AssetInventory` (one-time download, system-managed). Contextual strings for jargon if supported. |
| Transcription fallback | [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT) | Behind a protocol `Transcriber`; only if SpeechAnalyzer quality is insufficient on technical vocab. |
| Image processing | Core Image / vImage | Downscale, diff, perceptual hash. |

### 3.1 Session state machine
`idle → arming → recording(mode) → finishing → processing → done(bundle) | failed(error) | cancelled`.
One session at a time; hotkey during `processing` is ignored with a HUD hint.

### 3.2 Permissions (requested lazily, first use)
| Permission | Needed for | If denied |
|---|---|---|
| Screen Recording | both modes | hard fail, open System Settings pane |
| Microphone | both modes | continue silent (annotations only) |
| Speech recognition | maybe for SpeechTranscriber — verify | fall back to no transcript, keep audio file |
| Accessibility | click logging only | skip click events |

**Dev gotcha:** ad-hoc signed rebuilds reset the Screen Recording (TCC) grant every build.
Sign with a stable Apple Development certificate from day one.

## 4. The "compact format": keyframe storyboard

Agents take images + text, not video. So a Walkthrough is compressed into **≤ N keyframes
(default 8)** aligned to the transcript.

**Candidate signals** (sampled from the live stream at 2 fps, 256 px grayscale thumbnails):
- **Visual change**: mean abs diff vs. last kept frame; spikes = navigation/new view.
- **Settle**: frame after a change once the screen is stable for ≥ 400 ms (avoid
  mid-animation frames — always prefer the settled frame over the spike frame).
- **Annotation**: frame at the end of every stroke/pin (most important signal — the user
  explicitly pointed at something).
- **Click**: settled frame ~300 ms after a click.
- **Speech**: frame at the start of each speech segment / after long pauses (> 1.2 s).

**Selection**: score = weighted sum of signals → non-max suppression in time (min 1.5 s
apart) → dedupe by dHash (Hamming < 6) → keep top N, sorted chronologically. Always keep
the first and last frame. Tunable weights in a constants file; we'll calibrate on real captures.

**Image output**: PNG, long edge downscaled to 1568 px (Claude's sweet spot; also fine
for GPT/Gemini). Snapshot mode emits 1 image (annotated) + optionally the clean original.

The full `.mp4` and `.m4a` are kept in the bundle folder for agents/tools that *can* use
them (e.g. Gemini), but are not put on the clipboard by default.

## 5. Bundle format

Folder: `~/Library/Application Support/voice-annotate/captures/2026-11-02_14-03-12/`
(auto-pruned after 7 days, configurable).

```
capture.md
frame_01.png
frame_02.png
...
audio.m4a
recording.mp4        # walkthrough only
events.json          # raw timeline: words, strokes, pins, clicks, keyframes
```

`capture.md` — the thing agents read. Transcript is interleaved with frame references
and pin/click markers at the moment they happened, so "this one" is grounded:

```markdown
# Screen capture — 2026-11-02 14:03 (walkthrough, 0:47)

Images: frame_01.png … frame_04.png in /Users/…/captures/2026-11-02_14-03-12/

[00:00] ![frame_01](…/frame_01.png)
So I'm on the settings page and when I click save [click @ 812,440]

[00:06] ![frame_02](…/frame_02.png)
this error shows up [pin ①] even though the form is valid. And this field here [pin ②]
should actually be optional.

[00:19] ![frame_03](…/frame_03.png)
...
```

Pins are drawn as numbered circles in the image *and* referenced in the text, which gives
the agent an unambiguous pointer↔speech link.

## 6. Clipboard strategy ("paste into anything")

The pasteboard can hold multiple items with multiple representations; each target reads
what it understands. We write **one pasteboard write** containing:

1. **Item 0** — `public.utf8-plain-text`: `capture.md` content with absolute image paths.
   → Terminals (Claude Code) paste this; Claude Code reads the images from the paths.
2. **Items 1…N** — `public.file-url` per PNG (+ `public.png` data on each).
   → Browsers / Electron apps that accept pasted files get attachments.

Since targets differ in how they handle mixed pasteboards, the menu bar also offers
**"Copy as…"** for the last capture: *Text + paths* (terminal), *Images + text* (web),
*Single composite image* (contact sheet with transcript underneath — for targets that only
take one image). A per-app default can be set (frontmost app at finish time decides).

→ **Validate early** (milestone M3): a paste test matrix across Claude Code / iTerm,
Terminal, claude.ai (Safari + Chrome), ChatGPT web, Cursor, VS Code Copilot chat.

## 7. Settings (minimal)
Hotkeys · max keyframes · max walkthrough length · keep clean original (Snapshot) ·
retention days · per-app paste format · fade duration · mic device.

## 8. Milestones

| # | Deliverable | Done when |
|---|---|---|
| M0 | Xcode project, menu bar app, hotkeys, permission onboarding, stable signing | Hotkey shows a HUD toast; permissions flow works |
| M1 | Snapshot capture + overlay drawing (pen, arrow, rect, highlight, pins, undo) | Annotated PNG written to bundle folder |
| M2 | Audio + SpeechAnalyzer transcription with word timestamps; pins/strokes interleaved | `capture.md` correct for a Snapshot |
| M3 | ClipboardWriter + paste test matrix | Snapshot bundle pastes usefully into all targets in §6 |
| M4 | Walkthrough recording, pass-through overlay, draw-mode toggle, fading strokes, HUD excluded from capture | `.mp4` with burned-in annotations |
| M5 | KeyframeSelector + click logging | ≤ 8 sensible frames from a real 1-min walkthrough |
| M6 | Settings, retention, "Copy as…", polish | Daily-drivable |

Snapshot mode alone (M0–M3) is already useful and is the first shippable cut.

## 9. Risks / open questions

- **R1 – Mixed-pasteboard behavior** varies per app (some paste only text, some only the
  first image). Mitigation: "Copy as…" + per-app defaults; M3 test matrix.
- **R2 – SpeechAnalyzer quality on code/tech jargon.** Mitigation: contextual strings
  (if available), `Transcriber` protocol with WhisperKit fallback.
- **R3 – Draw-mode modifier in Walkthrough.** Observing a held modifier globally
  (`flagsChanged` global monitor) likely needs Accessibility. Default to a toggle hotkey
  (no permission), offer hold-to-draw when Accessibility is granted.
- **R4 – Multi-monitor.** v1 captures the display under the cursor at start only.
- **R5 – Fullscreen apps / Spaces / Stage Manager** may hide or reorder the overlay —
  test early in M1.
- **R6 – Privacy.** Recordings may contain secrets; everything stays local, auto-pruned,
  and the clipboard only carries what's in the bundle.
- **Q1** – Should Snapshot also allow scrolling/switching to a second screenshot within one
  session (multi-shot Snapshot)? Cheap to add after M3.
- **Q2** – Distribution: personal build only, or notarized DMG / Homebrew cask later?
