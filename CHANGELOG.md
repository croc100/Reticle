# Changelog

All notable changes to Centree will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Initial Swift Package structure with 9 library modules
- `CentreeNaming`: filename token parser (`%year%`, `%month%`, `%day%`, `%hour%`, `%minute%`, `%second%`, `%app%`, `%counter%`, `%uuid%`, `%weekday%`)
- `CentreePipeline`: `BeforeCaptureTask` / `AfterCaptureTask` / `OutputTask` / `AfterOutputTask` protocol definitions
- `CentreeEffects`: `MaskRenderer` scaffold with CoreImage/Metal context
- `CentreeCore`: `Screenshot`, `MaskRegion`, `MaskStyle` models
- `CentreeCapture`: `CaptureMode` enum, `Capturer` actor stub
- `CentreeOverlay`: `OverlayWindow` (AppKit) scaffold
- `CentreeUploaders`: `Uploader` protocol
- `CentreeWorkflow`: `WorkflowProfile`, `WorkflowCaptureMode`, `OutputDestination`
- `CentreeVision`: `PIIDetector` stub
- CI: GitHub Actions workflow (`build-and-test`, `lint`, `release-build`)
- SwiftLint configuration with custom `no_print_in_release` rule

---

[Unreleased]: https://github.com/centree/centree/compare/HEAD...HEAD
