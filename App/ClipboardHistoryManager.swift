import AppKit
import Combine
import CoreGraphics
import ImageIO
import ReticleCore

// MARK: - ClipboardHistoryManager

/// Polls `NSPasteboard.general` for changes and maintains a capped history.
@MainActor
final class ClipboardHistoryManager: ObservableObject {

    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardEntry] = []

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 30

    /// Longest side of the preview kept for the history row, in pixels.
    /// The row draws at 32 points, so this covers a 2x display.
    private let thumbnailMaxPixelSize = 64

    private init() { startPolling() }

    deinit { timer?.invalidate() }

    // MARK: - Poll

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkPasteboard() }
        }
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            push(.text(string))
            return
        }

        // PNG before TIFF.  Both are usually on the pasteboard, and TIFF is the
        // uncompressed one - roughly 80 MB for a full-screen Retina capture
        // against a couple of megabytes for the same frame as PNG.  Asking for
        // TIFF first also forces any lazily-provided TIFF to be generated,
        // which is exactly the cost `ClipboardOutput` arranges to avoid.
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type),
                  let entry = makeImageEntry(data: data, type: type) else { continue }
            push(entry)
            return
        }
    }

    /// Builds an entry without ever decoding the image at full size.
    ///
    /// The dimensions come from the image's own metadata and the preview is
    /// decoded straight to row size, so a 20-megapixel screenshot costs the
    /// bytes it arrived as plus a 64-pixel thumbnail - not 80 MB of bitmap.
    private func makeImageEntry(
        data: Data,
        type: NSPasteboard.PasteboardType
    ) -> ClipboardEntry? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width  = properties?[kCGImagePropertyPixelWidth]  as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }

        return .image(ClipboardImage(
            data: data,
            type: type.rawValue,
            pixelWidth: width,
            pixelHeight: height,
            thumbnail: thumbnail))
    }

    private func push(_ entry: ClipboardEntry) {
        // Deduplicate by content.
        items.removeAll { $0.id == entry.id }
        items.insert(entry, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }

    // MARK: - Copy back

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            // The bytes exactly as they arrived, in the type they arrived as:
            // no re-encode, and nothing lost on the way back.
            pasteboard.setData(image.data, forType: NSPasteboard.PasteboardType(image.type))
        }
        // Don't push back - it would show as a duplicate
        lastChangeCount = pasteboard.changeCount
    }

    func clear() { items.removeAll() }
}
