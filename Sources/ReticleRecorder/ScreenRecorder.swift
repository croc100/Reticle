import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AVFoundation
import Foundation

// MARK: - ScreenRecorder

/// Records a region of the screen (or the full display) to MP4 or GIF.
///
/// Lifecycle:
/// ```
/// let recorder = ScreenRecorder()
/// try await recorder.start(config:)
/// // … user clicks "Stop" …
/// let url = try await recorder.stop()
/// ```
@MainActor
public final class ScreenRecorder: NSObject {

    // MARK: - Public state

    public private(set) var state: RecordingState = .idle
    /// Elapsed recording time, updated every second on the main actor.
    public private(set) var elapsedSeconds: Int = 0

    // MARK: - Private (main-actor isolated)

    private var stream: SCStream?
    private var config: RecordingConfig?
    private var timer: Task<Void, Never>?
    private let callbackQueue = DispatchQueue(label: "com.reticle.recorder", qos: .userInitiated)

    // Encoders are accessed from the SCStream callback (nonisolated) and from
    // main-actor methods. All access is serialized via encoderLock.
    nonisolated private let encoderLock = NSLock()
    nonisolated(unsafe) private var mp4Encoder: MP4Encoder?
    nonisolated(unsafe) private var gifEncoder: GIFEncoder?

    // MARK: - Start

    /// Begins recording with the provided configuration.
    public func start(config: RecordingConfig) async throws {
        guard case .idle = state else { return }
        self.config = config
        state = .recording
        elapsedSeconds = 0

        // Build SCStream filter — capture the main display (or the display
        // containing the specified rect, if any).
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            state = .idle
            throw RecordingError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let streamConfig = SCStreamConfiguration()
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.showsCursor = true
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        // Crop to the requested rect if provided.
        // `config.captureRect` is in global screen coordinates; SCStreamConfiguration
        // expects `sourceRect` in display-local points (origin at the display's top-left).
        if let rect = config.captureRect {
            let scale = display.frame.width > 0
                ? CGFloat(display.width) / display.frame.width
                : 1.0
            // Translate global → display-local (handles multi-monitor layouts)
            let localRect = CGRect(
                x: rect.minX - display.frame.minX,
                y: rect.minY - display.frame.minY,
                width: rect.width,
                height: rect.height
            )
            streamConfig.sourceRect = localRect
            streamConfig.width  = Int(localRect.width  * scale)
            streamConfig.height = Int(localRect.height * scale)
        } else {
            streamConfig.width  = display.width
            streamConfig.height = display.height
        }

        // Make sure dimensions are even (H.264 requirement)
        streamConfig.width  = streamConfig.width  & ~1
        streamConfig.height = streamConfig.height & ~1

        // Guard against zero-sized rects after alignment (e.g. 1×1 input → 0×0 after masking)
        guard streamConfig.width > 0, streamConfig.height > 0 else {
            state = .idle
            throw RecordingError.encoderFailure("Capture rect is too small — minimum 2×2 pixels after alignment.")
        }

        let frameSize = CGSize(width: streamConfig.width, height: streamConfig.height)

        // Set up encoder for chosen format (create first, then assign under lock)
        switch config.format {
        case .mp4:
            let encoder = try MP4Encoder(outputURL: config.outputURL, size: frameSize, fps: config.fps)
            encoderLock.withLock { mp4Encoder = encoder }
        case .gif:
            let encoder = GIFEncoder(outputURL: config.outputURL, fps: config.fps)
            encoderLock.withLock { gifEncoder = encoder }
        }

        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: callbackQueue)
        try await scStream.startCapture()
        stream = scStream

        // Elapsed-time ticker
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self?.elapsedSeconds += 1 }
            }
        }
    }

    // MARK: - Stop

    /// Stops recording and encodes the output file.
    /// - Returns: The URL of the finished file.
    @discardableResult
    public func stop() async throws -> URL {
        guard case .recording = state else {
            throw RecordingError.encoderFailure("stop() called while not recording.")
        }
        state = .encoding
        timer?.cancel()
        timer = nil

        // Stop SCStream
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }

        // Encode output (copy references under lock, then finalize outside the lock)
        let mp4 = encoderLock.withLock { mp4Encoder }
        let gif  = encoderLock.withLock { gifEncoder }
        encoderLock.withLock { mp4Encoder = nil; gifEncoder = nil }

        let url: URL
        do {
            if let encoder = mp4 {
                url = try await encoder.finish()
            } else if let encoder = gif {
                url = try encoder.finish()
            } else {
                throw RecordingError.encoderFailure("No encoder active.")
            }
        } catch {
            state = .failed(error)
            throw error
        }

        state = .done(url)
        return url
    }

    // MARK: - Cancel

    public func cancel() {
        timer?.cancel()
        timer = nil
        Task {
            try? await stream?.stopCapture()
            self.stream = nil
            self.encoderLock.withLock {
                self.mp4Encoder = nil
                self.gifEncoder = nil
            }
            self.state = .idle
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        // Copy references under lock, then use outside the lock
        let mp4 = encoderLock.withLock { mp4Encoder }
        let gif  = encoderLock.withLock { gifEncoder }

        if let encoder = mp4 {
            encoder.append(sampleBuffer)
        } else if let encoder = gif {
            // Extract CGImage from pixel buffer for GIF
            guard
                let pixelBuffer = sampleBuffer.imageBuffer,
                let image = cgImage(from: pixelBuffer)
            else { return }
            do {
                try encoder.append(image)
            } catch {
                // Frame limit exceeded — auto-stop on the main actor so the
                // UI updates cleanly (same path as a user pressing Stop).
                Task { @MainActor [weak self] in
                    guard let self, case .recording = self.state else { return }
                    _ = try? await self.stop()
                }
            }
        }
    }

    /// Convert a `CVPixelBuffer` (BGRA) to a `CGImage`.
    nonisolated private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: base,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        return ctx.makeImage()
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, case .recording = self.state else { return }
            self.state = .failed(error)
            self.timer?.cancel()
        }
    }
}
