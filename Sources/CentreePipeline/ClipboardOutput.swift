import AppKit
import CentreeCore
import Foundation

/// Copies the captured screenshot to the system clipboard.
///
/// Writes both `TIFF` and `PNG` representations so apps that request either type
/// (e.g. Slack, Figma) get a valid image.
public struct ClipboardOutput: OutputTask {
    public init() {}

    public func execute(screenshot: Screenshot, context: inout CaptureContext) async throws {
        let nsImage = NSImage(
            cgImage: screenshot.image,
            size: NSSize(
                width: CGFloat(screenshot.image.width) / screenshot.scaleFactor,
                height: CGFloat(screenshot.image.height) / screenshot.scaleFactor
            )
        )
        // NSPasteboard must be accessed on the main thread.
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        }
    }
}
