import AppKit
import CoreGraphics
import Foundation
import ReticleCore
import ScreenCaptureKit

/// Bridges the window server's view of what is in front into
/// ``ActiveWindowChooser``.
///
/// The split is deliberate: the rules live in `ReticleCore` where they can be
/// tested, and the three system reads that cannot be — the window list, the
/// stacking order and which application has focus — live here.
@MainActor
public enum ActiveWindowLocator {

    /// The window to capture, chosen from what ScreenCaptureKit can see.
    public static func choose(from windows: [SCWindow]) -> CGWindowID? {
        let candidates = windows.map { window in
            WindowCandidate(
                windowID: window.windowID,
                layer: window.windowLayer,
                isOnScreen: window.isOnScreen,
                // A window whose owner cannot be read is attributed to no
                // process: -1 is not a pid, so it never matches the focused
                // application and never matches this one either.
                processID: window.owningApplication?.processID ?? -1,
                width: window.frame.width,
                height: window.frame.height,
                title: window.title)
        }
        return ActiveWindowChooser.choose(
            from: candidates,
            frontToBack: frontToBackOrder(),
            frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            excluding: ProcessInfo.processInfo.processIdentifier)
    }

    /// On-screen window IDs, front to back.
    ///
    /// `CGWindowListCopyWindowInfo` returns them in that order, which
    /// `SCShareableContent` does not promise — hence reading the order from
    /// here and nothing else. Only the window numbers are used, so this needs
    /// no Screen Recording permission of its own; titles and owner names are
    /// the parts that do.
    static func frontToBackOrder() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? Int,
                  number >= 0 else { return nil }
            return CGWindowID(number)
        }
    }
}
