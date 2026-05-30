import CoreGraphics
import Foundation

/// The result of a single capture operation, passed through the pipeline.
public struct Screenshot: Sendable {
    public let image: CGImage
    public let capturedAt: Date
    /// The rect in screen coordinates (origin at top-left, points) that was captured.
    public let sourceRect: CGRect
    /// The display scale factor of the source screen (1.0 or 2.0 for Retina).
    public let scaleFactor: CGFloat

    public init(
        image: CGImage,
        capturedAt: Date = .now,
        sourceRect: CGRect,
        scaleFactor: CGFloat = 2.0
    ) {
        self.image = image
        self.capturedAt = capturedAt
        self.sourceRect = sourceRect
        self.scaleFactor = scaleFactor
    }
}
