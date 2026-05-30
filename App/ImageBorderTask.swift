import AppKit
import CoreGraphics
import ReticleCore
import ReticlePipeline
import Defaults
import Foundation

/// After-capture task that adds a solid coloured border (and optional drop shadow)
/// around the captured image.
///
/// The output canvas is expanded so no image content is cropped:
///   - shadow extends outward `ceil(blur * 3)` px on each side
///   - border thickness is drawn inside that margin
struct ImageBorderTask: AfterCaptureTask {

    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        let sf       = screenshot.scaleFactor
        let img      = screenshot.image
        let imgW     = CGFloat(img.width)
        let imgH     = CGFloat(img.height)

        // Pixel-space border thickness (minimum 1 px).
        let borderPx = max(1, CGFloat(Defaults[.borderWidth]) * sf)
        let hasShadow = Defaults[.borderShadow]
        let shadowBlur = CGFloat(Defaults[.borderShadowBlur])
        // Extra padding needed beyond the border for the shadow glow.
        let shadowPad: CGFloat = hasShadow ? ceil(shadowBlur * 3) : 0

        let pad = borderPx + shadowPad  // total canvas margin per side

        let canvasW = Int(imgW + pad * 2)
        let canvasH = Int(imgH + pad * 2)

        guard let ctx = CGContext(
            data: nil, width: canvasW, height: canvasH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                        CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // ── 1. Drop shadow ────────────────────────────────────────────────────
        if hasShadow {
            let imgRect = CGRect(x: pad, y: pad, width: imgW, height: imgH)
            ctx.saveGState()
            // Draw the shadow of the image rect only (not the image itself yet).
            ctx.setShadow(
                offset: CGSize(width: 0, height: 0),
                blur: shadowBlur,
                color: CGColor(gray: 0, alpha: 0.6))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(imgRect)
            ctx.restoreGState()
        }

        // ── 2. Border rect (fills margin between shadow pad and image) ────────
        let borderColorHex = Defaults[.borderColorHex]
        let borderOpacity  = CGFloat(Defaults[.borderOpacity])
        let borderColor = nsColorFromHex(borderColorHex)?.withAlphaComponent(borderOpacity).cgColor
                          ?? CGColor(gray: 0, alpha: borderOpacity)

        ctx.setFillColor(borderColor)
        // Four rects: top, bottom, left, right (avoids clipping the shadow)
        let bRect = CGRect(x: shadowPad, y: shadowPad,
                           width: imgW + borderPx * 2, height: imgH + borderPx * 2)
        ctx.fill(bRect)

        // ── 3. Image ───────────────────────────────────────────────────────────
        let imgDest = CGRect(x: pad, y: pad, width: imgW, height: imgH)
        ctx.draw(img, in: imgDest)

        guard let result = ctx.makeImage() else { return }
        // Source rect: expand by the extra border/shadow padding in screen points.
        let padPt  = pad / sf
        let newSrc = screenshot.sourceRect.insetBy(dx: -padPt, dy: -padPt)
        screenshot = Screenshot(
            image: result,
            capturedAt: screenshot.capturedAt,
            sourceRect: newSrc,
            scaleFactor: sf)
    }

    // MARK: - Helper

    private func nsColorFromHex(_ hex: String) -> NSColor? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        return NSColor(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1.0)
    }
}
