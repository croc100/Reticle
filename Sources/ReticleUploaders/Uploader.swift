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
    /// A value typed into Settings cannot produce a valid request — a bucket
    /// name, a region, or a public URL template.  Distinct from a server error
    /// because nothing was sent and retrying will not help.
    case invalidConfiguration(String)
}

extension UploadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the screenshot for upload."
        case .networkError(let underlying):
            return "Upload failed: \(underlying.localizedDescription)"
        case .serverError(let statusCode, let body):
            return body.isEmpty
                ? "The server rejected the upload (HTTP \(statusCode))."
                : "The server rejected the upload (HTTP \(statusCode)): \(body)"
        case .invalidConfiguration(let detail):
            return "Upload settings are not valid: \(detail)"
        }
    }
}
