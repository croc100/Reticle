import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation

/// Writes a sequence of `CMSampleBuffer` video frames to an H.264 MP4 file.
///
/// Usage:
/// ```swift
/// let encoder = try MP4Encoder(outputURL: url, size: size, fps: 30)
/// encoder.append(sampleBuffer)   // call from SCStreamOutput callback
/// try await encoder.finish()
/// ```
final class MP4Encoder {

    // MARK: - Private

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private var hasStarted = false

    // MARK: - Init

    /// - Parameters:
    ///   - outputURL: Destination `.mp4` file. Must not already exist.
    ///   - size: Frame dimensions in pixels.
    ///   - fps: Target frame rate (used for time-scale only; actual timing comes from sample buffers).
    init(outputURL: URL, size: CGSize, fps: Int) throws {
        // Remove stale file if present (previous aborted recording)
        try? FileManager.default.removeItem(at: outputURL)

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let settings: [String: Any] = [
            AVVideoCodecKey:                AVVideoCodecType.h264,
            AVVideoWidthKey:                Int(size.width),
            AVVideoHeightKey:               Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:   8_000_000,   // 8 Mbps — good for 1080p screen content
                AVVideoProfileLevelKey:     AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps,      // keyframe once per second
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
    }

    // MARK: - Append

    /// Feed a raw video sample buffer from `SCStreamOutput`.
    /// Thread-safe — can be called from the SCStream callback queue.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard videoInput.isReadyForMoreMediaData else { return }

        if !hasStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            hasStarted = true
        }
        videoInput.append(sampleBuffer)
    }

    // MARK: - Finish

    /// Finalizes the file. Call once on stop. Returns the output URL.
    func finish() async throws -> URL {
        guard hasStarted else {
            throw RecordingError.encoderFailure("No frames were written.")
        }
        videoInput.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw RecordingError.encoderFailure(error.localizedDescription)
        }
        return writer.outputURL
    }
}
