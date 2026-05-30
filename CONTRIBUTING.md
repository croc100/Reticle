# Contributing to Reticle

Thank you for considering a contribution! This guide covers everything you need to go from zero to an open pull request.

---

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Project Structure](#project-structure)
3. [Building & Running](#building--running)
4. [Running Tests](#running-tests)
5. [Code Style](#code-style)
6. [Xcode Project Setup (first time)](#xcode-project-setup-first-time)
7. [Submitting a Pull Request](#submitting-a-pull-request)
8. [Commit Message Format](#commit-message-format)

---

## Development Environment Setup

**Required:**

| Tool | Version | Install |
|---|---|---|
| Xcode | 15.4+ | Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/) |
| Swift | 5.9+ | Bundled with Xcode |
| SwiftLint | latest | `brew install swiftlint` |
| swift-format | latest | `brew install swift-format` |

**Optional but recommended:**

```bash
brew install xcpretty   # Nicer xcodebuild output
```

---

## Project Structure

```
Reticle/
├── Reticle.xcodeproj/       # Xcode project (app target, entitlements, assets)
├── App/                     # App target sources (AppDelegate, SwiftUI App, settings UI)
├── Sources/
│   ├── ReticleCore/         # Shared models & protocols
│   ├── ReticleCapture/      # ScreenCaptureKit wrapper
│   ├── ReticleOverlay/      # Full-screen overlay window
│   ├── ReticleEffects/      # CoreImage mask/blur rendering
│   ├── ReticleVision/       # Vision PII detector
│   ├── ReticlePipeline/     # Task pipeline engine
│   ├── ReticleUploaders/    # Upload adapters
│   ├── ReticleWorkflow/     # Hotkey workflow profiles
│   └── ReticleNaming/       # Filename token parser
├── Tests/                   # XCTest targets (one per library module)
├── Package.swift            # Swift Package (library modules + tests)
└── .github/                 # CI workflows, issue templates
```

The `Package.swift` defines all library modules. The Xcode project (app target) adds
`Package.swift` as a local package dependency and handles entitlements, assets, and signing.

---

## Building & Running

### Library modules only (no Xcode project needed)

```bash
swift build
```

### Full app (requires Xcode project)

```bash
open Reticle.xcodeproj
# Then ⌘R in Xcode
```

Or from the command line:

```bash
xcodebuild -project Reticle.xcodeproj -scheme Reticle -configuration Debug build | xcpretty
```

---

## Running Tests

```bash
# All library tests in parallel:
swift test --parallel

# Specific target:
swift test --filter ReticleNamingTests
```

Tests that touch ScreenCaptureKit (`ReticleCaptureTests`) require Screen Recording permission
and must be run from Xcode, not `swift test`.

---

## Code Style

- **Formatter**: `swift-format` — run `swift-format format -i -r Sources Tests` before committing.
- **Linter**: SwiftLint — `swiftlint --strict`. See `.swiftlint.yml` for rules.
- **Async**: `async/await` throughout — no callbacks or `DispatchQueue` in new code.
- **Error handling**: `throws` at call sites; `Result` only at async external boundaries.
- **Comments**: Write comments only when the *why* is non-obvious. No docstrings on private symbols.
- **Public API**: DocC format (`/// …`) on all `public` declarations.

---

## Xcode Project Setup (first time)

These steps assume you have cloned the repo and want to set up the Xcode project for the app target.

### Step 1 — Create the Xcode project

1. Open Xcode → **File > New > Project…**
2. Choose **macOS → App**, click **Next**
3. Fill in:
   - **Product Name**: `Reticle`
   - **Organization Identifier**: `io.reticle` (or your own reverse-DNS)
   - **Bundle Identifier**: `io.reticle.Reticle`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - Uncheck **Include Tests** (tests live in `Package.swift`)
4. Save location: the **root of this repo** (next to `Package.swift`)
5. When asked about source control: choose **Don't add to source control** (git is already initialized)

### Step 2 — Delete the generated app group folder

Xcode creates a `Reticle/` subfolder with a generated `ContentView.swift` etc.  
Delete it — the real app sources live in `App/`.

### Step 3 — Add the local Swift package

1. In Xcode, **File > Add Package Dependencies…**
2. Click **Add Local…** and select the repo root (the folder containing `Package.swift`)
3. Xcode will resolve all modules. Add the ones the app target needs:
   `ReticleCore`, `ReticleCapture`, `ReticleOverlay`, `ReticleEffects`,
   `ReticlePipeline`, `ReticleWorkflow`, `ReticleNaming`

### Step 4 — Add source files

Drag the contents of `App/` into the Reticle Xcode target (check **"Add to target: Reticle"**).

### Step 5 — Set the deployment target

Target → **General → Minimum Deployments**: `macOS 13.0`

### Step 6 — Add entitlements

Create `App/Reticle.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for ScreenCaptureKit -->
    <key>com.apple.security.screen-recording</key>
    <true/>
    <!-- Required to write files outside the sandbox -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

In Target → **Signing & Capabilities**, set **Code Signing Entitlements** to this file.

### Step 7 — Disable sandbox (required for global hotkeys)

Add the **App Sandbox** capability and then **remove** it (or leave it off from the start).  
Global hotkeys via HotKey require `com.apple.security.temporary-exception.apple-events` or no sandbox.

> **Note**: Because Reticle is distributed outside the Mac App Store, we don't need sandbox.

---

## Submitting a Pull Request

1. Fork the repo and create a feature branch: `git checkout -b feat/my-feature`
2. Make your changes, add/update tests
3. Run `swift-format format -i -r Sources Tests && swiftlint --strict`
4. Push and open a PR against `main`
5. Fill in the PR template

For significant new features, open a GitHub Discussion or issue first to align on design before writing code.

---

## Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]
[optional footer]
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`  
**Scope** (optional): module name — `capture`, `overlay`, `effects`, `pipeline`, `naming`, …

**Examples:**

```
feat(naming): add %uuid% token support
fix(effects): clamp blur radius to avoid CIFilter crash on zero input
refactor(pipeline): extract CaptureContext into its own file
docs: add Xcode setup steps to CONTRIBUTING
```
