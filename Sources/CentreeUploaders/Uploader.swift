import CoreGraphics
import Foundation

/// Common interface for all upload destinations.
public protocol Uploader: Sendable {
    /// Uploads the given image and returns the public URL.
    func upload(_ image: CGImage) async throws -> URL
}

public enum UploadError: Error {
    case encodingFailed
    case networkError(underlying: Error)
    case serverError(statusCode: Int, body: String)
}
