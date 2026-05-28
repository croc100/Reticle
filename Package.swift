// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Centree",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CentreeCore", targets: ["CentreeCore"]),
        .library(name: "CentreeCapture", targets: ["CentreeCapture"]),
        .library(name: "CentreeOverlay", targets: ["CentreeOverlay"]),
        .library(name: "CentreeEffects", targets: ["CentreeEffects"]),
        .library(name: "CentreeVision", targets: ["CentreeVision"]),
        .library(name: "CentreePipeline", targets: ["CentreePipeline"]),
        .library(name: "CentreeUploaders", targets: ["CentreeUploaders"]),
        .library(name: "CentreeWorkflow", targets: ["CentreeWorkflow"]),
        .library(name: "CentreeNaming", targets: ["CentreeNaming"]),
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
            name: "CentreeApp",
            dependencies: [
                "CentreeCore",
                "CentreeCapture",
                "CentreeOverlay",
                "CentreeEffects",
                "CentreePipeline",
                "CentreeVision",
                "CentreeWorkflow",
                "CentreeNaming",
                "CentreeUploaders",
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "App",
            exclude: ["Centree.entitlements", "Info.plist"]
        ),

        // MARK: - Library Targets

        // Shared models, protocols, and constants consumed by all other modules.
        .target(
            name: "CentreeCore",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "Sources/CentreeCore"
        ),

        // ScreenCaptureKit wrapper: area / window / full-screen capture → CGImage.
        .target(
            name: "CentreeCapture",
            dependencies: ["CentreeCore"],
            path: "Sources/CentreeCapture"
        ),

        // Full-screen overlay window: region selector, live mask boxes, drawing canvas.
        // Uses AppKit NSWindow directly for precise hit-testing and transparency control.
        .target(
            name: "CentreeOverlay",
            dependencies: ["CentreeCore", "CentreeCapture"],
            path: "Sources/CentreeOverlay"
        ),

        // CoreImage-based effects: Gaussian blur, pixelate, solid fill, shape compositing.
        .target(
            name: "CentreeEffects",
            dependencies: ["CentreeCore"],
            path: "Sources/CentreeEffects"
        ),

        // Vision framework PII detector: text OCR + regex matching for emails,
        // phone numbers, API keys, JWTs, AWS keys, etc.
        .target(
            name: "CentreeVision",
            dependencies: ["CentreeCore"],
            path: "Sources/CentreeVision"
        ),

        // ShareX-style task pipeline: Capture → AfterCapture → Output → AfterOutput.
        // Depends on CentreeNaming so built-in output tasks can resolve filename tokens.
        .target(
            name: "CentreePipeline",
            dependencies: [
                "CentreeCore",
                "CentreeCapture",
                "CentreeEffects",
                "CentreeNaming",
            ],
            path: "Sources/CentreePipeline"
        ),

        // Upload adapters: Imgur, S3, custom SFTP — all behind a common Uploader protocol.
        .target(
            name: "CentreeUploaders",
            dependencies: ["CentreeCore"],
            path: "Sources/CentreeUploaders"
        ),

        // Workflow profile system: one hotkey = one workflow config.
        .target(
            name: "CentreeWorkflow",
            dependencies: [
                "CentreeCore",
                "CentreePipeline",
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources/CentreeWorkflow"
        ),

        // Filename token parser: %year%-%month%-%day%_%app%_%counter%.png
        .target(
            name: "CentreeNaming",
            dependencies: ["CentreeCore"],
            path: "Sources/CentreeNaming"
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "CentreeCoreTests",
            dependencies: ["CentreeCore"],
            path: "Tests/CentreeCoreTests"
        ),
        .testTarget(
            name: "CentreePipelineTests",
            dependencies: ["CentreePipeline"],
            path: "Tests/CentreePipelineTests"
        ),
        .testTarget(
            name: "CentreeNamingTests",
            dependencies: ["CentreeNaming"],
            path: "Tests/CentreeNamingTests"
        ),
        .testTarget(
            name: "CentreeEffectsTests",
            dependencies: ["CentreeEffects"],
            path: "Tests/CentreeEffectsTests"
        ),
        // CentreeCapture unit tests — SCK-dependent tests must run in Xcode (need entitlement).
        // This target only tests types that don't invoke SCStream.
        .testTarget(
            name: "CentreeCaptureTests",
            dependencies: ["CentreeCapture"],
            path: "Tests/CentreeCaptureTests"
        ),
    ]
)
