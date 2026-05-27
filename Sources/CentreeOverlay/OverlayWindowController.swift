import AppKit
import CoreGraphics
import ScreenCaptureKit
import CentreeCore

// MARK: - Result type

public enum OverlayResult: Sendable {
    case region(CGRect)      // selected rect in screen coordinates
    case cancelled
}

// MARK: - Controller

/// Presents full-screen frozen-screenshot overlays on every connected display,
/// waits for the user to drag-select a region (or pick a detected window),
/// then tears everything down.
@MainActor
public final class OverlayWindowController {
    private var windows: [OverlayNSWindow] = []
    private var continuation: CheckedContinuation<OverlayResult, Never>?

    public init() {}

    // MARK: - Public API

    /// Shows the overlay and suspends until the user selects a region or presses Escape.
    ///
    /// - Parameters:
    ///   - backgrounds: One `(frame, image)` per display. Frame is in AppKit screen coordinates.
    ///   - scWindows: On-screen SCWindows from SCShareableContent (for grid highlight).
    public func show(
        backgrounds: [(frame: CGRect, image: CGImage)],
        scWindows: [SCWindow] = []
    ) async -> OverlayResult {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.present(backgrounds: backgrounds, scWindows: scWindows)
        }
    }

    // MARK: - Private

    private func present(backgrounds: [(frame: CGRect, image: CGImage)], scWindows: [SCWindow]) {
        for (frame, image) in backgrounds {
            let window = OverlayNSWindow(frame: frame)
            let view = OverlayView(backgroundImage: image)
            view.scWindows = scWindows
            view.delegate = self
            view.frame = window.contentView!.bounds
            view.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(view)
            window.makeFirstResponder(view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSCursor.crosshair.set()
    }

    private func finish(with result: OverlayResult) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

// MARK: - OverlayViewDelegate

extension OverlayWindowController: OverlayViewDelegate {
    func overlayView(_ view: OverlayView, didSelectRect rect: CGRect) {
        finish(with: .region(rect))
    }

    func overlayView(_ view: OverlayView, didSelectWindowFrame frame: CGRect) {
        finish(with: .region(frame))
    }

    func overlayViewDidCancel(_ view: OverlayView) {
        finish(with: .cancelled)
    }
}

// MARK: - NSWindow subclass

private final class OverlayNSWindow: NSWindow {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Place above every other window including full-screen apps.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
