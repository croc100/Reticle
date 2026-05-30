import AppKit
import ReticleCore
import ReticlePipeline
import Foundation

/// After-capture task that opens the system print dialog for the captured image.
///
/// The print operation runs on the main actor because `NSPrintOperation` requires
/// a window to attach its sheet to; we create a temporary offscreen window.
struct PrintTask: AfterCaptureTask {

    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        let image = screenshot.image
        await MainActor.run { printImage(image) }
    }

    @MainActor
    private func printImage(_ cgImage: CGImage) {
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        let view = NSImageView(frame: NSRect(
            x: 0, y: 0,
            width: nsImage.size.width, height: nsImage.size.height))
        view.image = nsImage
        view.imageScaling = .scaleProportionallyUpOrDown

        let op = NSPrintOperation(view: view)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // Run as a modal sheet; if no key window is available, run modally.
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil,
                        didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }
}
