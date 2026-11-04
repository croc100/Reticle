import CoreGraphics
import Foundation

/// A window as the chooser sees it.
///
/// Deliberately carries no origin. "Which window am I working in" is a
/// question about ownership and stacking order, and answering it without
/// coordinates keeps this clear of the one genuinely unsettled thing in this
/// codebase: whether ScreenCaptureKit reports frames in AppKit's screen space
/// or Quartz's. `Capturer.crop` documents `SCDisplay.frame` as AppKit
/// (bottom-left origin) and flips Y on that basis; `ScrollCapturer` documents
/// `SCWindow.frame` as Quartz (top-left origin). Both cannot be right, and
/// settling it needs a Mac with two displays stacked vertically. Nothing here
/// depends on the answer — size is carried as width and height, which need no
/// origin at all.
public struct WindowCandidate: Sendable, Equatable {
    public let windowID: CGWindowID
    /// Window level. 0 is an ordinary document or app window; panels, menus,
    /// tooltips, the Dock and the desktop picture all sit on other levels.
    public let layer: Int
    public let isOnScreen: Bool
    public let processID: pid_t
    public let width: CGFloat
    public let height: CGFloat
    public let title: String?

    public init(
        windowID: CGWindowID,
        layer: Int,
        isOnScreen: Bool,
        processID: pid_t,
        width: CGFloat,
        height: CGFloat,
        title: String? = nil
    ) {
        self.windowID = windowID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.processID = processID
        self.width = width
        self.height = height
        self.title = title
    }

    var area: CGFloat { width * height }
}

// MARK: - Chooser

/// Chooses the window a "capture what I am working in" hotkey should take.
///
/// Pure, so the rules can be tested without a window server: the caller
/// supplies the candidates, the window server's front-to-back order and which
/// application has focus.
public enum ActiveWindowChooser {

    /// Smallest side, in points, a window must have to be considered.
    ///
    /// Applications keep invisible one-point helper windows around — for
    /// tracking, for drag sources, for offscreen rendering. Without a floor the
    /// chooser picks one of those and the capture is a single pixel.
    public static let minimumSide: CGFloat = 40

    /// - Parameters:
    ///   - candidates: Every window the capture system can see.
    ///   - order: Window IDs front-to-back, as `CGWindowListCopyWindowInfo`
    ///     reports them. `SCShareableContent` makes no ordering promise, so the
    ///     order has to come from there and only from there.
    ///   - frontmostProcessID: The application with focus, if known.
    ///   - excludedProcessID: A process whose windows are never the answer —
    ///     this app's own.
    /// - Returns: The window to capture, or nil when nothing is eligible.
    public static func choose(
        from candidates: [WindowCandidate],
        frontToBack order: [CGWindowID],
        frontmostProcessID: pid_t?,
        excluding excludedProcessID: pid_t? = nil
    ) -> CGWindowID? {
        let eligible = candidates.filter {
            $0.isOnScreen
                && $0.layer == 0
                && $0.width >= minimumSide
                && $0.height >= minimumSide
                && $0.processID != excludedProcessID
        }
        guard !eligible.isEmpty else { return nil }

        // Reticle is a menu-bar app and does not take focus, but opening its
        // menu can briefly make it frontmost — and "capture the window I am
        // working in" must never answer "Reticle".
        let focused = frontmostProcessID == excludedProcessID ? nil : frontmostProcessID

        // The focused application's windows first, ahead of stacking order: a
        // floating panel from another app can sit in front of the window the
        // user is actually typing into.
        let owned = focused.map { pid in eligible.filter { $0.processID == pid } } ?? []
        let preferred = owned.isEmpty ? eligible : owned

        // Among those, whichever the window server puts closest to the front.
        var position: [CGWindowID: Int] = [:]
        for (index, windowID) in order.enumerated() where position[windowID] == nil {
            position[windowID] = index
        }
        let ranked = preferred.compactMap { candidate -> (Int, WindowCandidate)? in
            guard let index = position[candidate.windowID] else { return nil }
            return (index, candidate)
        }
        if let front = ranked.min(by: { $0.0 < $1.0 }) {
            return front.1.windowID
        }

        // None of them appeared in the order list, which should not happen for
        // on-screen windows but is not worth failing over. The largest is
        // usually the main window; the ID breaks ties so the answer does not
        // depend on the order the candidates arrived in.
        return preferred.max {
            ($0.area, $0.windowID) < ($1.area, $1.windowID)
        }?.windowID
    }
}
