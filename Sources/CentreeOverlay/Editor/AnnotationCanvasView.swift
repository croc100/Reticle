import AppKit

// MARK: - AnnotationCanvasView

/// AppKit view that renders the screenshot + all annotations and handles drawing gestures.
/// `isFlipped = true` — all stored coordinates use top-left origin.
final class AnnotationCanvasView: NSView {

    // MARK: Configuration

    var viewModel: EditorViewModel?

    // MARK: Private drag state

    private var dragStart: NSPoint?
    private var inProgressAnnotation: Annotation?   // live preview during drag
    private var editingText: Bool = false

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
        for ann in vm.annotations { ann.draw(in: bounds) }

        // 3. In-progress annotation
        inProgressAnnotation?.draw(in: bounds)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let pt = convert(event.locationInWindow, from: nil)
        dragStart = pt

        switch vm.activeTool {
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
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let vm = viewModel, let start = dragStart else { return }
        let cur = convert(event.locationInWindow, from: nil)

        switch vm.activeTool {
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
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let vm = viewModel else { return }

        switch vm.activeTool {
        case .rect, .arrow, .highlight:
            if let ann = inProgressAnnotation {
                vm.addAnnotation(ann)
            }
            inProgressAnnotation = nil

        case .pen:
            // Already appended in mouseDown; canUndo state is already correct
            break

        case .text, .step:
            break
        }

        dragStart = nil
        needsDisplay = true
    }

    // MARK: - Text input

    private func beginTextInput(at point: NSPoint, vm: EditorViewModel) {
        guard !editingText else { return }
        editingText = true

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 200, height: 32))
        field.isBordered = true
        field.backgroundColor = NSColor(white: 0, alpha: 0.5)
        field.textColor = vm.strokeColor
        field.font = NSFont.systemFont(ofSize: vm.fontSize, weight: .semibold)
        field.placeholderString = "Type…"
        field.focusRingType = .none
        addSubview(field)
        window?.makeFirstResponder(field)

        NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification,
            object: field,
            queue: .main
        ) { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview()
            self.editingText = false
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

    // MARK: - Helpers

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
