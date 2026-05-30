import Foundation

public enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noMatchingContent
    case invalidFrame
    case timeout
    case streamFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission was denied. Enable it in System Settings → Privacy & Security → Screen Recording."
        case .noMatchingContent:
            return "No display or window matched the requested capture target."
        case .invalidFrame:
            return "ScreenCaptureKit delivered a frame that could not be decoded."
        case .timeout:
            return "Timed out waiting for the first frame from ScreenCaptureKit."
        case .streamFailed(let error):
            return "The capture stream stopped unexpectedly: \(error.localizedDescription)"
        }
    }
}
