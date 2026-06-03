import CoreGraphics
import Defaults
import Foundation

/// A single mask rule — either a fixed screen rect or an app/window match rule.
public struct MaskRegion: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var rule: MaskRule
    public var style: MaskStyle
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String = "",
                rule: MaskRule, style: MaskStyle = .blur(radius: 20), enabled: Bool = true) {
        self.id = id
        self.name = name
        self.rule = rule
        self.style = style
        self.enabled = enabled
    }
}

/// How the masked area is defined.
public enum MaskRule: Codable, Sendable {
    /// Fixed screen-coordinate rectangle — always masked regardless of what's on screen.
    case rect(CGRect)
    /// Any window belonging to the named app bundle identifier (e.g. "com.apple.Terminal").
    case appBundle(bundleID: String)
    /// Window whose title contains the given substring (case-insensitive).
    case windowTitle(contains: String)
}

public enum MaskStyle: Codable, Sendable {
    case blur(radius: Double)
    case pixelate(blockSize: Double)
    case solidFill(red: Double, green: Double, blue: Double)
}

// MARK: - Defaults serialization

extension MaskRegion: Defaults.Serializable {}
extension MaskRule: Defaults.Serializable {}
extension MaskStyle: Defaults.Serializable {}
