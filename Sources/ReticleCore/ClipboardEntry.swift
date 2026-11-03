import CoreGraphics
import Foundation

/// One entry in the clipboard history.
///
/// An image entry keeps the *encoded* bytes plus a small decoded preview, not a
/// decoded full-size image.  The poller used to turn whatever the pasteboard
/// held into a full `NSImage` and keep thirty of them: a full-screen Retina
/// capture is around 80 MB once decoded, so a handful of screenshot copies took
/// a menu-bar app into the hundreds of megabytes — and opening the history
/// panel then asked for all thirty to be resampled down to a 32-point row.
public enum ClipboardEntry: Identifiable, Sendable {
    case text(String)
    case image(ClipboardImage)

    /// Identity by content, so re-copying the same thing deduplicates.
    ///
    /// The old identity for text was its first 40 characters, so two different
    /// long strings sharing an opening line counted as the same entry and one
    /// silently replaced the other.  The old identity for an image was the
    /// `ObjectIdentifier` of a freshly built `NSImage`, which is different
    /// every time, so image entries never deduplicated at all.
    public var id: String {
        switch self {
        case .text(let string):  return "t-\(Self.fingerprint(of: string))"
        case .image(let image):  return "i-\(Self.fingerprint(of: image.data))"
        }
    }

    /// The row's main line: one line, bounded, safe to show as-is.
    public var displayText: String {
        switch self {
        case .text(let string):
            // Split rather than replace: Swift treats CRLF as one `Character`,
            // so a search for "\n" never matches the one inside it. Dropping
            // the empty pieces collapses runs of whitespace into one space,
            // which is what a single-line row wants regardless.
            let flattened = string
                .split(whereSeparator: { $0.isNewline || $0 == "\t" })
                .joined(separator: " ")
            return String(flattened.prefix(120))
        case .image(let image):
            return "Image \(image.pixelWidth)×\(image.pixelHeight)"
        }
    }

    /// The row's secondary line.
    public var typeLabel: String {
        switch self {
        case .text(let string):
            return "\(string.count) character\(string.count == 1 ? "" : "s")"
        case .image(let image):
            return image.byteSizeLabel
        }
    }

    // MARK: - Private

    /// A content fingerprint for in-memory deduplication only.
    ///
    /// `Hasher` is seeded once per process, so this is stable for as long as
    /// the history itself lives and no longer — which is all deduplicating a
    /// list held in memory requires.  Nothing persists it.
    private static func fingerprint<T: Hashable>(of value: T) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        let digest = UInt64(bitPattern: Int64(hasher.finalize()))
        return String(digest, radix: 36)
    }
}

// MARK: - ClipboardImage

/// An image on the clipboard, held as the bytes it arrived as.
public struct ClipboardImage: Sendable {
    /// The pasteboard's own bytes, kept so copying the entry back puts the
    /// original there rather than a re-encode of a re-decode.
    public let data: Data
    /// The pasteboard type identifier `data` came from, e.g. `public.png`.
    public let type: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// A row-sized preview, decoded at that size rather than scaled down from
    /// the full frame.
    public let thumbnail: CGImage

    public init(
        data: Data,
        type: String,
        pixelWidth: Int,
        pixelHeight: Int,
        thumbnail: CGImage
    ) {
        self.data = data
        self.type = type
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.thumbnail = thumbnail
    }

    /// Human-readable size of the retained bytes.
    public var byteSizeLabel: String {
        let kilobytes = Double(data.count) / 1024
        if kilobytes < 1024 {
            return String(format: "%.0f KB", kilobytes.rounded())
        }
        return String(format: "%.1f MB", kilobytes / 1024)
    }
}
