import AppKit
import CoreGraphics
import Foundation

/// Where the connected displays sit relative to one another.
///
/// Every rect here is in **AppKit's global screen space**: the origin is the
/// bottom-left corner of the primary display and y grows upward.
/// `NSEvent.mouseLocation` reports in that same space, which is the reason this
/// type exists rather than the geometry being done inline against Quartz
/// display coordinates. Quartz puts the origin at the primary display's
/// *top*-left with y growing downward, so feeding an AppKit point to Quartz
/// rects — or the reverse — picks the right display only on the single-monitor
/// case and on layouts where every display's top edge is aligned. Anything
/// stacked vertically silently resolves to the wrong screen.
///
/// The geometry is kept free of `NSScreen` so it can be tested without a
/// display attached; ``current`` is the only part that reads the real layout.
public struct DisplayLayout: Sendable, Equatable {

    /// One connected display.
    public struct Display: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        /// The display's frame in AppKit global screen coordinates.
        public let frame: CGRect

        public init(displayID: CGDirectDisplayID, frame: CGRect) {
            self.displayID = displayID
            self.frame = frame
        }
    }

    public let displays: [Display]

    /// Answer of last resort, for a layout with no displays in it at all.
    public let primary: CGDirectDisplayID

    public init(displays: [Display], primary: CGDirectDisplayID) {
        self.displays = displays
        self.primary = primary
    }

    /// The display `point` falls on, in AppKit global screen coordinates.
    ///
    /// `CGRect.contains` excludes the max edges, so two displays sharing a
    /// border never both claim the same point and the answer is deterministic
    /// right at the seam.
    ///
    /// A point outside every display resolves to the **nearest** one rather
    /// than to the primary. The pointer is always on some display in reality,
    /// so a miss means this layout is a moment out of date — a display just
    /// woken, unplugged or rearranged — and the nearest display is a better
    /// guess than jumping back to the primary, which may be somewhere else
    /// entirely.
    public func display(containing point: CGPoint) -> CGDirectDisplayID {
        if let hit = displays.first(where: { $0.frame.contains(point) }) {
            return hit.displayID
        }
        let nearest = displays.min {
            $0.frame.squaredDistance(to: point) < $1.frame.squaredDistance(to: point)
        }
        return nearest?.displayID ?? primary
    }
}

// MARK: - The real layout

public extension DisplayLayout {

    /// The layout as AppKit reports it right now.
    ///
    /// Main-actor only, because `NSScreen.screens` is.
    @MainActor
    static var current: DisplayLayout {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let displays = NSScreen.screens.compactMap { screen -> Display? in
            guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else {
                return nil
            }
            return Display(displayID: id, frame: screen.frame)
        }
        return DisplayLayout(displays: displays, primary: CGMainDisplayID())
    }

    /// The display the pointer is on.
    ///
    /// Deliberately `NSEvent.mouseLocation` and not the Quartz cursor
    /// position: the point and the frames it is tested against have to be in
    /// one coordinate space, and `NSScreen.frame` is AppKit's.
    @MainActor
    static func displayUnderPointer() -> CGDirectDisplayID {
        current.display(containing: NSEvent.mouseLocation)
    }
}

// MARK: - Geometry

private extension CGRect {
    /// Squared distance from `point` to the nearest edge of this rect, or zero
    /// when the point is inside it.
    ///
    /// Squared, because only the ordering is wanted and a square root would
    /// add nothing but rounding.
    func squaredDistance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}
