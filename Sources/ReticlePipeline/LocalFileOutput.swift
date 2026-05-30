import CoreGraphics
import ReticleCore
import ReticleNaming
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves the captured screenshot to a local directory.
///
/// Supported formats: PNG (lossless), JPEG, TIFF, WebP.
/// Files are organised into daily sub-folders: `<directory>/YYYY-MM-DD/<filename>`.
/// After saving, the output URL is appended to `context.outputURLs`.
public struct LocalFileOutput: OutputTask {
    public let directory: URL
    public let nameParser: NameParser
    /// One of "png", "jpeg", "tiff", "webp". Defaults to PNG.
    public let format: String
    /// JPEG compression quality 0.0–1.0 (only used when format = "jpeg").
    public let jpegQuality: Double

    public init(directory: URL,
                nameParser: NameParser = NameParser(),
                format: String = "png",
                jpegQuality: Double = 0.9) {
        self.directory = directory
        self.nameParser = nameParser
        self.format = format
        self.jpegQuality = jpegQuality
    }

    public func execute(screenshot: Screenshot, context: inout CaptureContext) async throws {
        let dateFolderURL = dailyFolder(for: screenshot.capturedAt)
        try FileManager.default.createDirectory(at: dateFolderURL, withIntermediateDirectories: true)

        // Resolve filename: strip any existing extension then add the correct one.
        var filename = nameParser.resolve(date: screenshot.capturedAt)
        filename = (filename as NSString).deletingPathExtension + "." + fileExtension
        let outputURL = dateFolderURL.appendingPathComponent(filename)

        try write(screenshot.image, to: outputURL, scaleFactor: screenshot.scaleFactor)
        context.outputURLs.append(outputURL)
    }

    // MARK: - Private

    private var fileExtension: String {
        switch format.lowercased() {
        case "jpeg", "jpg": return "jpg"
        case "tiff", "tif": return "tiff"
        case "webp":        return "webp"
        default:            return "png"
        }
    }

    private var utType: UTType {
        switch format.lowercased() {
        case "jpeg", "jpg": return .jpeg
        case "tiff", "tif": return .tiff
        case "webp":        return UTType(filenameExtension: "webp") ?? .png
        default:            return .png
        }
    }

    private func dailyFolder(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent(formatter.string(from: date))
    }

    private func write(_ image: CGImage, to url: URL, scaleFactor: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, utType.identifier as CFString, 1, nil
        ) else { throw LocalFileOutputError.destinationCreationFailed(url) }

        let dpi = scaleFactor * 72.0
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth:  dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        // Apply JPEG quality when relevant.
        if utType == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw LocalFileOutputError.writeFailed(url)
        }
    }
}

public enum LocalFileOutputError: Error, LocalizedError {
    case destinationCreationFailed(URL)
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .destinationCreationFailed(let url): return "Could not create image destination at \(url.path)."
        case .writeFailed(let url):               return "Failed to write image to \(url.path)."
        }
    }
}
