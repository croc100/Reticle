import CoreGraphics
import Foundation

/// Lays several displays' captures out into one image.
///
/// Separate from the capture itself and free of ScreenCaptureKit, so the
/// arithmetic can be tested without a screen attached — which for compositing
/// is the whole of the risk.
public enum DisplayCompositor {

    /// One display's capture and where it goes.
    public struct Tile: Sendable {
        /// The display's rect within the canvas, in points, measured from the
        /// canvas's bottom-left corner.  ``DisplayLayout/placement(of:)``
        /// produces these.
        public let placement: CGRect
        public let image: CGImage

        public init(placement: CGRect, image: CGImage) {
            self.placement = placement
            self.image = image
        }
    }

    /// Draws every tile into one image covering `size` points at `scale`.
    ///
    /// The canvas is y-up with its origin at the bottom-left — the same as
    /// AppKit's screen space and the same as a bitmap context's user space —
    /// so placements go in unchanged. The CTM is scaled but never flipped:
    /// flipping it mirrors the content of every image drawn into it, which is
    /// what used to come out of the scroll stitcher.
    ///
    /// Area no display occupies is black. Displays need not tile the plane, so
    /// a staggered or L-shaped arrangement leaves corners with nothing in them,
    /// and a single rectangular image has to put something there.
    ///
    /// `scale` is the caller's choice; the highest scale factor among the
    /// displays is the useful one, since upscaling a 1x display loses nothing
    /// that was there while flattening to 1x discards half of a Retina one.
    public static func composite(
        tiles: [Tile],
        size: CGSize,
        scale: CGFloat
    ) throws -> CGImage {
        guard !tiles.isEmpty else { throw CaptureError.noMatchingContent }
        guard scale > 0 else { throw CaptureError.compositeFailed }

        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { throw CaptureError.compositeFailed }

        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw CaptureError.compositeFailed }

        // Fill before scaling, so the rect is in pixels and covers the canvas
        // exactly whatever the scale is.
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.scaleBy(x: scale, y: scale)
        for tile in tiles where !tile.placement.isEmpty {
            context.draw(tile.image, in: tile.placement)
        }

        guard let image = context.makeImage() else { throw CaptureError.compositeFailed }
        return image
    }
}
