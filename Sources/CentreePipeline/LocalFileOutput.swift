import CoreGraphics
import CentreeCore
import CentreeNaming
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves the captured screenshot to a local directory as a PNG file.
///
/// Files are organised into daily sub-folders: `<directory>/YYYY-MM-DD/<filename>.png`
/// After saving, the output URL is appended to `context.outputURLs`.
public struct LocalFileOutput: OutputTask {
    public let directory: URL
    public let nameParser: NameParser

    public init(directory: URL, nameParser: NameParser = NameParser()) {
        self.directory = directory
        self.nameParser = nameParser
    }

    public func execute(screenshot: Screenshot, context: inout CaptureContext) async throws {
        let dateFolderURL = dailyFolder(for: screenshot.capturedAt)
        try FileManager.default.createDirectory(at: dateFolderURL, withIntermediateDirectories: true)

        let filename = nameParser.resolve(date: screenshot.capturedAt)
        let outputURL = dateFolderURL.appendingPathComponent(filename)

        try write(screenshot.image, to: outputURL, scaleFactor: screenshot.scaleFactor)
        context.outputURLs.append(outputURL)
    }

    // MARK: - Private

    private func dailyFolder(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent(formatter.string(from: date))
    }

    private func write(_ image: CGImage, to url: URL, scaleFactor: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw LocalFileOutputError.destinationCreationFailed(url) }

        let dpi = scaleFactor * 72.0
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
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
        case .writeFailed(let url):               return "Failed to write PNG to \(url.path)."
        }
    }
}
