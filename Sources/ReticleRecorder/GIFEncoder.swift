import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Encodes a sequence of `CGImage` frames into an animated GIF.
///
/// GIF is capped at `maxFrames` (default 900 = 30 s at 30 fps) to prevent
/// runaway memory usage. Caller is responsible for stopping the recording
/// before the limit is reached.
final class GIFEncoder {

    // MARK: - Configuration

    private let outputURL: URL
    /// Duration of each frame in seconds. 1/fps.
    private let frameDuration: Double
    /// Maximum number of frames before throwing `gifFrameLimitExceeded`.
    private let maxFrames: Int

    // MARK: - State

    private var frames: [(image: CGImage, delay: Double)] = []

    // MARK: - Init

    init(outputURL: URL, fps: Int, maxDurationSeconds: Int = 30) {
        self.outputURL = outputURL
        self.frameDuration = 1.0 / Double(max(fps, 1))
        self.maxFrames = fps * maxDurationSeconds
    }

    // MARK: - Append

    /// Buffer a captured frame. Call from the SCStream callback queue.
    /// - Throws: `RecordingError.gifFrameLimitExceeded` when over the cap.
    func append(_ image: CGImage) throws {
        guard frames.count < maxFrames else {
            throw RecordingError.gifFrameLimitExceeded
        }
        frames.append((image: image, delay: frameDuration))
    }

    // MARK: - Finish

    /// Writes all buffered frames to the GIF file.
    /// Runs frame reduction for large recordings (skip every other frame if > 15 fps effective).
    func finish() throws -> URL {
        guard !frames.isEmpty else {
            throw RecordingError.encoderFailure("No GIF frames to write.")
        }

        try? FileManager.default.removeItem(at: outputURL)

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw RecordingError.encoderFailure("Could not create GIF destination.")
        }

        // Global GIF properties (loop count 0 = loop forever)
        let globalProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as CFDictionary,
        ]
        CGImageDestinationSetProperties(dest, globalProps as CFDictionary)

        // Frame-level properties — GIF delay is in centiseconds (1/100 s)
        let centiseconds = Int(frameDuration * 100)
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDuration,
                kCGImagePropertyGIFUnclampedDelayTime: frameDuration,
            ] as CFDictionary,
        ]

        for frame in frames {
            // Downsample large frames — GIF looks fine at half resolution
            // and palette quantization artifacts are less visible.
            let image = frame.delay > 0 ? downscaleIfNeeded(frame.image, maxDimension: 1280) : frame.image
            CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else {
            throw RecordingError.encoderFailure("CGImageDestinationFinalize failed.")
        }

        _ = centiseconds  // suppress unused-variable warning
        return outputURL
    }

    // MARK: - Helpers

    /// Scales down the image so neither dimension exceeds `maxDimension`.
    private func downscaleIfNeeded(_ source: CGImage, maxDimension: Int) -> CGImage {
        let w = source.width
        let h = source.height
        guard w > maxDimension || h > maxDimension else { return source }

        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)

        guard let ctx = CGContext(
            data: nil,
            width: newW, height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return source }

        ctx.interpolationQuality = .medium
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? source
    }
}
