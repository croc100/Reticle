import AppKit
import ReticleCore
import Foundation

// MARK: - CaptureHistoryManager

/// Persists a flat list of capture history items as JSON in Application Support.
/// Thread-safe: all mutations happen on the main actor.
@MainActor
final class CaptureHistoryManager: ObservableObject {

    static let shared = CaptureHistoryManager()

    @Published private(set) var items: [HistoryItem] = []

    /// Maximum number of entries to keep. Oldest are dropped first.
    var maxItems: Int = 200

    private let storageURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Reticle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("captureHistory.json")
    }()

    private init() { load() }

    // MARK: - Public API

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            print("[CaptureHistory] load error: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[CaptureHistory] save error: \(error)")
        }
    }
}

// MARK: - Thumbnail helper

extension CaptureHistoryManager {
    /// Generate a ≤200×200 JPEG thumbnail from a CGImage.
    nonisolated static func makeThumbnail(from image: CGImage, maxSide: CGFloat = 200) -> Data? {
        let w = CGFloat(image.width); let h = CGFloat(image.height)
        let scale = min(maxSide / w, maxSide / h, 1.0)
        let tw = Int(w * scale); let th = Int(h * scale)
        guard tw > 0, th > 0,
              let ctx = CGContext(data: nil, width: tw, height: th,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let thumb = ctx.makeImage() else { return nil }
        let nsImage = NSImage(cgImage: thumb, size: NSSize(width: tw, height: th))
        guard let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    }
}
