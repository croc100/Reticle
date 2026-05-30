// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reticle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ReticleCore", targets: ["ReticleCore"]),
        .library(name: "ReticleCapture", targets: ["ReticleCapture"]),
        .library(name: "ReticleOverlay", targets: ["ReticleOverlay"]),
        .library(name: "ReticleEffects", targets: ["ReticleEffects"]),
        .library(name: "ReticleVision", targets: ["ReticleVision"]),
        .library(name: "ReticlePipeline", targets: ["ReticlePipeline"]),
        .library(name: "ReticleUploaders", targets: ["ReticleUploaders"]),
        .library(name: "ReticleWorkflow", targets: ["ReticleWorkflow"]),
        .library(name: "ReticleNaming", targets: ["ReticleNaming"]),
    ],
    dependencies: [
        // Global hotkey registration — simplest API for Carbon-based hotkeys on macOS
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        // Type-safe UserDefaults wrapper with observation support
        .package(url: "https://github.com/sindresorhus/Defaults", from: "7.0.0"),
        // macOS auto-update standard — appcast XML, delta updates, UI built-in
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        // MARK: - App Executable

        // macOS menu bar app target. Opened directly in Xcode via Package.swift —
        // no separate .xcodeproj needed. Entitlements are set in the Xcode scheme.
        .executableTarget(
            name: "ReticleApp",
            dependencies: [
                "ReticleCore",
                "ReticleCapture",
                "ReticleOverlay",
                "ReticleEffects",
                "ReticlePipeline",
                "ReticleVision",
                "ReticleWorkflow",
                "ReticleNaming",
                "ReticleUploaders",
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "App",
            exclude: ["Reticle.entitlements", "Info.plist"]
        ),

        // MARK: - Library Targets

        // Shared models, protocols, and constants consumed by all other modules.
        .target(
            name: "ReticleCore",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "Sources/ReticleCore"
        ),

        // ScreenCaptureKit wrapper: area / window / full-screen capture → CGImage.
        .target(
            name: "ReticleCapture",
            dependencies: ["ReticleCore"],
            path: "Sources/ReticleCapture"
        ),

        // Full-screen overlay window: region selector, live mask boxes, drawing canvas.
        // Uses AppKit NSWindow directly for precise hit-testing and transparency control.
        .target(
            name: "ReticleOverlay",
            dependencies: ["ReticleCore", "ReticleCapture"],
            path: "Sources/ReticleOverlay"
        ),

        // CoreImage-based effects: Gaussian blur, pixelate, solid fill, shape compositing.
        .target(
            name: "ReticleEffects",
            dependencies: ["ReticleCore"],
            path: "Sources/ReticleEffects"
        ),

        // Vision framework PII detector: text OCR + regex matching for emails,
        // phone numbers, API keys, JWTs, AWS keys, etc.
        .target(
            name: "ReticleVision",
            dependencies: ["ReticleCore"],
            path: "Sources/ReticleVision"
        ),

        // ShareX-style task pipeline: Capture → AfterCapture → Output → AfterOutput.
        // Depends on ReticleNaming so built-in output tasks can resolve filename tokens.
        .target(
            name: "ReticlePipeline",
            dependencies: [
                "ReticleCore",
                "ReticleCapture",
                "ReticleEffects",
                "ReticleNaming",
            ],
            path: "Sources/ReticlePipeline"
        ),

        // Upload adapters: Imgur, S3, custom SFTP — all behind a common Uploader protocol.
        .target(
            name: "ReticleUploaders",
            dependencies: ["ReticleCore"],
            path: "Sources/ReticleUploaders"
        ),

        // Workflow profile system: one hotkey = one workflow config.
        .target(
            name: "ReticleWorkflow",
            dependencies: [
                "ReticleCore",
                "ReticlePipeline",
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources/ReticleWorkflow"
        ),

        // Filename token parser: %year%-%month%-%day%_%app%_%counter%.png
        .target(
            name: "ReticleNaming",
            dependencies: ["ReticleCore"],
            path: "Sources/ReticleNaming"
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "ReticleCoreTests",
            dependencies: ["ReticleCore"],
            path: "Tests/ReticleCoreTests"
        ),
        .testTarget(
            name: "ReticlePipelineTests",
            dependencies: ["ReticlePipeline"],
            path: "Tests/ReticlePipelineTests"
        ),
        .testTarget(
            name: "ReticleNamingTests",
            dependencies: ["ReticleNaming"],
            path: "Tests/ReticleNamingTests"
        ),
        .testTarget(
            name: "ReticleEffectsTests",
            dependencies: ["ReticleEffects"],
            path: "Tests/ReticleEffectsTests"
        ),
        // ReticleCapture unit tests — SCK-dependent tests must run in Xcode (need entitlement).
        // This target only tests types that don't invoke SCStream.
        .testTarget(
            name: "ReticleCaptureTests",
            dependencies: ["ReticleCapture"],
            path: "Tests/ReticleCaptureTests"
        ),
    ]
)
