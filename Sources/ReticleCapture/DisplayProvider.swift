import AppKit
import ScreenCaptureKit
import Foundation

/// Fetches the list of available displays and on-screen windows from ScreenCaptureKit.
///
/// Results are fetched fresh on every call — SCK caches internally, so this is cheap.
public actor DisplayProvider {
    public init() {}

    /// Returns all connected displays and all currently on-screen windows.
    public func fetchContent() async throws -> (displays: [SCDisplay], windows: [SCWindow]) {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return (content.displays, content.windows)
        } catch {
            throw CaptureError.permissionDenied
        }
    }

    /// Returns the display whose frame has the largest intersection with `rect`.
    /// Falls back to the primary display if no intersection is found.
    public func display(for rect: CGRect) async throws -> SCDisplay {
        let (displays, _) = try await fetchContent()
        guard !displays.isEmpty else { throw CaptureError.noMatchingContent }
        return displays.max { a, b in
            a.frame.intersection(rect).area < b.frame.intersection(rect).area
        } ?? displays[0]
    }

    /// Returns the `SCWindow` matching the given `CGWindowID`, if it is currently on screen.
    public func window(withID windowID: CGWindowID) async throws -> SCWindow {
        let (_, windows) = try await fetchContent()
        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.noMatchingContent
        }
        return window
    }

    /// Returns the display matching `displayID`, or the primary display as fallback.
    public func display(withID displayID: CGDirectDisplayID) async throws -> SCDisplay {
        let (displays, _) = try await fetchContent()
        guard !displays.isEmpty else { throw CaptureError.noMatchingContent }
        return displays.first(where: { $0.displayID == displayID }) ?? displays[0]
    }
}

// MARK: - Helpers

public extension SCDisplay {
    /// The backing scale factor (1.0 or 2.0) by correlating displayID with NSScreen.
    var backingScaleFactor: CGFloat {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == displayID
        }?.backingScaleFactor ?? 2.0
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
