import AppKit
import ScreenCaptureKit

// MARK: - Delegate

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// User finished dragging a free selection.
    func overlayView(_ view: OverlayView, didSelectRect rect: CGRect)
    /// User clicked (no drag) on a detected window.
    func overlayView(_ view: OverlayView, didSelectWindowFrame frame: CGRect)
    /// User pressed Escape or right-clicked.
    func overlayViewDidCancel(_ view: OverlayView)
}

// MARK: - OverlayView

/// Full-screen NSView that renders a frozen screenshot and handles region / window selection.
///
/// Coordinate system: `isFlipped = true` so (0,0) is the top-left corner of the display.
final class OverlayView: NSView {

    // MARK: Configuration

    weak var delegate: OverlayViewDelegate?
    /// On-screen windows passed from SCShareableContent, used for grid highlight.
    var scWindows: [SCWindow] = []

    // MARK: Private state

    private let backgroundImage: NSImage
    private var dragStart: NSPoint?
    private var selectionRect: NSRect?        // live drag rect (view coords)
    private var hoveredWindowRect: NSRect?    // window rect in view coords
    private var mousePos: NSPoint = .zero

    // MARK: Init

    init(backgroundImage: CGImage) {
        self.backgroundImage = NSImage(cgImage: backgroundImage, size: .zero)
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Frozen screenshot
        backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

        // 2. Dim
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)

        if let sel = selectionRect, sel.width > 2, sel.height > 2 {
            // 3a. Punch through dim for selection
            ctx.saveGState()
            ctx.clip(to: sel)
            backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            ctx.restoreGState()

            // 3b. Selection border
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(sel.insetBy(dx: 0.75, dy: 0.75))

            // 3c. Corner handles
            drawHandles(sel, ctx: ctx)

            // 3d. Size label (above selection)
            drawSizeLabel(sel)

        } else if let win = hoveredWindowRect {
            // 4. Window hover highlight
            ctx.saveGState()
            ctx.clip(to: win)
            backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            ctx.restoreGState()

            let winPath = NSBezierPath(rect: win.insetBy(dx: 1, dy: 1))
            winPath.lineWidth = 2
            NSColor.systemBlue.setStroke()
            winPath.stroke()

            drawSizeLabel(win)
        }

        // 5. Crosshair (only when not mid-drag)
        if dragStart == nil {
            drawCrosshair(at: mousePos, ctx: ctx)
        }
    }

    // MARK: - Draw helpers

    private func drawHandles(_ rect: NSRect, ctx: CGContext) {
        let s: CGFloat = 6
        let corners: [CGPoint] = [
            .init(x: rect.minX, y: rect.minY), .init(x: rect.maxX, y: rect.minY),
            .init(x: rect.minX, y: rect.maxY), .init(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for c in corners {
            ctx.fill(CGRect(x: c.x - s/2, y: c.y - s/2, width: s, height: s))
        }
    }

    private func drawSizeLabel(_ rect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2.0
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size()
        let pad: CGFloat = 5
        let lx = max(2, min(rect.midX - sz.width / 2 - pad, bounds.width - sz.width - pad * 2 - 2))
        // Place label below selection when near top, otherwise above
        let ly = rect.maxY + 6 > bounds.height - 24 ? rect.minY - sz.height - 10 : rect.maxY + 6

        let bg = NSRect(x: lx, y: ly, width: sz.width + pad * 2, height: sz.height + pad)
        let pill = NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4)
        NSColor(white: 0, alpha: 0.7).setFill()
        pill.fill()
        str.draw(at: NSPoint(x: lx + pad, y: ly + pad / 2))
    }

    private func drawCrosshair(at p: NSPoint, ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(0.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: p.y));           ctx.addLine(to: CGPoint(x: bounds.width, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: 0));           ctx.addLine(to: CGPoint(x: p.x, y: bounds.height))
        ctx.strokePath()
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        hoveredWindowRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let cur = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(start.x, cur.x), y: min(start.y, cur.y),
            width: abs(cur.x - start.x), height: abs(cur.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; selectionRect = nil; hoveredWindowRect = nil }

        if let sel = selectionRect, sel.width > 5, sel.height > 5 {
            delegate?.overlayView(self, didSelectRect: toScreen(sel))
        } else if let win = hoveredWindowRect {
            delegate?.overlayView(self, didSelectWindowFrame: toScreen(win))
        }
        // tap without movement → cancel
        else {
            delegate?.overlayViewDidCancel(self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mousePos = convert(event.locationInWindow, from: nil)
        updateHoveredWindow()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayViewDidCancel(self)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { return } // Escape
        delegate?.overlayViewDidCancel(self)
    }

    // MARK: - Window grid detection

    private func updateHoveredWindow() {
        guard dragStart == nil, let nsWin = window else {
            hoveredWindowRect = nil; return
        }
        let screenPoint = nsWin.convertToScreen(NSRect(origin: mousePos.unflipped(in: bounds), size: .zero)).origin

        // Find topmost SCWindow containing this screen point
        let hit = scWindows
            .filter { $0.frame.contains(screenPoint) && $0.frame.width > 10 }
            .max { $0.windowLayer < $1.windowLayer }

        hoveredWindowRect = hit.map { toView($0.frame) }
    }

    // MARK: - Coordinate helpers

    /// Flipped-view rect → screen rect.
    private func toScreen(_ viewRect: NSRect) -> CGRect {
        guard let w = window else { return viewRect }
        return w.convertToScreen(NSRect(
            x: viewRect.minX,
            y: bounds.height - viewRect.maxY,   // unflip Y
            width: viewRect.width,
            height: viewRect.height
        ))
    }

    /// Screen rect → flipped-view rect.
    private func toView(_ screenRect: CGRect) -> NSRect {
        guard let w = window else { return screenRect }
        let inWindow = CGRect(
            x: screenRect.minX - w.frame.minX,
            y: screenRect.minY - w.frame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
        // Flip Y
        return NSRect(
            x: inWindow.minX,
            y: bounds.height - inWindow.maxY,
            width: inWindow.width,
            height: inWindow.height
        )
    }
}

// MARK: - NSPoint helper

private extension NSPoint {
    /// Converts from flipped (top-left) to unflipped (bottom-left) within a rect.
    func unflipped(in bounds: NSRect) -> NSPoint {
        NSPoint(x: x, y: bounds.height - y)
    }
}
