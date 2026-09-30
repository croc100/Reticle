import CoreGraphics
import ReticleCore
import ReticleNaming
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves the captured screenshot to a local directory.
///
/// Requested formats: PNG (lossless), JPEG, TIFF, WebP. WebP encoding is not available on
/// every macOS version Reticle supports, so an unavailable format falls back to PNG —
/// see `resolvedFormat`.
///
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

        let resolved = resolvedFormat

        // Resolve filename: strip any existing extension then add the one that matches the
        // format actually being encoded.
        let stem = (nameParser.resolve(date: screenshot.capturedAt) as NSString).deletingPathExtension
        let candidate = dateFolderURL.appendingPathComponent(stem + "." + resolved.pathExtension)
        let outputURL = Self.byAddingSuffixIfTaken(candidate)

        try write(screenshot.image, to: outputURL, type: resolved.type, scaleFactor: screenshot.scaleFactor)
        context.outputURLs.append(outputURL)
    }

    // MARK: - Format resolution

    /// The image type used for encoding, together with the file extension that matches it.
    ///
    /// Both come from one decision on purpose. Deriving them separately let a request for
    /// WebP on a system without a WebP encoder write PNG bytes to a `.webp` file — the
    /// payload and the name disagreed, and nothing downstream could tell.
    var resolvedFormat: (type: UTType, pathExtension: String) {
        let requested: (type: UTType?, pathExtension: String)
        switch format.lowercased() {
        case "jpeg", "jpg": requested = (.jpeg, "jpg")
        case "tiff", "tif": requested = (.tiff, "tiff")
        case "webp":        requested = (UTType("org.webmproject.webp"), "webp")
        default:            requested = (.png, "png")
        }

        guard let type = requested.type, Self.encodableTypes.contains(type.identifier) else {
            return (.png, "png")
        }
        return (type, requested.pathExtension)
    }

    /// Type identifiers ImageIO can actually write on this system.
    private static let encodableTypes: Set<String> = {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    // MARK: - Private

    private func dailyFolder(for date: Date) -> URL {
        let formatter = DateFormatter()
        // Pin the calendar and locale: a device set to a non-Gregorian calendar would
        // otherwise fold screenshots into folders named for a different year.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent(formatter.string(from: date))
    }

    /// Returns `url`, or `name (2).png`, `name (3).png`, … when it is already on disk.
    ///
    /// A pattern without `%counter%` or a seconds token resolves to the same name for two
    /// shots in a row, and `CGImageDestination` overwrites without complaint — so the
    /// earlier screenshot used to disappear.
    static func byAddingSuffixIfTaken(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        // Bounded so a permission error that makes every candidate "exist" cannot spin here.
        for n in 2...9999 {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private func write(_ image: CGImage, to url: URL, type: UTType, scaleFactor: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else { throw LocalFileOutputError.destinationCreationFailed(url) }

        let dpi = scaleFactor * 72.0
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth:  dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        // Apply JPEG quality when relevant.
        if type == .jpeg {
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
