import CoreGraphics
import Foundation

/// The source geometry for a capture operation.
public enum CaptureMode: Sendable {
    /// User-drawn rectangle in screen coordinates.
    case region(CGRect)
    /// Specific window identified by its CGWindowID.
    case window(CGWindowID)
    /// Entire display.
    case fullScreen(displayID: CGDirectDisplayID)
}
