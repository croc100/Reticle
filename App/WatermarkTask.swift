import AppKit
import CoreGraphics
import ReticleCore
import ReticleNaming
import ReticlePipeline
import Defaults
import Foundation

/// After-capture task that stamps configurable text onto the image.
///
/// Text supports NameParser tokens (%year%, %app%, %width%, etc.).
/// Position is one of nine grid cells; an optional dark pill background
/// improves legibility on light-coloured screenshots.
struct WatermarkTask: AfterCaptureTask {

    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        let template = Defaults[.watermarkText].trimmingCharacters(in: .whitespaces)
        guard !template.isEmpty else { return }

        let image = screenshot.image
        let w = image.width, h = image.height

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                        CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // 1. Draw base image (CG coords: y=0=bottom).
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 2. Resolve text template.
        var parser = NameParser(pattern: template)
        parser.imageWidth  = w
        parser.imageHeight = h
        let resolved = parser.resolve(date: context.triggeredAt)

        // 3. Build text attributes.
        let sf       = screenshot.scaleFactor
        let ptSize   = CGFloat(Defaults[.watermarkFontSize]) * sf
        let opacity  = CGFloat(Defaults[.watermarkOpacity])
        let hexColor = Defaults[.watermarkColorHex]
        let textColor = (NSColor(hexString: hexColor) ?? .white).withAlphaComponent(opacity)
        let shadow = NSShadow()
        shadow.shadowColor  = NSColor.black.withAlphaComponent(opacity * 0.6)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: ptSize, weight: .semibold),
            .foregroundColor: textColor,
            .shadow:          shadow,
        ]
        let str      = NSAttributedString(string: resolved, attributes: attrs)
        let textSize = str.size()

        // 4. Compute position (CG coords: origin = bottom-left).
        let padding  = 12 * sf
        let pos      = Defaults[.watermarkPosition]
        let origin   = watermarkOrigin(
            position: pos, textSize: textSize,
            imgW: CGFloat(w), imgH: CGFloat(h), padding: padding)

        // 5. Draw watermark via NSGraphicsContext on the CGContext.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        // Optional dark pill background.
        if Defaults[.watermarkBackground] {
            let pad: CGFloat = 4 * sf
            let bgRect = NSRect(
                x: origin.x - pad, y: origin.y - pad / 2,
                width: textSize.width + pad * 2, height: textSize.height + pad)
            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()
        }

        str.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()

        guard let result = ctx.makeImage() else { return }
        screenshot = Screenshot(
            image: result,
            capturedAt: screenshot.capturedAt,
            sourceRect: screenshot.sourceRect,
            scaleFactor: screenshot.scaleFactor)
    }

    // MARK: - Position helpers

    /// Returns the bottom-left origin for the watermark text in CG (y=0=bottom) coordinates.
    private func watermarkOrigin(position: String, textSize: CGSize,
                                 imgW: CGFloat, imgH: CGFloat, padding: CGFloat) -> NSPoint {
        let x: CGFloat
        let y: CGFloat
        switch position {
        case "topLeft":
            x = padding
            y = imgH - textSize.height - padding
        case "topCenter":
            x = (imgW - textSize.width) / 2
            y = imgH - textSize.height - padding
        case "topRight":
            x = imgW - textSize.width - padding
            y = imgH - textSize.height - padding
        case "middleLeft":
            x = padding
            y = (imgH - textSize.height) / 2
        case "center":
            x = (imgW - textSize.width) / 2
            y = (imgH - textSize.height) / 2
        case "middleRight":
            x = imgW - textSize.width - padding
            y = (imgH - textSize.height) / 2
        case "bottomLeft":
            x = padding
            y = padding
        case "bottomCenter":
            x = (imgW - textSize.width) / 2
            y = padding
        default:  // "bottomRight"
            x = imgW - textSize.width - padding
            y = padding
        }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - NSColor hex helper

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1.0
        )
    }
}
