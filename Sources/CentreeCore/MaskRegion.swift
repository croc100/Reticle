import CoreGraphics
import Foundation

/// A single masked area defined by the user or detected automatically.
public struct MaskRegion: Identifiable, Codable, Sendable {
    public let id: UUID
    /// The rect in screen coordinates this mask covers.
    public var rect: CGRect
    public var style: MaskStyle

    public init(id: UUID = UUID(), rect: CGRect, style: MaskStyle = .blur(radius: 20)) {
        self.id = id
        self.rect = rect
        self.style = style
    }
}

public enum MaskStyle: Codable, Sendable {
    case blur(radius: Double)
    case pixelate(blockSize: Double)
    case solidFill(red: Double, green: Double, blue: Double)
}
