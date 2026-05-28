import AppKit
import CoreImage
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Delegate

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayView(_ view: OverlayView, didFinish image: CGImage,
                     sourceRect: CGRect, scaleFactor: CGFloat)
    func overlayViewDidCancel(_ view: OverlayView)
}

// MARK: - OverlayView

final class OverlayView: NSView {

    weak var delegate: OverlayViewDelegate?
    var viewModel: OverlayViewModel?
    var scWindows: [SCWindow] = []

    private var baseCGImage: CGImage
    private var scaleFactor: CGFloat = 2.0

    private var dragStart: NSPoint?
    private var inProgressAnnotation: Annotation?
    private var liveSelectionRect: NSRect?
    private var hoveredWindowRect: NSRect?
    private var mousePos: NSPoint = .zero
    private var selectedAnnotation: Annotation?
    /// Multi-select set — populated by Shift+click in the select tool.
    private var selectedAnnotations: Set<ObjectIdentifier> = []
    private var moveOrigin: NSPoint?
    private var activeHandle: Int?   // 0-7 = rect handle index, 10-11 = line endpoint index

    // Freehand / Polygon region
    private var freehandPoints: [NSPoint] = []
    private var isPolygonMode: Bool = false   // true = click-to-add-point; false = drag-to-draw
    private var editingTextField: NSTextField?
    private var eraserDidPushUndo = false
    private var editingObserver: NSObjectProtocol?

    init(backgroundImage: CGImage, scaleFactor: CGFloat) {
        self.baseCGImage = backgroundImage
        self.scaleFactor = scaleFactor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func requestFinish() {
        guard let vm = viewModel, let sel = vm.selectionRect else { return }
        // Apply crop if the user set one
        let effectiveSel: NSRect
        if let crop = vm.cropRect {
            let intersection = crop.intersection(sel)
            effectiveSel = intersection.isEmpty ? sel : intersection
        } else {
            effectiveSel = sel
        }
        guard let final = vm.renderFinalImage(baseCGImage: baseCGImage,
                                              selectionRect: effectiveSel,
                                              scaleFactor: scaleFactor) else { return }
        delegate?.overlayView(self, didFinish: final, sourceRect: toScreen(effectiveSel), scaleFactor: scaleFactor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let vm = viewModel else { return }

        drawBackground(in: ctx)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)

        let displaySel = vm.selectionRect ?? liveSelectionRect
        if let sel = displaySel, sel.width > 2, sel.height > 2 {
            drawBackground(in: ctx, clippedTo: sel)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.5)
            ctx.stroke(sel.insetBy(dx: 0.75, dy: 0.75))
            drawHandles(sel, ctx: ctx); drawSizeLabel(sel, showCoords: true)
        } else if let win = hoveredWindowRect, vm.activeTool == .region {
            let winView = toViewRect(win)   // convert Quartz screen coords → flipped view coords
            drawBackground(in: ctx, clippedTo: winView)
            let p = NSBezierPath(rect: winView.insetBy(dx: 1, dy: 1))
            p.lineWidth = 2; NSColor.systemBlue.setStroke(); p.stroke()
            drawSizeLabel(winView)
        }

        // Collect spotlights separately — drawn as a unified overlay at end
        let spotlights = vm.annotations.compactMap { $0 as? SpotlightAnnotation }
        for ann in vm.annotations where !(ann is SpotlightAnnotation) { drawAnnotation(ann) }
        // Draw in-progress annotation only if it is NOT already in vm.annotations (avoids double-draw)
        if let ip = inProgressAnnotation, !(ip is SpotlightAnnotation),
           !vm.annotations.contains(where: { $0 === ip }) { drawAnnotation(ip) }

        // Spotlight overlay (dark with holes)
        var allSpotlights = spotlights
        if let sp = inProgressAnnotation as? SpotlightAnnotation { allSpotlights.append(sp) }
        if !allSpotlights.isEmpty { drawSpotlightOverlay(allSpotlights) }

        // Crop preview overlay
        if let crop = vm.cropRect, !crop.isEmpty {
            if let sel = vm.selectionRect {
                NSGraphicsContext.saveGraphicsState()
                let dimPath = NSBezierPath(rect: sel)
                dimPath.append(NSBezierPath(rect: crop))
                dimPath.windingRule = .evenOdd
                NSColor.black.withAlphaComponent(0.4).setFill()
                dimPath.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.systemYellow.setStroke()
            let cropPath = NSBezierPath(rect: crop)
            cropPath.lineWidth = 2
            cropPath.setLineDash([6, 4], count: 2, phase: 0)
            cropPath.stroke()
        }

        if vm.activeTool == .region {
            // Full-screen crosshair (always, thin)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.5); ctx.beginPath()
            ctx.move(to: .init(x: 0, y: mousePos.y))
            ctx.addLine(to: .init(x: bounds.width, y: mousePos.y))
            ctx.move(to: .init(x: mousePos.x, y: 0))
            ctx.addLine(to: .init(x: mousePos.x, y: bounds.height))
            ctx.strokePath()

            // Magnifier loupe (before final selection)
            if vm.selectionRect == nil {
                drawMagnifier(at: mousePos, in: ctx)
            }
        }

        // Freehand / Polygon region drawing
        if vm.activeTool == .freehand, !freehandPoints.isEmpty {
            drawFreehandOverlay(ctx: ctx)
        }

        // Selection handles for the currently selected annotation (select tool)
        if vm.activeTool == .select {
            // Draw multi-select highlight for all selected annotations
            if !selectedAnnotations.isEmpty {
                for ann in vm.annotations where selectedAnnotations.contains(ObjectIdentifier(ann)) {
                    drawMultiSelectHighlight(for: ann, in: ctx)
                }
            }
            if let sel = selectedAnnotation {
                drawSelectionHandles(for: sel, in: ctx)
            }
        }
    }

    // CGImage from CIImage(cvPixelBuffer:) has row 0 at the BOTTOM (CG / CIImage convention).
    // In an isFlipped NSView, ctx.draw() would put row 0 at the visual top → upside-down.
    // Fix: cancel the view's flip (translate+scale) so the context is back to CG convention
    // (y=0=bottom), then draw. The pre-existing device-space clip from `clip` is unaffected.
    private func drawBackground(in ctx: CGContext, clippedTo clip: CGRect? = nil) {
        ctx.saveGState()
        if let clip { ctx.clip(to: clip) }
        let h = bounds.height
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(baseCGImage, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    private func drawAnnotation(_ ann: Annotation) {
        if let blur = ann as? BlurAnnotation      { drawBlur(blur);     return }
        if let pix  = ann as? PixelateAnnotation  { drawPixelate(pix);  return }
        if let mag  = ann as? MagnifyAnnotation   { drawMagnify(mag);   return }
        ann.drawRotated(in: bounds)
    }

    private func drawBlur(_ ann: BlurAnnotation) {
        guard ann.rect.width > 4, ann.rect.height > 4 else { return }
        let pr = pixelRect(ann.rect)
        guard let cropped = baseCGImage.cropping(to: pr) else { return }
        let ci = CIImage(cgImage: cropped)
        guard let f = CIFilter(name: "CIGaussianBlur") else { return }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(max(ann.radius, 1.0), forKey: kCIInputRadiusKey)
        guard let out = f.outputImage else { return }
        let sz = CGSize(width: pr.width, height: pr.height)
        let shifted = out.transformed(by: .init(translationX: -out.extent.minX, y: -out.extent.minY))
        if let cg = OverlayViewModel.ciContext.createCGImage(shifted, from: CGRect(origin: .zero, size: sz)) {
            NSImage(cgImage: cg, size: ann.rect.size)
                .draw(in: ann.rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    private func drawPixelate(_ ann: PixelateAnnotation) {
        guard ann.rect.width > 4, ann.rect.height > 4 else { return }
        let pr = pixelRect(ann.rect)
        guard let cropped = baseCGImage.cropping(to: pr) else { return }
        let ci = CIImage(cgImage: cropped)
        guard let f = CIFilter(name: "CIPixellate") else { return }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(max(ann.pixelSize * scaleFactor / 2, 2.0), forKey: kCIInputScaleKey)
        guard let out = f.outputImage else { return }
        let sz = CGSize(width: pr.width, height: pr.height)
        if let cg = OverlayViewModel.ciContext.createCGImage(out, from: CGRect(origin: .zero, size: sz)) {
            NSImage(cgImage: cg, size: ann.rect.size)
                .draw(in: ann.rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    private func drawMagnify(_ ann: MagnifyAnnotation) {
        guard ann.rect.width > 4, ann.rect.height > 4 else { return }
        let srcW = ann.rect.width  / ann.scale
        let srcH = ann.rect.height / ann.scale
        let srcRect = NSRect(x: ann.rect.midX - srcW/2, y: ann.rect.midY - srcH/2, width: srcW, height: srcH)
        let pr = pixelRect(srcRect)
        guard let cropped = baseCGImage.cropping(to: pr),
              let ctx = NSGraphicsContext.current?.cgContext else {
            ann.draw(in: bounds); return
        }
        ctx.saveGState()
        NSBezierPath(ovalIn: ann.rect).addClip()
        NSImage(cgImage: cropped, size: ann.rect.size)
            .draw(in: ann.rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()
        // Border
        ann.color.setStroke()
        let border = NSBezierPath(ovalIn: ann.rect)
        border.lineWidth = ann.lineWidth; border.stroke()
    }

    private func drawSpotlightOverlay(_ spotlights: [SpotlightAnnotation]) {
        let fullPath = NSBezierPath(rect: bounds)
        for sp in spotlights { fullPath.append(NSBezierPath(ovalIn: sp.rect)) }
        fullPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.65).setFill()
        fullPath.fill()
        // Stroke border of each spotlight circle
        for sp in spotlights {
            sp.color.setStroke()
            let p = NSBezierPath(ovalIn: sp.rect)
            p.lineWidth = max(sp.lineWidth, 2); p.stroke()
        }
    }

    // Converts a view-coordinate rect (flipped, y=0=top) to a CGImage pixel rect (y=0=bottom).
    private func pixelRect(_ r: NSRect) -> CGRect {
        let imgH = CGFloat(baseCGImage.height)
        return CGRect(x: r.minX * scaleFactor,
                      y: imgH - r.maxY * scaleFactor,
                      width: r.width * scaleFactor,
                      height: r.height * scaleFactor)
    }

    // MARK: - Freehand region

    private func drawFreehandOverlay(ctx: CGContext) {
        guard freehandPoints.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: freehandPoints[0])
        if freehandPoints.count > 2 {
            // Cardinal spline for smooth freehand
            for i in 1..<freehandPoints.count - 1 {
                let p0 = freehandPoints[max(0, i-1)]
                let p1 = freehandPoints[i]
                let p2 = freehandPoints[min(freehandPoints.count-1, i+1)]
                let cp1 = NSPoint(x: p1.x + (p2.x - p0.x)/6, y: p1.y + (p2.y - p0.y)/6)
                let cp2 = NSPoint(x: p2.x - (freehandPoints[min(freehandPoints.count-1, i+2)].x - p1.x)/6,
                                  y: p2.y - (freehandPoints[min(freehandPoints.count-1, i+2)].y - p1.y)/6)
                path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            }
        } else {
            path.line(to: freehandPoints[1])
        }

        // Draw selected area clear + path stroke
        if freehandPoints.count > 3 {
            let closedPath = path.copy() as! NSBezierPath
            closedPath.close()
            NSGraphicsContext.saveGraphicsState()
            closedPath.addClip()
            drawBackground(in: ctx, clippedTo: nil)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Path outline
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.setLineDash([6, 3], count: 2, phase: 0)
        path.stroke()

        // Vertex dots in polygon mode
        if isPolygonMode {
            NSColor.systemBlue.setFill()
            for pt in freehandPoints {
                NSBezierPath(ovalIn: NSRect(x: pt.x-4, y: pt.y-4, width: 8, height: 8)).fill()
            }
        }

        // Closing line preview (polygon mode)
        if isPolygonMode, freehandPoints.count > 2 {
            let closeLine = NSBezierPath()
            closeLine.move(to: freehandPoints.last!); closeLine.line(to: freehandPoints[0])
            NSColor.white.withAlphaComponent(0.4).setStroke()
            closeLine.lineWidth = 1; closeLine.setLineDash([4, 4], count: 2, phase: 0); closeLine.stroke()
        }
    }

    private func finalizeFreehandRegion(vm: OverlayViewModel) {
        guard freehandPoints.count > 2 else { return }
        // Bounding rect of the freehand path → selection rect (ShareX also uses bounding rect)
        let minX = freehandPoints.map(\.x).min()!
        let maxX = freehandPoints.map(\.x).max()!
        let minY = freehandPoints.map(\.y).min()!
        let maxY = freehandPoints.map(\.y).max()!
        let bbox = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard bbox.width > 5, bbox.height > 5 else { freehandPoints = []; return }
        vm.selectionRect = bbox
        freehandPoints = []
        isPolygonMode = false
    }

    private func drawHandles(_ rect: NSRect, ctx: CGContext) {
        let s: CGFloat = 6
        ctx.setFillColor(NSColor.white.cgColor)
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].forEach {
            ctx.fill(CGRect(x: $0.x - s/2, y: $0.y - s/2, width: s, height: s))
        }
    }

    // MARK: - Annotation selection helpers

    /// 8 resize handle rects (TL,TC,TR,MR,BR,BC,BL,ML) in view coords.
    private func handleRects(for r: NSRect) -> [NSRect] {
        let s: CGFloat = 10; let hs = s / 2
        return [
            NSRect(x: r.minX-hs, y: r.minY-hs, width: s, height: s),   // 0 TL
            NSRect(x: r.midX-hs, y: r.minY-hs, width: s, height: s),   // 1 TC
            NSRect(x: r.maxX-hs, y: r.minY-hs, width: s, height: s),   // 2 TR
            NSRect(x: r.maxX-hs, y: r.midY-hs, width: s, height: s),   // 3 MR
            NSRect(x: r.maxX-hs, y: r.maxY-hs, width: s, height: s),   // 4 BR
            NSRect(x: r.midX-hs, y: r.maxY-hs, width: s, height: s),   // 5 BC
            NSRect(x: r.minX-hs, y: r.maxY-hs, width: s, height: s),   // 6 BL
            NSRect(x: r.minX-hs, y: r.midY-hs, width: s, height: s),   // 7 ML
        ]
    }

    /// Returns a bounding rect for rect-based annotations; nil for line/arrow/point-based.
    private func annotationBoundingRect(_ ann: Annotation) -> NSRect? {
        switch ann {
        case let a as RectAnnotation:         return a.rect
        case let a as EllipseAnnotation:      return a.rect
        case let a as HighlightAnnotation:    return a.rect
        case let a as BlurAnnotation:         return a.rect
        case let a as PixelateAnnotation:     return a.rect
        case let a as BlackoutAnnotation:     return a.rect
        case let a as SpeechBalloonAnnotation:return a.rect
        case let a as SpotlightAnnotation:    return a.rect
        case let a as MagnifyAnnotation:      return a.rect
        default: return nil
        }
    }

    private func drawMultiSelectHighlight(for ann: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        if let br = annotationBoundingRect(ann) {
            ctx.stroke(br.insetBy(dx: -2, dy: -2))
        }
        ctx.restoreGState()
    }

    private func drawSelectionHandles(for ann: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)

        if let br = annotationBoundingRect(ann) {
            let c = ann.rotationCenter
            let θ = ann.rotation

            // Dashed selection border — drawn as the rotated quad
            if θ == 0 {
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.stroke(br.insetBy(dx: -1, dy: -1))
                ctx.setLineDash(phase: 0, lengths: [])
            } else {
                // Rotate the four corners and draw the polygon
                let corners = [
                    CGPoint(x: br.minX - 1, y: br.minY - 1),
                    CGPoint(x: br.maxX + 1, y: br.minY - 1),
                    CGPoint(x: br.maxX + 1, y: br.maxY + 1),
                    CGPoint(x: br.minX - 1, y: br.maxY + 1),
                ]
                let rotated = corners.map { rotatePoint(NSPoint(x: $0.x, y: $0.y), around: c, by: θ) }
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.beginPath()
                ctx.move(to: rotated[0]); rotated[1...].forEach { ctx.addLine(to: $0) }
                ctx.closePath(); ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }

            // 8 resize handles (at rotated positions)
            for hr in handleRects(for: br) {
                let rotatedCenter = rotatePoint(NSPoint(x: hr.midX, y: hr.midY), around: c, by: θ)
                let size: CGFloat = hr.width
                let rhr = CGRect(x: rotatedCenter.x - size/2, y: rotatedCenter.y - size/2,
                                 width: size, height: size)
                ctx.fill(rhr)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.stroke(rhr)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            }

            // Rotation handle — circle above the top-centre, offset by rotation
            if ann.isRotatable {
                let topCenter = NSPoint(x: br.midX, y: br.minY - 28)
                let rh = rotatePoint(topCenter, around: c, by: θ)
                let stemEnd = rotatePoint(NSPoint(x: br.midX, y: br.minY), around: c, by: θ)
                // Stem line
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(1)
                ctx.beginPath(); ctx.move(to: stemEnd); ctx.addLine(to: rh); ctx.strokePath()
                // Handle circle
                let hr = CGRect(x: rh.x - 7, y: rh.y - 7, width: 14, height: 14)
                ctx.setFillColor(NSColor.systemOrange.cgColor)
                ctx.fillEllipse(in: hr)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: hr)
            }

        } else if let line = ann as? LineAnnotation {
            for pt in [line.start, line.end] {
                ctx.fill(CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10))
            }
        } else if let arr = ann as? ArrowAnnotation {
            for pt in [arr.start, arr.end] {
                ctx.fill(CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10))
            }
        }
        ctx.restoreGState()
    }

    /// Hit-tests an annotation accounting for its rotation.
    private func hitTestAnnotation(_ ann: Annotation, point: NSPoint) -> Bool {
        guard ann.isRotatable, ann.rotation != 0 else { return ann.hitTest(point) }
        let local = unrotatePoint(point, around: ann.rotationCenter, by: ann.rotation)
        return ann.hitTest(local)
    }

    /// Rotates `point` around `center` by `theta` radians clockwise in screen space
    /// (where y=0 is the top, consistent with NSAffineTransform in a flipped NSView).
    private func rotatePoint(_ point: NSPoint, around center: NSPoint, by theta: CGFloat) -> CGPoint {
        guard theta != 0 else { return point }
        let dx = point.x - center.x, dy = point.y - center.y
        let cos = Foundation.cos(theta), sin = Foundation.sin(theta)
        return CGPoint(
            x: center.x + dx * cos + dy * sin,
            y: center.y - dx * sin + dy * cos
        )
    }

    /// Inverse of `rotatePoint` — used to un-rotate a hit-test point into the annotation's local space.
    private func unrotatePoint(_ point: NSPoint, around center: NSPoint, by theta: CGFloat) -> NSPoint {
        let r = rotatePoint(point, around: center, by: -theta)
        return NSPoint(x: r.x, y: r.y)
    }

    /// Transforms a delta vector (dx, dy) from screen space into the annotation's unrotated local space.
    /// Used when resizing a rotated annotation via a handle drag.
    private func unrotateVec(dx: CGFloat, dy: CGFloat, by theta: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        guard theta != 0 else { return (dx, dy) }
        let cos = Foundation.cos(theta), sin = Foundation.sin(theta)
        // Inverse of the clockwise screen-space rotation formula
        return (dx: dx * cos - dy * sin, dy: dx * sin + dy * cos)
    }

    private func applyRectResize(ann: Annotation, handle: Int, dx: CGFloat, dy: CGFloat,
                                 proportional: Bool = false) {
        func resized(_ r: NSRect) -> NSRect {
            var x = r.minX; var y = r.minY; var w = r.width; var h = r.height
            var ddx = dx, ddy = dy
            // Proportional resize: constrain the larger delta to match aspect ratio
            if proportional {
                let ratio = r.width > 0 ? r.height / r.width : 1
                switch handle {
                case 0, 2, 4, 6: // corners — use whichever axis moved more
                    let bigger = abs(ddx) > abs(ddy) ? abs(ddx) : abs(ddy)
                    ddx = ddx < 0 ? -bigger : bigger
                    ddy = ddy < 0 ? -bigger * ratio : bigger * ratio
                default: break
                }
            }
            switch handle {
            case 0: x += ddx; y += ddy; w -= ddx; h -= ddy   // TL
            case 1:            y += ddy;            h -= ddy   // TC
            case 2:            y += ddy; w += ddx;  h -= ddy   // TR
            case 3:                      w += ddx              // MR
            case 4:                      w += ddx;  h += ddy   // BR
            case 5:                                 h += ddy   // BC
            case 6: x += ddx;            w -= ddx;  h += ddy   // BL
            case 7: x += ddx;            w -= ddx              // ML
            default: break
            }
            return NSRect(x: x, y: y, width: max(8, w), height: max(8, h))
        }
        switch ann {
        case let a as RectAnnotation:         a.rect = resized(a.rect)
        case let a as EllipseAnnotation:      a.rect = resized(a.rect)
        case let a as HighlightAnnotation:    a.rect = resized(a.rect)
        case let a as BlurAnnotation:         a.rect = resized(a.rect)
        case let a as PixelateAnnotation:     a.rect = resized(a.rect)
        case let a as BlackoutAnnotation:     a.rect = resized(a.rect)
        case let a as SpeechBalloonAnnotation:a.rect = resized(a.rect)
        case let a as SpotlightAnnotation:    a.rect = resized(a.rect)
        case let a as MagnifyAnnotation:      a.rect = resized(a.rect)
        default: break
        }
    }

    private func applyLineResize(ann: Annotation, endpointIdx: Int, dx: CGFloat, dy: CGFloat) {
        switch ann {
        case let a as LineAnnotation:
            if endpointIdx == 0 { a.start.x += dx; a.start.y += dy }
            else                { a.end.x   += dx; a.end.y   += dy }
        case let a as ArrowAnnotation:
            if endpointIdx == 0 { a.start.x += dx; a.start.y += dy }
            else                { a.end.x   += dx; a.end.y   += dy }
        default: break
        }
    }

    private func drawSizeLabel(_ rect: NSRect, showCoords: Bool = false) {
        let sf = scaleFactor
        let text: String
        if showCoords {
            text = "X: \(Int(rect.minX * sf))  Y: \(Int(rect.minY * sf))  W: \(Int(rect.width * sf))  H: \(Int(rect.height * sf))"
        } else {
            text = "\(Int(rect.width * sf)) × \(Int(rect.height * sf))"
        }
        let str = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                         .foregroundColor: NSColor.white])
        let sz = str.size(); let pad: CGFloat = 5
        let lx = max(2, min(rect.midX - sz.width/2 - pad, bounds.width - sz.width - pad*2 - 2))
        let ly = rect.maxY + 6 > bounds.height - 24 ? rect.minY - sz.height - 10 : rect.maxY + 6
        let bg = NSBezierPath(roundedRect: NSRect(x: lx, y: ly, width: sz.width+pad*2, height: sz.height+pad),
                              xRadius: 4, yRadius: 4)
        NSColor(white: 0, alpha: 0.7).setFill()
        bg.fill()
        str.draw(at: NSPoint(x: lx + pad, y: ly + pad/2))
    }

    // ShareX-style pixel magnifier with coordinate readout.
    // Crops pixelCount×pixelCount pixels from baseCGImage around the cursor,
    // scales them up with nearest-neighbor, overlays a grid and crosshair.
    private func drawMagnifier(at pos: NSPoint, in ctx: CGContext) {
        let pixelCount = 11          // source pixels per side (must be odd)
        let zoom: CGFloat = 8        // each source pixel → zoom×zoom points
        let half = pixelCount / 2    // = 5
        let magW = CGFloat(pixelCount) * zoom   // 88
        let magH = CGFloat(pixelCount) * zoom

        // Crop region in CGImage coords: x = pos.x*sf, y = imgH - pos.y*sf (y=0=bottom)
        let cx = (pos.x * scaleFactor).rounded()
        let imgW = CGFloat(baseCGImage.width)
        let imgH = CGFloat(baseCGImage.height)
        let cy = (imgH - pos.y * scaleFactor).rounded()   // flip: view y=0=top → CGImage y=0=bottom
        let srcRect = CGRect(x: max(0, cx - CGFloat(half)),
                             y: max(0, cy - CGFloat(half)),
                             width: CGFloat(pixelCount),
                             height: CGFloat(pixelCount))
            .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard let cropped = baseCGImage.cropping(to: srcRect) else { return }

        // Position near cursor; flip sides to stay on screen
        let gap: CGFloat = 20
        let labelH: CGFloat = 22
        var mx = pos.x + gap
        var my = pos.y + gap
        if mx + magW > bounds.width  - 8 { mx = pos.x - gap - magW }
        if my + magH + labelH > bounds.height - 8 { my = pos.y - gap - magH - labelH }
        let magRect = CGRect(x: mx, y: my, width: magW, height: magH)

        // ── Draw zoomed pixels (nearest-neighbor) ──────────────────────────
        // CGImage row 0=bottom; cancel the view flip so ctx.draw renders correctly.
        ctx.saveGState()
        ctx.clip(to: magRect)      // clip in flipped view coords (device-space clip)
        ctx.interpolationQuality = .none
        let bh = bounds.height
        ctx.translateBy(x: 0, y: bh); ctx.scaleBy(x: 1, y: -1)
        // magRect in new CG coords: origin = (mx, bh-my-magH)
        ctx.draw(cropped, in: CGRect(x: mx, y: bh - my - magH, width: magW, height: magH))
        ctx.restoreGState()

        // ── Grid lines ─────────────────────────────────────────────────────
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<pixelCount {
            let x = mx + CGFloat(i) * zoom
            ctx.move(to: CGPoint(x: x, y: my)); ctx.addLine(to: CGPoint(x: x, y: my + magH))
        }
        for i in 1..<pixelCount {
            let y = my + CGFloat(i) * zoom
            ctx.move(to: CGPoint(x: mx, y: y)); ctx.addLine(to: CGPoint(x: mx + magW, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // ── Center crosshair bars (light-blue tint, ShareX style) ──────────
        let cpx = mx + CGFloat(half) * zoom
        let cpy = my + CGFloat(half) * zoom
        ctx.saveGState()
        ctx.setFillColor(NSColor(red: 0.6, green: 0.88, blue: 1.0, alpha: 0.45).cgColor)
        ctx.fill(CGRect(x: mx, y: cpy, width: cpx - mx, height: zoom))             // left
        ctx.fill(CGRect(x: cpx + zoom, y: cpy, width: mx + magW - cpx - zoom, height: zoom)) // right
        ctx.fill(CGRect(x: cpx, y: my, width: zoom, height: cpy - my))             // top
        ctx.fill(CGRect(x: cpx, y: cpy + zoom, width: zoom, height: my + magH - cpy - zoom)) // bottom
        ctx.restoreGState()

        // ── Center pixel highlight (black outer + white inner border) ───────
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1.5)
        ctx.stroke(CGRect(x: cpx - 1, y: cpy - 1, width: zoom + 2, height: zoom + 2))
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: cpx, y: cpy, width: zoom - 1, height: zoom - 1))
        ctx.restoreGState()

        // ── Magnifier border (white 2pt outer, black 1pt inner) ────────────
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2)
        ctx.stroke(magRect.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1)
        ctx.stroke(magRect)
        ctx.restoreGState()

        // ── Coordinate label below magnifier ───────────────────────────────
        let screenX = Int(pos.x * scaleFactor)
        let screenY = Int(pos.y * scaleFactor)
        let coordStr = NSAttributedString(
            string: "X: \(screenX)  Y: \(screenY)",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                         .foregroundColor: NSColor.white])
        let csz = coordStr.size(); let cpad: CGFloat = 4
        let lbX = mx + (magW - csz.width) / 2 - cpad
        let lbY = my + magH + 3
        let lbBg = NSRect(x: lbX, y: lbY, width: csz.width + cpad * 2, height: csz.height + cpad)
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: lbBg, xRadius: 3, yRadius: 3).fill()
        coordStr.draw(at: NSPoint(x: lbX + cpad, y: lbY + cpad / 2))
    }

    override func mouseDown(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let pt = convert(event.locationInWindow, from: nil)
        dragStart = pt

        // Double-click: finalize capture or close polygon
        if event.clickCount == 2 {
            if vm.activeTool == .region, vm.selectionRect != nil {
                requestFinish(); return
            }
            if vm.activeTool == .freehand, isPolygonMode, freehandPoints.count > 2 {
                finalizeFreehandRegion(vm: vm); return
            }
        }

        // Freehand: Shift key → polygon mode (click-to-add vertices)
        if vm.activeTool == .freehand {
            isPolygonMode = event.modifierFlags.contains(.shift)
        }

        switch vm.activeTool {
        case .freehand:
            if isPolygonMode {
                // Polygon mode: each click adds a vertex (Shift was pressed at start)
                freehandPoints.append(pt)
            } else {
                // Freehand mode: drag draws free path
                freehandPoints = [pt]
            }
        case .region:
            liveSelectionRect = nil; hoveredWindowRect = nil
        case .select:
            // Check if clicking on a resize/endpoint/rotation handle of the currently selected annotation
            activeHandle = nil
            if let sel = selectedAnnotation {
                if let br = annotationBoundingRect(sel) {
                    let c = sel.rotationCenter; let θ = sel.rotation
                    // Rotation handle check (index 20) — must come before resize handles
                    if sel.isRotatable {
                        let rotHandleCenter = rotatePoint(NSPoint(x: br.midX, y: br.minY - 28), around: c, by: θ)
                        if hypot(pt.x - rotHandleCenter.x, pt.y - rotHandleCenter.y) < 10 {
                            activeHandle = 20; moveOrigin = pt; needsDisplay = true; return
                        }
                    }
                    // Resize handle check — un-rotate the click into annotation local space first
                    let localPt = unrotatePoint(pt, around: c, by: θ)
                    if let hi = handleRects(for: br).firstIndex(where: { $0.contains(localPt) }) {
                        activeHandle = hi; moveOrigin = pt; needsDisplay = true; return
                    }
                } else if let line = sel as? LineAnnotation {
                    let handles = [NSRect(x: line.start.x-5, y: line.start.y-5, width: 10, height: 10),
                                   NSRect(x: line.end.x-5, y: line.end.y-5, width: 10, height: 10)]
                    if let hi = handles.firstIndex(where: { $0.contains(pt) }) {
                        activeHandle = hi + 10; moveOrigin = pt; needsDisplay = true; return
                    }
                } else if let arr = sel as? ArrowAnnotation {
                    let handles = [NSRect(x: arr.start.x-5, y: arr.start.y-5, width: 10, height: 10),
                                   NSRect(x: arr.end.x-5, y: arr.end.y-5, width: 10, height: 10)]
                    if let hi = handles.firstIndex(where: { $0.contains(pt) }) {
                        activeHandle = hi + 10; moveOrigin = pt; needsDisplay = true; return
                    }
                }
            }
            // Hit test with rotation-aware lookup
            let hit = vm.annotations.last(where: { hitTestAnnotation($0, point: pt) })
            if event.modifierFlags.contains(.shift), let h = hit {
                // Shift+click: toggle membership in multi-selection
                let id = ObjectIdentifier(h)
                if selectedAnnotations.contains(id) { selectedAnnotations.remove(id) }
                else { selectedAnnotations.insert(id) }
                // Keep selectedAnnotation on the last-clicked for handle display
                selectedAnnotation = h
            } else {
                selectedAnnotations.removeAll()
                selectedAnnotation = hit
            }
            moveOrigin = pt
        case .freehandArrow:
            let fa = FreehandArrowAnnotation(color: vm.strokeColor, lineWidth: vm.lineWidth)
            fa.addPoint(pt); vm.pushUndo(); vm.annotations.append(fa)
        case .text:
            beginTextInput(at: pt, vm: vm)
        case .textOutline:
            beginTextOutlineInput(at: pt, vm: vm)
        case .textBackground:
            beginTextBackgroundInput(at: pt, vm: vm)
        case .step:
            // Place the step and keep a reference so drag can attach a leader line
            let step = StepAnnotation(center: pt, number: vm.nextStepNumber, color: vm.strokeColor)
            vm.addAnnotation(step)
            inProgressAnnotation = step   // reuse inProgressAnnotation to track during drag
        case .rect:
            inProgressAnnotation = RectAnnotation(rect: .init(origin: pt, size: .zero),
                                                  color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .ellipse:
            inProgressAnnotation = EllipseAnnotation(rect: .init(origin: pt, size: .zero),
                                                     color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .line:
            inProgressAnnotation = LineAnnotation(start: pt, end: pt,
                                                  color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .arrow:
            inProgressAnnotation = ArrowAnnotation(start: pt, end: pt,
                                                   color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .highlight:
            inProgressAnnotation = HighlightAnnotation(rect: .init(origin: pt, size: .zero),
                                                       color: vm.strokeColor, opacity: vm.highlightOpacity)
        case .pen:
            let pen = PenAnnotation(color: vm.strokeColor, lineWidth: vm.lineWidth)
            pen.addPoint(pt); vm.pushUndo(); vm.annotations.append(pen)
            inProgressAnnotation = nil
        case .ruler:
            inProgressAnnotation = RulerAnnotation(start: pt, end: pt, color: vm.strokeColor,
                                                   lineWidth: vm.lineWidth, scaleFactor: scaleFactor)
        case .blur:
            inProgressAnnotation = BlurAnnotation(rect: .init(origin: pt, size: .zero),
                                                  radius: vm.blurRadius)
        case .pixelate:
            inProgressAnnotation = PixelateAnnotation(rect: .init(origin: pt, size: .zero),
                                                      pixelSize: vm.pixelateSize)
        case .blackout:
            inProgressAnnotation = BlackoutAnnotation(rect: .init(origin: pt, size: .zero))
        case .speechBalloon:
            inProgressAnnotation = SpeechBalloonAnnotation(
                rect: .init(origin: pt, size: .zero), color: vm.strokeColor, fontSize: vm.fontSize)
        case .spotlight:
            inProgressAnnotation = SpotlightAnnotation(
                rect: .init(origin: pt, size: .zero), color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .magnify:
            inProgressAnnotation = MagnifyAnnotation(
                rect: .init(origin: pt, size: .zero),
                scale: vm.magnifyScale, color: vm.strokeColor, lineWidth: vm.lineWidth)
        case .emoji:
            beginEmojiInput(at: pt, vm: vm)
        case .cursor:
            vm.addAnnotation(CursorAnnotation(origin: pt, size: vm.cursorSize))
        case .image:
            openImagePicker(at: pt, vm: vm)
        case .crop:
            vm.cropRect = nil
        case .eraser:
            if !eraserDidPushUndo { vm.pushUndo(); eraserDidPushUndo = true }
            eraseAnnotation(at: pt, vm: vm)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let cur = convert(event.locationInWindow, from: nil)

        switch vm.activeTool {
        case .freehand:
            if !isPolygonMode {
                // Freehand drag: add smoothed points
                let last = freehandPoints.last ?? cur
                let dist = hypot(cur.x - last.x, cur.y - last.y)
                if dist > 3 { freehandPoints.append(cur) }
            } else {
                // Polygon: update the "rubber-band" last point while dragging
                if freehandPoints.count > 1 { freehandPoints[freehandPoints.count - 1] = cur }
            }
        case .region:
            if let s = dragStart { liveSelectionRect = makeRect(s, cur) }
        case .select:
            guard let ann = selectedAnnotation, let o = moveOrigin else { break }
            let dx = cur.x - o.x; let dy = cur.y - o.y; moveOrigin = cur
            if let h = activeHandle {
                if h == 20 {
                    // Rotation handle: compute visual clockwise angle from center → mouse
                    let c = ann.rotationCenter
                    ann.rotation = atan2(cur.y - c.y, cur.x - c.x) + .pi / 2
                } else if h < 10 {
                    // Resize in annotation-local (unrotated) space
                    let localDelta = unrotateVec(dx: dx, dy: dy, by: ann.rotation)
                    applyRectResize(ann: ann, handle: h, dx: localDelta.dx, dy: localDelta.dy,
                                    proportional: event.modifierFlags.contains(.shift))
                } else {
                    applyLineResize(ann: ann, endpointIdx: h - 10, dx: dx, dy: dy)
                }
            } else {
                moveAnnotation(ann, dx: dx, dy: dy)
                // Also move all other annotations in the multi-selection
                if !selectedAnnotations.isEmpty {
                    for other in vm.annotations
                        where ObjectIdentifier(other) != ObjectIdentifier(ann) &&
                              selectedAnnotations.contains(ObjectIdentifier(other)) {
                        moveAnnotation(other, dx: dx, dy: dy)
                    }
                }
            }
        case .rect:
            if let s = dragStart {
                let r = event.modifierFlags.contains(.shift) ? makeSquare(s, cur) : makeRect(s, cur)
                inProgressAnnotation = RectAnnotation(rect: r, color: vm.strokeColor, lineWidth: vm.lineWidth)
            }
        case .ellipse:
            if let s = dragStart {
                let r = event.modifierFlags.contains(.shift) ? makeSquare(s, cur) : makeRect(s, cur)
                inProgressAnnotation = EllipseAnnotation(rect: r, color: vm.strokeColor, lineWidth: vm.lineWidth)
            }
        case .line:
            if let s = dragStart {
                let end = event.modifierFlags.contains(.shift) ? angleSnapped(from: s, to: cur) : cur
                inProgressAnnotation = LineAnnotation(start: s, end: end, color: vm.strokeColor, lineWidth: vm.lineWidth)
            }
        case .arrow:
            if let s = dragStart {
                let end = event.modifierFlags.contains(.shift) ? angleSnapped(from: s, to: cur) : cur
                inProgressAnnotation = ArrowAnnotation(start: s, end: end, color: vm.strokeColor, lineWidth: vm.lineWidth)
            }
        case .highlight:
            if let s = dragStart { inProgressAnnotation = HighlightAnnotation(rect: makeRect(s, cur), color: vm.strokeColor, opacity: vm.highlightOpacity) }
        case .ruler:
            if let s = dragStart {
                let end = event.modifierFlags.contains(.shift) ? angleSnapped(from: s, to: cur) : cur
                inProgressAnnotation = RulerAnnotation(start: s, end: end, color: vm.strokeColor,
                                                       lineWidth: vm.lineWidth, scaleFactor: scaleFactor)
            }
        case .pen:
            (vm.annotations.last as? PenAnnotation)?.addPoint(cur)
        case .freehandArrow:
            (vm.annotations.last as? FreehandArrowAnnotation)?.addPoint(cur)
        case .blur:
            if let s = dragStart { inProgressAnnotation = BlurAnnotation(rect: makeRect(s, cur), radius: vm.blurRadius) }
        case .pixelate:
            if let s = dragStart { inProgressAnnotation = PixelateAnnotation(rect: makeRect(s, cur), pixelSize: vm.pixelateSize) }
        case .blackout:
            if let s = dragStart { inProgressAnnotation = BlackoutAnnotation(rect: makeRect(s, cur)) }
        case .speechBalloon:
            if let s = dragStart { inProgressAnnotation = SpeechBalloonAnnotation(
                rect: makeRect(s, cur), color: vm.strokeColor, fontSize: vm.fontSize) }
        case .spotlight:
            if let s = dragStart { inProgressAnnotation = SpotlightAnnotation(
                rect: makeRect(s, cur), color: vm.strokeColor, lineWidth: vm.lineWidth) }
        case .magnify:
            if let s = dragStart { inProgressAnnotation = MagnifyAnnotation(
                rect: makeRect(s, cur), scale: vm.magnifyScale, color: vm.strokeColor, lineWidth: vm.lineWidth) }
        case .crop:
            if let s = dragStart, let sel = vm.selectionRect {
                let raw = makeRect(s, cur)
                let clipped = raw.intersection(sel)
                vm.cropRect = clipped.isEmpty ? nil : clipped
            }
        case .eraser:
            eraseAnnotation(at: cur, vm: vm)
        case .step:
            // Drag from the just-placed step to set a leader line tip
            (inProgressAnnotation as? StepAnnotation)?.leaderEnd = cur
        case .text, .textOutline, .textBackground, .emoji, .cursor, .image: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let vm = viewModel else { return }
        switch vm.activeTool {
        case .freehand:
            if !isPolygonMode, freehandPoints.count > 3 {
                finalizeFreehandRegion(vm: vm)
            }
        case .region:
            if let live = liveSelectionRect, live.width > 5, live.height > 5 {
                vm.selectionRect = live
            } else if let win = hoveredWindowRect {
                vm.selectionRect = toViewRect(win)
                if vm.windowPickerMode { requestFinish(); return }
            }
            liveSelectionRect = nil
        case .select:
            moveOrigin = nil; activeHandle = nil
        case .pen, .freehandArrow:
            break
        case .ruler, .rect, .ellipse, .line, .arrow, .highlight, .blur, .pixelate, .blackout, .spotlight, .magnify:
            if let ann = inProgressAnnotation {
                vm.addAnnotation(ann)
                // Auto-select the just-placed annotation so it can be immediately resized
                selectedAnnotation = ann
                vm.activeTool = .select
            }
            inProgressAnnotation = nil
        case .speechBalloon:
            if let ann = inProgressAnnotation as? SpeechBalloonAnnotation,
               ann.rect.width > 20, ann.rect.height > 20 {
                vm.addAnnotation(ann)
                beginBalloonTextInput(balloon: ann, vm: vm)
                selectedAnnotation = ann; vm.activeTool = .select
            }
            inProgressAnnotation = nil
        case .eraser:
            eraserDidPushUndo = false
        case .step:
            inProgressAnnotation = nil   // leader drag finished
        case .text, .textOutline, .textBackground, .emoji, .cursor, .image, .crop:
            break
        }
        dragStart = nil; needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mousePos = convert(event.locationInWindow, from: nil)
        if viewModel?.activeTool == .region { updateHoveredWindow() }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { delegate?.overlayViewDidCancel(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // ESC
            if editingTextField != nil { window?.makeFirstResponder(self) }
            else { delegate?.overlayViewDidCancel(self) }
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 { requestFinish(); return }  // Return
        if (event.keyCode == 51 || event.keyCode == 117), let vm = viewModel {
            vm.pushUndo()
            if !selectedAnnotations.isEmpty {
                vm.annotations.removeAll { selectedAnnotations.contains(ObjectIdentifier($0)) }
                selectedAnnotations.removeAll()
                selectedAnnotation = nil
            } else if let sel = selectedAnnotation {
                vm.annotations.removeAll { $0 === sel }
                selectedAnnotation = nil
            }
            needsDisplay = true; return
        }
        super.keyDown(with: event)
    }

    private func beginTextInput(at pt: NSPoint, vm: OverlayViewModel) {
        guard editingTextField == nil else { return }
        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y, width: 200, height: 32))
        field.isBordered = true; field.backgroundColor = NSColor(white:0,alpha:0.5)
        field.textColor = vm.strokeColor
        field.font = NSFont.systemFont(ofSize: vm.fontSize, weight: .semibold)
        field.placeholderString = "Type…"; field.focusRingType = .none
        addSubview(field); editingTextField = field; window?.makeFirstResponder(field)
        editingObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: field, queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview(); self.editingTextField = nil
            if !text.isEmpty {
                vm.addAnnotation(TextAnnotation(origin: pt, text: text,
                                                color: vm.strokeColor, fontSize: vm.fontSize))
            }
            self.needsDisplay = true
            if let obs = self.editingObserver { NotificationCenter.default.removeObserver(obs) }
            self.editingObserver = nil
        }
    }

    private func beginTextOutlineInput(at pt: NSPoint, vm: OverlayViewModel) {
        guard editingTextField == nil else { return }
        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y, width: 200, height: 32))
        field.isBordered = true; field.backgroundColor = NSColor(white: 0, alpha: 0.5)
        field.textColor = vm.strokeColor
        field.font = NSFont.systemFont(ofSize: vm.fontSize, weight: .semibold)
        field.placeholderString = "Outlined text…"; field.focusRingType = .none
        addSubview(field); editingTextField = field; window?.makeFirstResponder(field)
        editingObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: field, queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview(); self.editingTextField = nil
            if !text.isEmpty {
                vm.addAnnotation(TextOutlineAnnotation(origin: pt, text: text, color: vm.strokeColor, fontSize: vm.fontSize))
            }
            self.needsDisplay = true
            if let obs = self.editingObserver { NotificationCenter.default.removeObserver(obs) }
            self.editingObserver = nil
        }
    }

    private func beginTextBackgroundInput(at pt: NSPoint, vm: OverlayViewModel) {
        guard editingTextField == nil else { return }
        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y, width: 200, height: 32))
        field.isBordered = true; field.backgroundColor = NSColor(white: 0, alpha: 0.5)
        field.textColor = vm.strokeColor
        field.font = NSFont.systemFont(ofSize: vm.fontSize, weight: .semibold)
        field.placeholderString = "Background text…"; field.focusRingType = .none
        addSubview(field); editingTextField = field; window?.makeFirstResponder(field)
        editingObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: field, queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview(); self.editingTextField = nil
            if !text.isEmpty {
                // Background is complementary to stroke: dark label ↔ light bg
                let bg: NSColor = vm.strokeColor.isLight ? .black : .white
                vm.addAnnotation(TextBackgroundAnnotation(origin: pt, text: text, color: vm.strokeColor,
                                                          fontSize: vm.fontSize, backgroundColor: bg))
            }
            self.needsDisplay = true
            if let obs = self.editingObserver { NotificationCenter.default.removeObserver(obs) }
            self.editingObserver = nil
        }
    }

    private func beginBalloonTextInput(balloon: SpeechBalloonAnnotation, vm: OverlayViewModel) {
        guard editingTextField == nil else { return }
        let pad: CGFloat = 10
        let fieldRect = balloon.rect.insetBy(dx: pad, dy: pad)
        let field = NSTextField(frame: fieldRect)
        field.isBordered = false; field.drawsBackground = false
        field.textColor = balloon.color
        field.font = NSFont.systemFont(ofSize: balloon.fontSize, weight: .regular)
        field.placeholderString = "Type…"; field.focusRingType = .none
        addSubview(field); editingTextField = field; window?.makeFirstResponder(field)
        editingObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: field, queue: .main
        ) { [weak self, weak field, weak balloon] _ in
            guard let self, let field, let balloon else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                vm.undo()
            } else {
                balloon.text = text
            }
            field.removeFromSuperview(); self.editingTextField = nil
            self.needsDisplay = true
            if let obs = self.editingObserver { NotificationCenter.default.removeObserver(obs) }
            self.editingObserver = nil
        }
    }

    private func updateHoveredWindow() {
        guard let w = window else { hoveredWindowRect = nil; return }
        let sp = w.convertToScreen(NSRect(origin: mousePos.unflipped(in: bounds), size: .zero)).origin
        // SCK returns windows front-to-back — first match is topmost
        let hit = scWindows.first { $0.frame.contains(sp) && $0.frame.width > 10 }
        hoveredWindowRect = hit.map { $0.frame }
    }

    private func moveAnnotation(_ ann: Annotation, dx: CGFloat, dy: CGFloat) {
        switch ann {
        case let r as RectAnnotation:      r.rect   = r.rect.offsetBy(dx: dx, dy: dy)
        case let e as EllipseAnnotation:   e.rect   = e.rect.offsetBy(dx: dx, dy: dy)
        case let a as ArrowAnnotation:     a.start  = .init(x: a.start.x+dx, y: a.start.y+dy); a.end = .init(x: a.end.x+dx, y: a.end.y+dy)
        case let l as LineAnnotation:      l.start  = .init(x: l.start.x+dx, y: l.start.y+dy); l.end = .init(x: l.end.x+dx, y: l.end.y+dy)
        case let ru as RulerAnnotation:    ru.start = .init(x: ru.start.x+dx, y: ru.start.y+dy); ru.end = .init(x: ru.end.x+dx, y: ru.end.y+dy)
        case let t as TextAnnotation:           t.origin = .init(x: t.origin.x+dx, y: t.origin.y+dy)
        case let t as TextOutlineAnnotation:    t.origin = .init(x: t.origin.x+dx, y: t.origin.y+dy)
        case let t as TextBackgroundAnnotation: t.origin = .init(x: t.origin.x+dx, y: t.origin.y+dy)
        case let h as HighlightAnnotation: h.rect   = h.rect.offsetBy(dx: dx, dy: dy)
        case let p as PenAnnotation:       p.points = p.points.map { .init(x: $0.x+dx, y: $0.y+dy) }
        case let s as StepAnnotation:      s.center = .init(x: s.center.x+dx, y: s.center.y+dy)
        case let b as BlurAnnotation:           b.rect = b.rect.offsetBy(dx: dx, dy: dy)
        case let x as PixelateAnnotation:       x.rect = x.rect.offsetBy(dx: dx, dy: dy)
        case let k as BlackoutAnnotation:       k.rect = k.rect.offsetBy(dx: dx, dy: dy)
        case let sb as SpeechBalloonAnnotation: sb.rect = sb.rect.offsetBy(dx: dx, dy: dy)
        case let sp as SpotlightAnnotation:     sp.rect = sp.rect.offsetBy(dx: dx, dy: dy)
        case let m as MagnifyAnnotation:        m.rect  = m.rect.offsetBy(dx: dx, dy: dy)
        case let em as EmojiAnnotation:         em.origin = .init(x: em.origin.x+dx, y: em.origin.y+dy)
        case let cu as CursorAnnotation:        cu.origin = .init(x: cu.origin.x+dx, y: cu.origin.y+dy)
        case let im as ImageAnnotation:         im.origin = .init(x: im.origin.x+dx, y: im.origin.y+dy)
        default: break
        }
    }

    private func beginEmojiInput(at pt: NSPoint, vm: OverlayViewModel) {
        guard editingTextField == nil else { return }
        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y, width: 80, height: CGFloat(vm.emojiSize) + 16))
        field.isBordered = true
        field.backgroundColor = NSColor(white: 0, alpha: 0.5)
        field.textColor = .white
        field.font = NSFont.systemFont(ofSize: vm.emojiSize)
        field.placeholderString = "🙂"
        field.focusRingType = .none
        field.alignment = .center
        addSubview(field); editingTextField = field; window?.makeFirstResponder(field)
        editingObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: field, queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview(); self.editingTextField = nil
            if !text.isEmpty {
                vm.addAnnotation(EmojiAnnotation(origin: pt, emoji: text, fontSize: vm.emojiSize))
            }
            self.needsDisplay = true
            if let obs = self.editingObserver { NotificationCenter.default.removeObserver(obs) }
            self.editingObserver = nil
        }
    }

    /// Smart Eraser: radius-based brush that trims pen/freehandArrow strokes point-by-point;
    /// fully removes other annotation types if the brush center hits them.
    private func eraseAnnotation(at pt: NSPoint, vm: OverlayViewModel, radius: CGFloat = 16) {
        var didChange = false

        vm.annotations = vm.annotations.compactMap { ann -> Annotation? in
            // Pen stroke — remove points inside the eraser circle
            if let pen = ann as? PenAnnotation {
                let before = pen.points.count
                pen.points = pen.points.filter { hypot($0.x - pt.x, $0.y - pt.y) > radius }
                if pen.points.count != before { didChange = true }
                return pen.points.count > 1 ? pen : nil
            }
            // Freehand arrow — same treatment
            if let fa = ann as? FreehandArrowAnnotation {
                let before = fa.points.count
                fa.points = fa.points.filter { hypot($0.x - pt.x, $0.y - pt.y) > radius }
                if fa.points.count != before { didChange = true }
                return fa.points.count > 1 ? fa : nil
            }
            // All other annotations — whole-annotation erase if hit
            if ann.hitTest(pt) { didChange = true; return nil }
            return ann
        }

        if didChange { needsDisplay = true }
    }

    private func openImagePicker(at pt: NSPoint, vm: OverlayViewModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url,
                  let img = NSImage(contentsOf: url) else { return }
            Task { @MainActor [weak self, weak vm] in
                guard let self, let vm else { return }
                vm.addAnnotation(ImageAnnotation(origin: pt, image: img))
                self.needsDisplay = true
            }
        }
    }

    private func toScreen(_ r: NSRect) -> CGRect {
        guard let w = window else { return r }
        return w.convertToScreen(NSRect(x: r.minX, y: bounds.height - r.maxY,
                                        width: r.width, height: r.height))
    }

    private func toViewRect(_ s: CGRect) -> NSRect {
        guard let w = window else { return s }
        let l = CGRect(x: s.minX - w.frame.minX, y: s.minY - w.frame.minY,
                       width: s.width, height: s.height)
        return NSRect(x: l.minX, y: bounds.height - l.maxY, width: l.width, height: l.height)
    }

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(b.x-a.x), height: abs(b.y-a.y))
    }

    /// Square-constrained rect (Shift key for rect/ellipse).
    private func makeSquare(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        let side = min(abs(b.x - a.x), abs(b.y - a.y))
        let x = b.x >= a.x ? a.x : a.x - side
        let y = b.y >= a.y ? a.y : a.y - side
        return NSRect(x: x, y: y, width: side, height: side)
    }

    /// Snaps `to` to the nearest 45° direction from `from` (Shift-constrained line/arrow).
    private func angleSnapped(from a: NSPoint, to b: NSPoint) -> NSPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return b }
        let angle = atan2(dy, dx)
        let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
        return NSPoint(x: a.x + len * cos(snapped), y: a.y + len * sin(snapped))
    }
}

private extension NSPoint {
    func unflipped(in bounds: NSRect) -> NSPoint { NSPoint(x: x, y: bounds.height - y) }
}

private extension NSColor {
    /// Returns true when the perceived luminance is above 0.5 (i.e. colour is light).
    var isLight: Bool {
        guard let c = usingColorSpace(.deviceRGB) else { return false }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.5
    }
}

