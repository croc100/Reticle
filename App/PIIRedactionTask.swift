import CoreGraphics
import ReticleCore
import ReticleEffects
import ReticlePipeline
import ReticleVision
import Foundation

/// After-capture task that runs Vision OCR, detects PII patterns, and blurs
/// every identified region in-place before the image is saved or uploaded.
///
/// Coordinate note:
///   - PIIDetector returns rects in Vision pixel space (y=0=bottom).
///   - MaskRenderer expects rects in screen/view space (y=0=top).
///   - This task flips the y-axis accordingly.
struct PIIRedactionTask: AfterCaptureTask {
    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        let image = screenshot.image

        // 1. Detect PII regions (Vision pixel space, y=0=bottom)
        let rawRegions = try await PIIDetector().detect(in: image)
        guard !rawRegions.isEmpty else { return }

        // 2. Flip y to screen/view space (y=0=top) for MaskRenderer
        let imgH = CGFloat(image.height)
        let flipped: [MaskRegion] = rawRegions.compactMap { region in
            guard case .rect(let r) = region.rule else { return nil }
            let flippedRect = CGRect(x: r.minX, y: imgH - r.maxY, width: r.width, height: r.height)
            return MaskRegion(rule: .rect(flippedRect), style: region.style)
        }

        // 3. Apply blur to each detected region
        let redacted = try MaskRenderer().render(image: image, masks: flipped)
        screenshot = Screenshot(image: redacted,
                                sourceRect: screenshot.sourceRect,
                                scaleFactor: screenshot.scaleFactor)
    }
}
