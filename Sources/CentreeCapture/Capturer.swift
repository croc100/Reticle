import AppKit
import CoreGraphics
import CoreMedia
import ScreenCaptureKit
import CentreeCore
import Foundation

/// The primary capture actor.
///
/// Orchestrates: permission check → display/window discovery → SCStream setup
/// → single-frame extraction → cleanup → Screenshot delivery.
///
/// Requires `com.apple.security.screen-recording` entitlement.
public actor Capturer {
    private let provider: DisplayProvider

    public init() {
        provider = DisplayProvider()
    }

    // MARK: - Public API

    public func capture(mode: CaptureMode) async throws -> Screenshot {
        guard await PermissionChecker.hasPermission() else {
            throw CaptureError.permissionDenied
        }
        switch mode {
        case .region(let rect):
            return try await captureRegion(rect)
        case .window(let windowID):
            return try await captureWindow(windowID: windowID)
        case .fullScreen(let displayID):
            return try await captureFullScreen(displayID: displayID)
        }
    }

    // MARK: - Region

    private func captureRegion(_ rect: CGRect) async throws -> Screenshot {
        let display = try await provider.display(for: rect)
        let scale = display.backingScaleFactor

        // Capture the full display, then crop — this sidesteps SCK's sourceRect
        // coordinate space ambiguity. Optimise to sourceRect in a later phase.
        let fullImage = try await streamCapture(display: display)
        let cropped = try crop(image: fullImage, rect: rect, display: display, scale: scale)
        return Screenshot(image: cropped, sourceRect: rect, scaleFactor: scale)
    }

    // MARK: - Window

    private func captureWindow(windowID: CGWindowID) async throws -> Screenshot {
        let window = try await provider.window(withID: windowID)
        let scale = CGFloat(window.owningApplication.map { _ in CGMainDisplayID() }
            .flatMap { id in
                NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
                }
            }?.backingScaleFactor ?? 2.0)

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = baseConfig()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)

        let image = try await singleFrameCapture(filter: filter, config: config)
        return Screenshot(image: image, sourceRect: window.frame, scaleFactor: scale)
    }

    // MARK: - Full screen

    private func captureFullScreen(displayID: CGDirectDisplayID) async throws -> Screenshot {
        let display = try await provider.display(withID: displayID)
        let scale = display.backingScaleFactor
        let image = try await streamCapture(display: display)
        return Screenshot(image: image, sourceRect: display.frame, scaleFactor: scale)
    }

    // MARK: - SCStream helpers

    private func streamCapture(display: SCDisplay) async throws -> CGImage {
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let config = baseConfig()
        config.width = display.width
        config.height = display.height
        return try await singleFrameCapture(filter: filter, config: config)
    }

    /// Starts an `SCStream`, waits for the first complete frame (5 s timeout), stops the stream.
    private func singleFrameCapture(
        filter: SCContentFilter,
        config: SCStreamConfiguration
    ) async throws -> CGImage {
        let frameCapture = FrameCapture()
        let stream = SCStream(filter: filter, configuration: config, delegate: frameCapture)
        try stream.addStreamOutput(
            frameCapture,
            type: .screen,
            sampleHandlerQueue: .global(qos: .userInitiated)
        )
        try await stream.startCapture()

        do {
            // Race the frame against a 5-second timeout.
            let buffer = try await withTimeout(seconds: 5) {
                try await frameCapture.waitForFrame()
            }
            try await stream.stopCapture()
            return try ImageConverter.cgImage(from: buffer)
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }

    private func baseConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        return config
    }

    // MARK: - Crop

    /// Crops a full-display CGImage to the requested screen rect.
    ///
    /// Coordinate spaces:
    /// - `rect` and `display.frame` use AppKit screen coords: origin bottom-left, points.
    /// - `CGImage` origin is top-left, pixels.
    private func crop(
        image: CGImage,
        rect: CGRect,
        display: SCDisplay,
        scale: CGFloat
    ) throws -> CGImage {
        // Translate rect into display-local coordinates (still bottom-left origin).
        let localX = rect.minX - display.frame.minX
        let localY = rect.minY - display.frame.minY

        // Flip Y to match CGImage's top-left origin.
        let flippedY = display.frame.height - localY - rect.height

        let pixelRect = CGRect(
            x: localX * scale,
            y: flippedY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = image.cropping(to: pixelRect) else {
            throw CaptureError.invalidFrame
        }
        return cropped
    }
}

// MARK: - Timeout helper

/// Races `operation` against a deadline; throws `CaptureError.timeout` if the
/// deadline fires first.
///
/// `T` is intentionally unconstrained — `CMSampleBuffer` is `@_nonSendable` in the SDK
/// but safe here because we consume the buffer on the same task before it escapes.
private func withTimeout<T>(
    seconds: Double,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CaptureError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
