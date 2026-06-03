<p align="center">
  <img src="Resources/logo.svg" width="128" alt="Reticle" />
</p>

<h1 align="center">Reticle</h1>

<p align="center">
  A free macOS screenshot tool — source available, free to use, built for people who take screenshots seriously.
</p>

<p align="center">
  <a href="https://github.com/croc100/Reticle/actions/workflows/ci.yml">
    <img src="https://github.com/croc100/Reticle/actions/workflows/ci.yml/badge.svg" alt="CI" />
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" />
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" />
  <img src="https://img.shields.io/badge/license-source%20available-lightgrey" />
  <img src="https://img.shields.io/github/v/release/croc100/Reticle?include_prereleases&label=release&color=yellow" />
  <a href="https://github.com/croc100/homebrew-reticle">
    <img src="https://img.shields.io/badge/homebrew-tap-orange?logo=homebrew" alt="Homebrew tap" />
  </a>
</p>

<p align="center">
  <img src="docs/assets/demo.svg" alt="Reticle in action — annotation toolbar with freeze overlay" width="100%" />
</p>

---

## What is Reticle?

Reticle is a **macOS-native screenshot tool** that brings the full power of [ShareX](https://getsharex.com/) — the gold standard on Windows — to macOS.

Most macOS screenshot tools are either too simple (built-in Screenshot.app) or too expensive (CleanShot X at $29). Reticle is **completely free to use**, with a ShareX-style annotation toolbar, workflow automation, and cloud upload built in from day one.

---

## Features

### Capture

| Feature | Status |
|---|:---:|
| Region capture (freeze + annotate) | ✅ |
| Full-screen capture | ✅ |
| Per-monitor capture | ✅ |
| Window capture (click-to-pick) | ✅ |
| Scrolling screenshot | ✅ |
| Last region repeat | ✅ |
| Saved regions | ✅ |
| Auto capture (interval timer) | ✅ |
| Capture delay (countdown) | ✅ |
| ShareX-style instant capture (drag or click) | ✅ |
| **Screen recording (MP4 / GIF)** | ✅ |

### Annotation Tools

21 tools, ShareX-style toolbar that slides in from the top of the frozen screen.  
Each tool is **sticky** — stays active until you switch to another.

| Tool | Notes |
|---|---|
| Rectangle / Ellipse | Solid / dashed / dotted stroke |
| Line / Arrow | Solid / dashed / dotted, angle-snap with Shift |
| Freehand pen | Smooth cardinal spline |
| Freehand arrow | |
| Text | Outline, background variants |
| Step numbers | Auto-increments, drag to add leader line |
| Speech balloon | Click-through text input |
| Highlight | Defaults to fluorescent yellow, adjustable opacity |
| Blur (Gaussian) | Live preview, expanded-crop for edge accuracy |
| Pixelate | Live preview |
| Blackout | |
| Spotlight | Dark overlay with circular reveal |
| Magnify / Loupe | Circular magnifier with configurable scale |
| Emoji / Sticker | |
| Mouse cursor stamp | |
| Image insert | |
| Ruler | With scale readout |
| Crop | Non-destructive selection crop |
| Eraser | Smart: trims pen strokes point-by-point |
| Select / Move | Rotate, resize, multi-select with Shift |

### After Capture

| Action | Status |
|---|:---:|
| Copy to clipboard | ✅ |
| Save to file (configurable path + filename tokens) | ✅ |
| Desktop notification with thumbnail | ✅ |
| OCR — extract text via Vision framework | ✅ |
| Pin to screen (floating image overlay) | ✅ |
| Open in viewer | ✅ |
| Reveal in Finder | ✅ |
| Copy file path | ✅ |

### Uploads

| Destination | Status |
|---|:---:|
| Imgur | ✅ |
| Amazon S3 / Backblaze B2 / Cloudflare R2 | ✅ |
| SFTP | ✅ |
| Custom HTTP uploader (JSON-defined) | ✅ |
| Google Drive / Dropbox | 🔜 |
| URL shortener | 🔜 |

### Recording

| Feature | Notes |
|---|---|
| MP4 (H.264) | Configurable FPS (default 30), 8 Mbps |
| Animated GIF | Auto-downscale to 1280 px, 30 s cap |
| Menu bar timer | Live elapsed time, stop from menu bar |
| After recording | Copy path · Notification · Reveal in Finder |

### Utilities

| Tool | Status |
|---|:---:|
| Screen color picker (loupe + HEX copy) | ✅ |
| Clipboard history (⌘⇧V, last 30 items) | ✅ |
| OCR result panel | ✅ |
| Workflow profiles (hotkey → capture mode → upload) | ✅ |
| Customizable global hotkeys | ✅ |
| Launch at login (SMAppService) | ✅ |
| SFTP / S3 Test Connection | ✅ |

---

## Why Reticle?

### vs. the competition

| | Reticle | CleanShot X | Shottr | Snagit | Flameshot |
|---|:---:|:---:|:---:|:---:|:---:|
| **Price** | **Free** | $29 one-time | Free | $62/year | Free |
| **Open source** | ✅ | ❌ | ❌ | ❌ | ✅ |
| ShareX-style annotation | ✅ | ❌ | ❌ | partial | ❌ |
| Sticky tool mode | ✅ | ❌ | ❌ | ✅ | ✅ |
| Live blur / pixelate preview | ✅ | ✅ | ✅ | ✅ | ✅ |
| Line style (solid/dashed/dotted) | ✅ | ❌ | ❌ | ✅ | ❌ |
| Scrolling screenshot | ✅ | ✅ | ❌ | ✅ | ❌ |
| Window picker (click-to-capture) | ✅ | ✅ | ✅ | ✅ | ❌ |
| Color picker | ✅ | ✅ | ✅ | ✅ | ❌ |
| Clipboard history | ✅ | ✅ | ❌ | ❌ | ❌ |
| OCR | ✅ | ✅ | ✅ | ✅ | ❌ |
| Pin to screen | ✅ | ✅ | ❌ | ❌ | ❌ |
| Cloud uploads | ✅ | ✅ | ❌ | ✅ | ❌ |
| Workflow automation | ✅ | partial | ❌ | ✅ | ❌ |
| Screen recording (MP4/GIF) | ✅ | ✅ | ❌ | ✅ | ❌ |
| Pixel-perfect capture | ✅ | ✅ | ✅ | ✅ | ✅ |
| Display P3 color space preserved | ✅ | ✅ | ❓ | ❓ | ❌ |
| **Static Mask (auto-redact regions)** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Vision PII auto-detection** | 🔜 | ❌ | ❌ | ❌ | ❌ |

### Reticle vs. ShareX

ShareX is the undisputed best screenshot tool — on Windows. Reticle aims for **feature parity on macOS**, built natively with SwiftUI + AppKit + ScreenCaptureKit rather than a port.

| | Reticle | ShareX (Windows) |
|---|:---:|:---:|
| Native macOS (SwiftUI / AppKit) | ✅ | — |
| Freeze-screen annotation overlay | ✅ | ✅ |
| Instant drag-or-click capture | ✅ | ✅ |
| Annotation toolbar (21 tools) | ✅ | ✅ |
| Workflow / after-capture pipeline | ✅ | ✅ |
| Cloud upload destinations | ✅ | ✅ |
| Screen recording (MP4 / GIF) | ✅ | ✅ |

---

## Coming Soon

- **Notarized DMG** — no more `xattr` bypass on first launch
- **QR code** — generate / scan from captured image

---

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel

## Installation

### Homebrew (recommended)

```bash
brew tap croc100/reticle
brew install --cask reticle
```

> **First launch:** Reticle is not yet notarized. Right-click → **Open**, or run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Reticle.app
> ```

### Download DMG (recommended)

Grab the latest `Reticle-x.x.x.dmg` from [Releases](https://github.com/croc100/Reticle/releases).

> **First launch (not yet notarized):** Right-click → **Open**, or run once:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Reticle.app
> ```

### Build from source

```bash
git clone https://github.com/croc100/Reticle.git
cd Reticle
swift build -c release
# Or open Package.swift in Xcode → select ReticleApp scheme → Run
```

Grant **Screen Recording** permission on first launch.  
Grant **Accessibility** permission for scroll capture and hotkey recording.

---

## Keyboard Shortcuts

### Global (works from any app)

| Key | Action |
|---|---|
| `⌘⇧2` | **Reticle Region Capture** — freeze + annotate |
| `⌘⇧3` | macOS full-screen (system default, untouched) |
| `⌘⇧4` | macOS region (system default, untouched) |

### In the annotation overlay

| Key | Action |
|---|---|
| Drag or click window | Instant capture (ShareX-style) |
| `⌘Z` | Undo last annotation |
| `Delete` / `Backspace` | Delete selected annotation |
| `Return` / `Enter` | Finalize and capture |
| `Escape` | Cancel |
| `Shift` + drag | Constrain to square / 45° angle |

---

## Architecture

```
ReticleApp          — Menu bar app, hotkey wiring, capture coordinator
├── ReticleCapture  — ScreenCaptureKit wrapper (region / window / full-screen / scroll)
├── ReticleOverlay  — Full-screen freeze overlay + annotation toolbar (SwiftUI + AppKit)
├── ReticleEffects  — CoreImage blur / pixelate / mask rendering
├── ReticlePipeline — Capture → AfterCapture → Output → AfterOutput task chain
├── ReticleRecorder — Screen recording: SCStream → MP4 (AVAssetWriter) / GIF (ImageIO)
├── ReticleNaming   — Filename token parser (%year%, %counter%, %app%, …)
├── ReticleVision   — Vision framework OCR + PII detector
├── ReticleWorkflow — Hotkey → workflow profile binding
├── ReticleUploaders— Upload adapters (Imgur, S3, custom HTTP, …)
└── ReticleCore     — Shared models, protocols, Defaults keys
```

---

## Sponsoring

Reticle is free forever. If it saves you time, consider [sponsoring](https://croc100.github.io/Reticle/sponsor/) — it helps fund the Apple Developer ID needed for notarized releases.

## Contributing

Contributions are welcome! Open an issue or PR on GitHub.

For bug reports and feature requests, use the [issue tracker](https://github.com/croc100/Reticle/issues).

## License

[Apache 2.0 + Commons Clause](LICENSE) — free to use and modify for personal and non-commercial purposes. Commercial sale or redistribution of the software requires explicit permission from the author.

© 2026 croc100
