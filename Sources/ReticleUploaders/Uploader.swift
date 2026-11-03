import CoreGraphics
import Foundation

/// Common interface for all upload destinations.
public protocol Uploader: Sendable {
    /// Uploads an already-encoded image and returns the public URL.
    ///
    /// Destinations take bytes rather than a `CGImage` so that a capture bound
    /// for several of them is encoded once — see ``EncodedImage``.
    func upload(_ image: EncodedImage) async throws -> URL
}

public extension Uploader {
    /// Encodes `image` as PNG and uploads it.
    ///
    /// Convenience for a single destination. A caller sending one capture to
    /// several destinations should encode once with ``EncodedImage/png(from:)``
    /// and hand the result to each, rather than calling this per destination.
    func upload(_ image: CGImage) async throws -> URL {
        let encoded = try EncodedImage.png(from: image)
        return try await upload(encoded)
    }
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
