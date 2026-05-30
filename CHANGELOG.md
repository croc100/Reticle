# Changelog

All notable changes to Reticle will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Initial Swift Package structure with 9 library modules
- `ReticleNaming`: filename token parser (`%year%`, `%month%`, `%day%`, `%hour%`, `%minute%`, `%second%`, `%app%`, `%counter%`, `%uuid%`, `%weekday%`)
- `ReticlePipeline`: `BeforeCaptureTask` / `AfterCaptureTask` / `OutputTask` / `AfterOutputTask` protocol definitions
- `ReticleEffects`: `MaskRenderer` scaffold with CoreImage/Metal context
- `ReticleCore`: `Screenshot`, `MaskRegion`, `MaskStyle` models
- `ReticleCapture`: `CaptureMode` enum, `Capturer` actor stub
- `ReticleOverlay`: `OverlayWindow` (AppKit) scaffold
- `ReticleUploaders`: `Uploader` protocol
- `ReticleWorkflow`: `WorkflowProfile`, `WorkflowCaptureMode`, `OutputDestination`
- `ReticleVision`: `PIIDetector` stub
- CI: GitHub Actions workflow (`build-and-test`, `lint`, `release-build`)
- SwiftLint configuration with custom `no_print_in_release` rule

---

[Unreleased]: https://github.com/reticle/reticle/compare/HEAD...HEAD
