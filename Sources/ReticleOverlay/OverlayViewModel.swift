import AppKit
import CoreImage

// MARK: - Line Style

/// Stroke dash pattern for shape annotations.
enum LineStyle: String, CaseIterable {
    case solid  = "solid"
    case dashed = "dashed"
    case dotted = "dotted"
}

// MARK: - OverlayViewModel

/// Shared observable state between the overlay NSView and the SwiftUI toolbar.
@MainActor
final class OverlayViewModel: ObservableObject {

    // MARK: Tool state

    @Published var activeTool: AnnotationTool = .region
    @Published var strokeColor: NSColor = .systemRed
    /// Separate color for the highlight tool — defaults to classic fluorescent yellow.
    @Published var highlightColor: NSColor = NSColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0)
    @Published var lineWidth: CGFloat = 2
    @Published var lineStyle: LineStyle = .solid
    @Published var fontSize: CGFloat = 18
    @Published var highlightOpacity: CGFloat = 0.35
    @Published var blurRadius: CGFloat = 20
    @Published var pixelateSize: CGFloat = 12
    @Published var magnifyScale: CGFloat = 2
    @Published var emojiSize: CGFloat = 40
    @Published var cursorSize: CGFloat = 32
    @Published var cropRect: NSRect? = nil
    /// Spotlight dark overlay opacity (0 = transparent, 1 = opaque black).
    @Published var spotlightOpacity: CGFloat = 0.62
    /// Tail direction applied to the next speech balloon annotation.
    @Published var balloonTailDirection: BalloonTailDirection = .bottomLeft

    // MARK: Annotations

    @Published var annotations: [Annotation] = []
    @Published var canUndo: Bool = false

    // MARK: Selection

    @Published var selectionRect: NSRect? = nil
    var hasSelection: Bool { selectionRect != nil }

    /// When true: clicking a hovered window immediately fires capture (no Enter needed).
    var windowPickerMode: Bool = false

    // MARK: Callbacks (set by OverlayWindowController)

    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: Undo

    private var undoStack: [[Annotation]] = []

    func pushUndo() {
        undoStack.append(annotations)
        canUndo = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        annotations = last
        canUndo = !undoStack.isEmpty
    }

    func addAnnotation(_ ann: Annotation) {
        pushUndo()
        annotations.append(ann)
    }

    var nextStepNumber: Int {
        (annotations.compactMap { ($0 as? StepAnnotation)?.number }.max() ?? 0) + 1
    }

    // MARK: - CoreImage context (shared, GPU-accelerated)

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Final render

    /// Crops `baseCGImage` to `selectionRect` and composites all annotations.
    ///
    /// - Parameters:
    ///   - baseCGImage: Full-display frozen screenshot.
    ///   - selectionRect: Selection in overlay view coords (isFlipped=true, points).
    ///   - scaleFactor: Actual points → pixels ratio (derived from image.width / view.width).
    func renderFinalImage(
        baseCGImage: CGImage,
        selectionRect sel: NSRect,
        scaleFactor: CGFloat
    ) -> CGImage? {
        // ── 1. Pixel-perfect base crop ──────────────────────────────────────────
        // Round to whole-pixel boundaries so there is no sub-pixel origin drift
        // and the cropped CGImage is exactly the pixels we want — no resampling.
        let imageH = CGFloat(baseCGImage.height)
        let px = (sel.minX * scaleFactor).rounded()
        let py = (imageH - sel.maxY * scaleFactor).rounded()
        let pw = (sel.width  * scaleFactor).rounded()
        let ph = (sel.height * scaleFactor).rounded()
        let cropRect = CGRect(x: px, y: py, width: pw, height: ph)
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(baseCGImage.width), height: imageH))
        guard !cropRect.isEmpty,
              let cropped = baseCGImage.cropping(to: cropRect) else { return nil }

        let w = cropped.width   // output dimensions match the crop exactly — zero resampling
        let h = cropped.height
        guard w > 0, h > 0 else { return nil }

        // Use the source image's own color space (e.g. Display P3) to avoid any
        // color-space conversion that would degrade per-pixel accuracy.
        let colorSpace = baseCGImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high

        // Draw base: 1:1 pixel copy, no scaling whatsoever.
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))

        // ── 2. Effect annotations (blur / pixelate / blackout / magnify) ────────
        let pixelOrigin = CGPoint(x: px, y: py)    // already rounded
        for ann in annotations {
            let relPixelRect = pixelRelative(ann: ann, sel: sel, scale: scaleFactor)
            guard !relPixelRect.isEmpty else { continue }

            if let blur = ann as? BlurAnnotation {
                if let blurredCG = applyBlur(baseCGImage: baseCGImage,
                                             absolutePixelRect: relPixelRect.offsetBy(dx: pixelOrigin.x, dy: pixelOrigin.y),
                                             radius: Float(blur.radius * scaleFactor / 4)) {
                    ctx.draw(blurredCG, in: relPixelRect)
                }

            } else if let pix = ann as? PixelateAnnotation {
                if let pixelatedCG = applyPixelate(baseCGImage: baseCGImage,
                                                   absolutePixelRect: relPixelRect.offsetBy(dx: pixelOrigin.x, dy: pixelOrigin.y),
                                                   scale: Float(pix.pixelSize * scaleFactor / 4)) {
                    ctx.draw(pixelatedCG, in: relPixelRect)
                }

            } else if ann is BlackoutAnnotation {
                ctx.setFillColor(CGColor.black)
                ctx.fill(relPixelRect)

            } else if let mag = ann as? MagnifyAnnotation {
                let srcW = relPixelRect.width  / mag.scale
                let srcH = relPixelRect.height / mag.scale
                let absSrc = CGRect(
                    x: relPixelRect.midX + pixelOrigin.x - srcW / 2,
                    y: relPixelRect.midY + pixelOrigin.y - srcH / 2,
                    width: srcW, height: srcH)
                if let magCropped = baseCGImage.cropping(to: absSrc) {
                    ctx.saveGState()
                    ctx.addEllipse(in: relPixelRect)
                    ctx.clip()
                    ctx.draw(magCropped, in: relPixelRect)
                    ctx.restoreGState()
                    ctx.setStrokeColor(mag.color.cgColor)
                    ctx.setLineWidth(mag.lineWidth * scaleFactor)
                    ctx.strokeEllipse(in: relPixelRect)
                }
            }
        }

        // ── 3. Vector annotations ────────────────────────────────────────────────
        // Transform: view-point coords → output-pixel coords (flip + scale).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scaleFactor, y: -scaleFactor)
        ctx.translateBy(x: -sel.minX, y: -sel.minY)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        // overlayBounds gives annotations the full-screen coordinate space they
        // were drawn in, so relative positions remain correct.
        let overlayBounds = NSRect(x: 0, y: 0,
                                   width:  CGFloat(baseCGImage.width)  / scaleFactor,
                                   height: CGFloat(baseCGImage.height) / scaleFactor)
        for ann in annotations {
            if ann is BlurAnnotation || ann is PixelateAnnotation || ann is BlackoutAnnotation { continue }
            ann.drawRotated(in: overlayBounds)
        }

        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()

        // ── 4. Spotlight overlay ─────────────────────────────────────────────────
        let spotlights = annotations.compactMap { $0 as? SpotlightAnnotation }
        if !spotlights.isEmpty {
            let fullPath = CGMutablePath()
            fullPath.addRect(CGRect(x: 0, y: 0, width: w, height: h))
            for sp in spotlights {
                let relRect = CGRect(
                    x: (sp.rect.minX - sel.minX) * scaleFactor,
                    y: (sel.maxY - sp.rect.maxY) * scaleFactor,
                    width:  sp.rect.width  * scaleFactor,
                    height: sp.rect.height * scaleFactor)
                fullPath.addEllipse(in: relRect)
            }
            ctx.addPath(fullPath)
            ctx.setFillColor(NSColor.black.withAlphaComponent(spotlightOpacity).cgColor)
            ctx.fillPath(using: .evenOdd)
        }

        return ctx.makeImage()
    }

    // MARK: - Helpers

    /// Rect of an annotation relative to selection top-left, in pixels.
    private func pixelRelative(ann: Annotation, sel: NSRect, scale: CGFloat) -> CGRect {
        var r: NSRect?
        if let a = ann as? BlurAnnotation          { r = a.rect }
        else if let a = ann as? PixelateAnnotation { r = a.rect }
        else if let a = ann as? BlackoutAnnotation { r = a.rect }
        else if let a = ann as? MagnifyAnnotation  { r = a.rect }
        guard let viewRect = r else { return .zero }

        let clipped = viewRect.intersection(sel)
        guard !clipped.isEmpty else { return .zero }

        // Output CG context is y=0=bottom. Selection bottom (sel.maxY in view) → y=0 in output.
        // Annotation at view clipped.maxY → output y = (sel.maxY - clipped.maxY)*scale.
        return CGRect(
            x: (clipped.minX - sel.minX) * scale,
            y: (sel.maxY - clipped.maxY) * scale,
            width:  clipped.width  * scale,
            height: clipped.height * scale
        )
    }

    private func applyBlur(baseCGImage: CGImage, absolutePixelRect: CGRect, radius: Float) -> CGImage? {
        // Expand source by radius so the blur has real neighbours at all edges (no dark borders).
        let expand = CGFloat(radius)
        let imgBounds = CGRect(x: 0, y: 0,
                               width: CGFloat(baseCGImage.width), height: CGFloat(baseCGImage.height))
        let expanded = absolutePixelRect.insetBy(dx: -expand, dy: -expand).intersection(imgBounds)
        guard !expanded.isEmpty, let cropped = baseCGImage.cropping(to: expanded) else { return nil }

        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(radius, 1), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }

        // Extract just the original rect from the blurred expanded region.
        let innerRect = CGRect(x: absolutePixelRect.minX - expanded.minX,
                               y: absolutePixelRect.minY - expanded.minY,
                               width: absolutePixelRect.width,
                               height: absolutePixelRect.height)
        return Self.ciContext.createCGImage(output, from: innerRect)
    }

    private func applyPixelate(baseCGImage: CGImage, absolutePixelRect: CGRect, scale: Float) -> CGImage? {
        guard let cropped = baseCGImage.cropping(to: absolutePixelRect) else { return nil }
        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(scale, 2), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        let dest = CGRect(origin: .zero, size: CGSize(width: absolutePixelRect.width,
                                                       height: absolutePixelRect.height))
        return Self.ciContext.createCGImage(output, from: dest)
    }
}
