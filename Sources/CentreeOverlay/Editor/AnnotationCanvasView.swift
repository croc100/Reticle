import AppKit

// MARK: - AnnotationCanvasView

/// AppKit view that renders the screenshot + all annotations and handles drawing gestures.
/// `isFlipped = true` — all stored coordinates use top-left origin.
final class AnnotationCanvasView: NSView {

    // MARK: Configuration

    var viewModel: EditorViewModel?
    /// Called when the user presses Escape while NOT editing text (i.e. close the editor).
    var onEscape: (() -> Void)?

    // MARK: Private drag state

    private var dragStart: NSPoint?
    private var inProgressAnnotation: Annotation?   // live preview during drag
    private var editingTextField: NSTextField?       // non-nil while text tool is active
    private var selectedAnnotation: Annotation?      // for select tool
    private var moveOrigin: NSPoint?                 // drag origin for moving

    // MARK: Base image

    private var baseImage: NSImage?

    func setBaseImage(_ cg: CGImage) {
        baseImage = NSImage(cgImage: cg, size: .zero)
        needsDisplay = true
    }

    // MARK: Flipped

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let vm = viewModel else { return }

        // 1. Screenshot
        baseImage?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

        // 2. Committed annotations
        for ann in vm.annotations {
            ann.drawRotated(in: bounds)
            if ann === selectedAnnotation { drawSelectionHalo(for: ann) }
        }

        // 3. In-progress annotation
        inProgressAnnotation?.drawRotated(in: bounds)
    }

    private func drawSelectionHalo(for ann: Annotation) {
        // Draw a subtle blue border around the annotation bounding box.
        NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        // Attempt bounding-box per type
        if let r = ann as? RectAnnotation      { path.appendRect(r.rect.insetBy(dx: -3, dy: -3)) }
        else if let h = ann as? HighlightAnnotation { path.appendRect(h.rect.insetBy(dx: -3, dy: -3)) }
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let pt = convert(event.locationInWindow, from: nil)

        // --- Select tool ---
        if vm.activeTool == .select {
            // Find topmost annotation that hits the click point
            selectedAnnotation = vm.annotations.last(where: { $0.hitTest(pt) })
            moveOrigin = pt
            needsDisplay = true
            return
        }

        dragStart = pt

        switch vm.activeTool {
        case .select: break // handled above

        case .text:
            beginTextInput(at: pt, vm: vm)

        case .step:
            let ann = StepAnnotation(center: pt, number: vm.nextStepNumber, color: vm.strokeColor)
            vm.addAnnotation(ann)
            needsDisplay = true

        case .rect:
            inProgressAnnotation = RectAnnotation(
                rect: NSRect(origin: pt, size: .zero),
                color: vm.strokeColor, lineWidth: vm.lineWidth)

        case .arrow:
            inProgressAnnotation = ArrowAnnotation(
                start: pt, end: pt,
                color: vm.strokeColor, lineWidth: vm.lineWidth)

        case .highlight:
            inProgressAnnotation = HighlightAnnotation(
                rect: NSRect(origin: pt, size: .zero),
                color: vm.strokeColor)

        case .pen:
            let pen = PenAnnotation(color: vm.strokeColor, lineWidth: vm.lineWidth)
            pen.addPoint(pt)
            inProgressAnnotation = pen
            vm.pushUndo()
            vm.annotations.append(pen)

        default: break   // .region / .ellipse / .line / .blur / .pixelate / .blackout not used in standalone editor
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let cur = convert(event.locationInWindow, from: nil)

        // --- Select / move ---
        if vm.activeTool == .select {
            if let sel = selectedAnnotation, let origin = moveOrigin {
                let dx = cur.x - origin.x
                let dy = cur.y - origin.y
                moveAnnotation(sel, dx: dx, dy: dy)
                moveOrigin = cur
                needsDisplay = true
            }
            return
        }

        guard let start = dragStart else { return }

        switch vm.activeTool {
        case .select: break

        case .rect:
            inProgressAnnotation = RectAnnotation(
                rect: makeRect(start, cur),
                color: vm.strokeColor, lineWidth: vm.lineWidth)

        case .arrow:
            inProgressAnnotation = ArrowAnnotation(
                start: start, end: cur,
                color: vm.strokeColor, lineWidth: vm.lineWidth)

        case .highlight:
            inProgressAnnotation = HighlightAnnotation(
                rect: makeRect(start, cur),
                color: vm.strokeColor)

        case .pen:
            if let pen = vm.annotations.last as? PenAnnotation { pen.addPoint(cur) }

        case .text, .step:
            break

        default: break
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let vm = viewModel else { return }

        if vm.activeTool == .select {
            moveOrigin = nil
            return
        }

        switch vm.activeTool {
        case .select: break

        case .rect, .arrow, .highlight:
            if let ann = inProgressAnnotation { vm.addAnnotation(ann) }
            inProgressAnnotation = nil

        case .pen:
            // Already appended in mouseDown; undo state is already correct.
            break

        case .text, .step:
            break

        default: break
        }

        dragStart = nil
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // ESC: if text field is active → end text editing. Otherwise → close editor.
        if event.keyCode == 53 {
            if editingTextField != nil {
                window?.makeFirstResponder(self)  // resign → triggers textDidEndEditing
            } else {
                onEscape?()
            }
            return
        }

        // Delete / Backspace: remove selected annotation
        if (event.keyCode == 51 || event.keyCode == 117),
           let vm = viewModel, let sel = selectedAnnotation {
            vm.pushUndo()
            vm.annotations.removeAll { $0 === sel }
            selectedAnnotation = nil
            needsDisplay = true
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Text input

    private func beginTextInput(at point: NSPoint, vm: EditorViewModel) {
        guard editingTextField == nil else { return }

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 200, height: 32))
        field.isBordered = true
        field.backgroundColor = NSColor(white: 0, alpha: 0.5)
        field.textColor = vm.strokeColor
        field.font = NSFont.systemFont(ofSize: vm.fontSize, weight: .semibold)
        field.placeholderString = "Type…"
        field.focusRingType = .none
        addSubview(field)
        editingTextField = field
        window?.makeFirstResponder(field)

        NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification,
            object: field,
            queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview()
            self.editingTextField = nil
            if !text.isEmpty {
                let ann = TextAnnotation(
                    origin: point, text: text,
                    color: vm.strokeColor, fontSize: vm.fontSize)
                vm.addAnnotation(ann)
            }
            self.needsDisplay = true
            NotificationCenter.default.removeObserver(self)
        }
    }

    // MARK: - Move helpers

    private func moveAnnotation(_ ann: Annotation, dx: CGFloat, dy: CGFloat) {
        switch ann {
        case let r as RectAnnotation:
            r.rect = r.rect.offsetBy(dx: dx, dy: dy)
        case let a as ArrowAnnotation:
            a.start = NSPoint(x: a.start.x + dx, y: a.start.y + dy)
            a.end   = NSPoint(x: a.end.x   + dx, y: a.end.y   + dy)
        case let t as TextAnnotation:
            t.origin = NSPoint(x: t.origin.x + dx, y: t.origin.y + dy)
        case let h as HighlightAnnotation:
            h.rect = h.rect.offsetBy(dx: dx, dy: dy)
        case let p as PenAnnotation:
            p.points = p.points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
        case let s as StepAnnotation:
            s.center = NSPoint(x: s.center.x + dx, y: s.center.y + dy)
        default: break
        }
    }

    // MARK: - Helpers

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
