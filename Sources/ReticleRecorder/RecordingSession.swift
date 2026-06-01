import Foundation
import CoreGraphics
import AVFoundation

// MARK: - Configuration

/// User-facing recording configuration.
public struct RecordingConfig: Sendable {
    /// Target area in screen coordinates. Nil = full main display.
    public var captureRect: CGRect?
    /// Frames per second. 30 is a good default for screen content.
    public var fps: Int
    /// Output format selection.
    public var format: RecordingFormat
    /// Where to save the output file.
    public var outputURL: URL

    public init(
        captureRect: CGRect? = nil,
        fps: Int = 30,
        format: RecordingFormat = .mp4,
        outputURL: URL
    ) {
        self.captureRect = captureRect
        self.fps = fps
        self.format = format
        self.outputURL = outputURL
    }
}

public enum RecordingFormat: String, Sendable, CaseIterable {
    case mp4
    case gif

    public var fileExtension: String { rawValue }
    public var displayName: String {
        switch self {
        case .mp4: return "MP4 (H.264)"
        case .gif: return "GIF (animated)"
        }
    }
}

// MARK: - Session state

public enum RecordingState: Sendable {
    case idle
    case recording
    case encoding
    case done(URL)
    case failed(any Error)
}

// MARK: - Error types

public enum RecordingError: LocalizedError {
    case permissionDenied
    case noDisplay
    case encoderFailure(String)
    case gifFrameLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required. Grant it in System Settings → Privacy & Security → Screen Recording."
        case .noDisplay:
            return "No display found to record."
        case .encoderFailure(let msg):
            return "Encoder error: \(msg)"
        case .gifFrameLimitExceeded:
            return "GIF recording exceeds the maximum allowed duration (30 s). Stop the recording sooner."
        }
    }
}
