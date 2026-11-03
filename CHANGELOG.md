# Changelog

All notable changes to Reticle are documented here.

<!-- This file and site/src/pages/changelog.astro must list the same versions,
     and the newest one has to match CFBundleShortVersionString in
     App/Info.plist. Scripts/check_versions.py enforces both in CI. -->

---

## [Unreleased]

On `main` since 0.5.0, not yet tagged.

### Added
- Vision PII settings UI — per-pattern toggles, redaction style, and blur /
  pixelate strength sliders for automatic PII redaction
- The Homebrew cask is published from CI on every tagged release

### Fixed
- S3 uploads signed the percent-decoded object path while sending the encoded
  one, so any key prefix containing a space or another reserved character was
  rejected by AWS. Several force unwraps on values typed into Settings could
  also crash the app rather than report the mistake

### Changed
- Licence: Apache 2.0 → Apache 2.0 with the Commons Clause. The source stays
  available and free to use; selling the software is reserved to the author

### Security
- CodeQL scanning for Swift and the site runs on every pull request
- Site dependencies updated (Astro 4 → 7, Tailwind 3 → 4), clearing 58
  advisories, one of them critical

---

## [0.5.0] — 2026-06-03

### Added
- Sparkle auto-update — EdDSA-signed appcast feed, "Check for Updates…" in the
  menu bar, and a CI step that signs and publishes on every tagged release
- Static Mask — register fixed screen regions, app bundle IDs or window-title
  substrings to blur, pixelate or black out permanently on every capture
- Masks tab in Settings — per-rule enable/disable, three styles (blur /
  pixelate / solid fill) and live sliders

---

## [0.4.0] — 2026-06-03

### Added
- Launch at login — Settings → General toggle (SMAppService, macOS 13+)
- Test Connection for SFTP — verifies host, credentials and remote path with
  curl before any upload
- Test Connection for S3 — sends a signed HEAD request to the bucket to check
  credentials and connectivity

### Fixed
- SFTP: the temporary `.netrc` is created with `0o600` atomically, closing the
  brief window in which it was world-readable between write and chmod

---

## [0.3.0] — 2026-06-03

### Added
- Magnifier HUD — pixel colour swatch with live HEX (#RRGGBB) readout
- Region selector shows 8 circular handles (corners plus edge midpoints)
- Annotation handles are white circles with a blue stroke; hover adds a glow ring
- Rotation handle redrawn as a white circle with blue stroke and dashed stem
- Speech-balloon tail direction picker — four directions
- Spotlight opacity slider in the toolbar (was hard-coded at 62%)
- Line-style picker drawn as Canvas strokes — solid, dashed, dotted, replacing
  the Unicode glyphs
- Text fields use a dark frosted pill backdrop with a white border, with the
  accessibility focus ring restored
- Size label shows pixel dimensions and origin coordinates in one pill

### Changed
- Rotation handle colour: system orange → white/blue, matching the resize handles
- `drawSpotlightOverlay` honours `vm.spotlightOpacity` rather than a constant

---

## [0.2.0] — 2026-06-03

### Added
- Screen recording — MP4 (H.264, configurable FPS, 8 Mbps) and animated GIF
  (auto-downscale to 1280 px, 30 s cap, loops forever) via SCStream and
  AVAssetWriter, with a live menu-bar timer and auto-stop at the GIF frame cap
- First-launch onboarding flow
- App icon and site logo
- Available via **Homebrew**: `brew tap croc100/reticle && brew install --cask reticle`

### Fixed
- Crash in `Capturer` when the task group was exhausted — `guard let` replaces a
  force unwrap
- Crash with no attached screen — `NSScreen.screens[0]` → `.first` with a guard
- Crashes on nil URLs in `AppDelegate`, `OnboardingView` and `CaptureCoordinator`
- Data race in `ScreenRecorder` — an `NSLock` now guards every
  `nonisolated(unsafe)` encoder access
- `AVAssetWriter` crash on 1-pixel capture rects after `&~1` dimension masking
- Silent data clobber when two workflow tasks ran at once — the destination
  override is passed as a parameter instead of shared state
- Directory-creation failures were dropped silently; they are logged now
- OCR errors are shown in the result panel instead of an empty string

### Changed
- Licence: AGPL v3 → Apache 2.0

### Known limitations
- Screen recording is early — multi-monitor region recording may produce
  unexpected crops

---

## [0.1.0-alpha] — 2026-05-30

First public alpha release.

### Capture
- Region capture with freeze overlay — drag or click a window to capture instantly (ShareX-style)
- Full-screen capture (main display or per-monitor)
- Window picker — click any window to capture it
- Scrolling screenshot via Accessibility + CGEvent scroll
- Last region repeat
- User-saved named regions
- Auto capture on interval timer
- Capture delay with countdown overlay
- Default global shortcut: **⌘⇧2** (sits next to macOS built-ins ⌘⇧3/4)

### Annotation (21 tools)
Rectangle · Ellipse · Line · Arrow · Freehand pen · Freehand arrow · Text ·
Step numbers · Speech balloon · Highlight · Blur · Pixelate · Blackout ·
Spotlight · Magnify · Emoji · Cursor stamp · Image insert · Ruler · Crop · Eraser · Select/Move

All tools are **sticky** — stay active until you switch.  
Blur and Pixelate show a live preview.

### After Capture
- Copy to clipboard
- Save to file with filename token patterns (`%year%`, `%counter%`, `%app%`, …)
- Desktop notification with thumbnail
- OCR via Vision framework
- Pin to screen (floating overlay)
- Reveal in Finder · Copy file path · Open in Preview

### Upload Destinations
- Imgur (anonymous upload)
- Amazon S3 / Backblaze B2 / Cloudflare R2
- SFTP
- Custom HTTP endpoint (configurable method, field, headers, response path)

### Utilities
- Screen color picker with loupe and HEX copy
- Clipboard history (⌘⇧V, last 30 items)
- Workflow profiles — bind one hotkey to a full capture → output chain
- Customisable global hotkeys for all capture modes

### Distribution
- Ad-hoc signed DMG attached to this release
- AGPL v3 licence (Apache 2.0 from 0.2.0; Commons Clause added after 0.5.0)

### Known limitations
- App is not notarised — first launch requires right-click → Open (or `xattr -dr com.apple.quarantine /Applications/Reticle.app`)
- No auto-update yet (shipped later, in 0.5.0)
- Google Drive / Dropbox upload not yet implemented
