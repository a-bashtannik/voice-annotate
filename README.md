# voice-annotate

macOS menu bar utility: press a hotkey, talk, point and draw on your screen(s), and get an
agent-ready bundle (annotated images + timestamped transcript that references every drawing)
on the clipboard. Fully on-device (WhisperKit), no API keys. Design: [SPEC.md](SPEC.md).

## Use

| Shortcut | |
|---|---|
| `⌃⌥⌘S` | **Snapshot** — freezes all displays; draw and talk. `⇥` hide overlay & navigate, `⌃⌥⌘S` next shot, `↩`/`⌃⌥⌘S` finish, `⎋` cancel |
| `⌃⌥⌘R` | **Walkthrough** — records all displays while you work; hold `⌃⌥` (or `⌃⌥⌘D` toggle) to draw; `⌃⌥⌘R` again to finish |
| `⌃⌥⌘F` | Finish any capture |

Tools (Snapshot keys): `P` smart pen (circles/lines are recognized; a tap drops a pin) · `A` arrow ·
`R` box · `O` ellipse · `H` highlighter · `N` pin · `1–6` colors · `⌘Z` undo.

Paste into Claude Code (text with image paths), or a web chat (image files + text). Other
formats: menu bar → Recent captures. Bundles live in `~/.voice-annotate/captures/`.

## Build

Requires macOS 15+, Xcode 16+ (Swift 6 toolchain), Apple Silicon.

```bash
make install   # build release, sign with your Apple Development identity, copy to ~/Applications
make run       # install + launch
make test      # unit tests (VoiceAnnotateCore)
```

On first launch grant **Screen Recording** (then relaunch) and **Microphone**. The Whisper
model (~630 MB) downloads to `~/.voice-annotate/models` on first start.

Developer commands (run the binary directly, e.g. `.build/debug/VoiceAnnotate --help`):
`--transcribe <audio>`, `--render-demo <out.png>`, `--demo-snapshot <audio>`,
`--test-screenshot [screen]`, `--test-walkthrough <seconds> [screen|all]`.
