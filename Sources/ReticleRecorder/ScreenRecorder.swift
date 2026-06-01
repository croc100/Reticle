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
    // main-actor methods. We guard all access ourselves, so nonisolated(unsafe) is safe.
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

        // Crop to the requested rect if provided
        if let rect = config.captureRect {
            let scale = display.frame.width > 0
                ? CGFloat(display.width) / display.frame.width
                : 1.0
            streamConfig.sourceRect = rect
            streamConfig.width  = Int(rect.width  * scale)
            streamConfig.height = Int(rect.height * scale)
        } else {
            streamConfig.width  = display.width
            streamConfig.height = display.height
        }

        // Make sure dimensions are even (H.264 requirement)
        streamConfig.width  = streamConfig.width  & ~1
        streamConfig.height = streamConfig.height & ~1

        let frameSize = CGSize(width: streamConfig.width, height: streamConfig.height)

        // Set up encoder for chosen format
        switch config.format {
        case .mp4:
            mp4Encoder = try MP4Encoder(outputURL: config.outputURL, size: frameSize, fps: config.fps)
        case .gif:
            gifEncoder = GIFEncoder(outputURL: config.outputURL, fps: config.fps)
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

        // Encode output
        let url: URL
        do {
            if let encoder = mp4Encoder {
                url = try await encoder.finish()
                mp4Encoder = nil
            } else if let encoder = gifEncoder {
                url = try encoder.finish()
                gifEncoder = nil
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
            self.mp4Encoder = nil
            self.gifEncoder = nil
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

        // Route to the correct encoder
        if let encoder = mp4Encoder {
            encoder.append(sampleBuffer)
        } else if let encoder = gifEncoder {
            // Extract CGImage from pixel buffer for GIF
            guard
                let pixelBuffer = sampleBuffer.imageBuffer,
                let image = cgImage(from: pixelBuffer)
            else { return }
            try? encoder.append(image)
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
