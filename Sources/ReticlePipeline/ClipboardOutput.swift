import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ReticleCore
import UniformTypeIdentifiers

/// Copies the captured screenshot to the system clipboard.
///
/// Advertises both PNG and TIFF, because which one the receiving app asks for
/// is not predictable: Slack, Figma and most web apps take PNG, while older
/// AppKit apps and the iWork suite ask for TIFF.  `writeObjects([NSImage])`
/// advertised only what `NSImage` itself declares — TIFF and PDF — so an app
/// that asked for PNG found nothing on the pasteboard, which is the opposite of
/// what the old comment here claimed.
///
/// PNG is written up front; TIFF is provided on demand.  TIFF is uncompressed,
/// so a full-screen Retina capture runs to roughly 80 MB, and pushing that into
/// the pasteboard server on every copy costs a visible pause and twice that
/// again in transient memory — for bytes most consumers never request.  The
/// same frame is a couple of megabytes as PNG, and writing *that* one eagerly
/// is what keeps the clipboard usable if Reticle is quit before the paste.
public struct ClipboardOutput: OutputTask {
    public init() {}

    public func execute(screenshot: Screenshot, context: inout CaptureContext) async throws {
        let image = screenshot.image
        let scale = screenshot.scaleFactor
        // NSPasteboard must be accessed on the main thread.
        await MainActor.run {
            ClipboardImageOwner.shared.copy(image: image, scaleFactor: scale)
        }
    }
}

// MARK: - Pasteboard owner

/// Holds the frame behind the clipboard's lazily-provided representations.
///
/// `NSPasteboard` keeps an *unowned* reference to a type owner, so the owner has
/// to outlive the copy — a shared instance is the simplest thing that cannot
/// dangle.  Only the most recent copy is ever asked for, because
/// `declareTypes(_:owner:)` revokes the previous declaration.
///
/// Not an actor and not `@MainActor`: `NSPasteboardTypeOwner` is a plain
/// Objective-C protocol that AppKit calls on the main thread, and a main-actor
/// method cannot satisfy a nonisolated requirement.  `@unchecked Sendable`
/// records the invariant instead — every path in and out of here is main-thread
/// only, which ``ClipboardOutput`` enforces with `MainActor.run`.
final class ClipboardImageOwner: NSObject, NSPasteboardTypeOwner, @unchecked Sendable {

    static let shared = ClipboardImageOwner()

    private var image: CGImage?
    private var scaleFactor: CGFloat = 2.0

    /// Declares the available types and writes the eager one.
    func copy(image: CGImage, scaleFactor: CGFloat) {
        self.image = image
        self.scaleFactor = scaleFactor

        let pasteboard = NSPasteboard.general
        _ = pasteboard.declareTypes([.png, .tiff], owner: self)
        if let png = ClipboardImageOwner.data(from: image, as: .png, scaleFactor: scaleFactor) {
            pasteboard.setData(png, forType: .png)
        }
    }

    // MARK: - NSPasteboardTypeOwner

    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let image else { return }
        if let tiff = ClipboardImageOwner.data(from: image, as: .tiff, scaleFactor: scaleFactor) {
            sender.setData(tiff, forType: .tiff)
        }
    }

    // MARK: - Encoding

    /// Encodes `image` for the pasteboard, stamping the capture's own DPI so a
    /// Retina screenshot pastes at the size it was taken at rather than at
    /// twice it.
    ///
    /// `CGImageDestination` rather than `NSImage.tiffRepresentation`: the latter
    /// materialises the frame as uncompressed TIFF before any encoder runs, so
    /// even asking it for PNG costs the big allocation first.
    static func data(
        from image: CGImage,
        as type: NSPasteboard.PasteboardType,
        scaleFactor: CGFloat
    ) -> Data? {
        let utType: UTType = type == .png ? .png : .tiff
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, utType.identifier as CFString, 1, nil
        ) else { return nil }

        let dpi = scaleFactor * 72.0
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}
