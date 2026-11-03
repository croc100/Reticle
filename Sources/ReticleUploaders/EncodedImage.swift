import CoreGraphics
import Foundation
import ImageIO

/// A screenshot already encoded to bytes, ready to be sent anywhere.
///
/// Encoding is the expensive half of an upload — a full-screen Retina capture is
/// tens of megapixels — and the result does not depend on the destination.
/// Passing the bytes around lets one capture fan out to several destinations for
/// a single encode, instead of each uploader encoding the same frame again.
public struct EncodedImage: Sendable {
    public let data: Data
    /// MIME type for the `Content-Type` header.
    public let contentType: String
    /// Extension for the uploaded filename, without the leading dot.
    public let fileExtension: String

    public init(data: Data, contentType: String, fileExtension: String) {
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
    }

    /// Encodes `image` as PNG through `CGImageDestination`.
    ///
    /// Deliberately not the `NSImage` → `tiffRepresentation` →
    /// `NSBitmapImageRep` route: that materialises the whole frame as
    /// uncompressed TIFF first, which for a 6K capture is a ~80 MB allocation
    /// before the PNG encoder has started.
    public static func png(from image: CGImage) throws -> EncodedImage {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, "public.png" as CFString, 1, nil
        ) else {
            throw UploadError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UploadError.encodingFailed
        }
        return EncodedImage(data: buffer as Data, contentType: "image/png", fileExtension: "png")
    }
}
