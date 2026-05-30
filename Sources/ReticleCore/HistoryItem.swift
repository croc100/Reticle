import Foundation

// MARK: - HistoryItem

/// A single entry in the capture history — mirrors ShareX's HistoryItem model.
public struct HistoryItem: Identifiable, Codable, Sendable {
    public let id: UUID
    /// When the capture was taken.
    public let capturedAt: Date
    /// Absolute path to the saved file, if any.
    public var filePath: String?
    /// URL convenience (computed, not stored).
    public var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }
    /// Screen rect of the captured region (display coordinates, Quartz/screen origin).
    public let sourceRect: CodableCGRect
    /// Backing-scale factor at capture time.
    public let scaleFactor: Double
    /// Pixel dimensions of the final image.
    public let widthPx: Int
    public let heightPx: Int
    /// JPEG thumbnail (max 200×200). Nil if unavailable.
    public var thumbnailData: Data?
    /// Optional user-provided title / label.
    public var title: String

    public init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        filePath: String? = nil,
        sourceRect: CGRect,
        scaleFactor: Double,
        widthPx: Int,
        heightPx: Int,
        thumbnailData: Data? = nil,
        title: String = ""
    ) {
        self.id            = id
        self.capturedAt    = capturedAt
        self.filePath      = filePath
        self.sourceRect    = CodableCGRect(sourceRect)
        self.scaleFactor   = scaleFactor
        self.widthPx       = widthPx
        self.heightPx      = heightPx
        self.thumbnailData = thumbnailData
        self.title         = title
    }
}

// MARK: - CGRect Codable wrapper

public struct CodableCGRect: Codable, Sendable {
    public var x, y, width, height: Double
    public init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
