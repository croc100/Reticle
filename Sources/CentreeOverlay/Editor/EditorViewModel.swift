import AppKit
import Combine

// MARK: - EditorViewModel

@MainActor
final class EditorViewModel: ObservableObject {

    // MARK: Published state

    @Published var activeTool: AnnotationTool = .rect
    @Published var strokeColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 2
    @Published var fontSize: CGFloat = 18
    @Published var annotations: [Annotation] = []
    @Published var canUndo: Bool = false

    // MARK: Private

    private var undoStack: [[Annotation]] = []

    // MARK: Snapshot / Undo

    func pushUndo() {
        undoStack.append(annotations)
        canUndo = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        annotations = last
        canUndo = !undoStack.isEmpty
    }

    // MARK: Add annotations

    func addAnnotation(_ ann: Annotation) {
        pushUndo()
        annotations.append(ann)
    }

    func replaceLastAnnotation(with ann: Annotation) {
        // Called during live drag to swap the in-progress annotation
        if !annotations.isEmpty { annotations[annotations.count - 1] = ann }
    }

    // MARK: Next step number

    var nextStepNumber: Int {
        (annotations.compactMap { ($0 as? StepAnnotation)?.number }.max() ?? 0) + 1
    }

    // MARK: Render final image

    /// Composites all annotations onto `baseImage` and returns a new CGImage.
    func render(onto baseImage: CGImage, scaleFactor: CGFloat) -> CGImage? {
        let w = baseImage.width
        let h = baseImage.height
        let ptW = CGFloat(w) / scaleFactor
        let ptH = CGFloat(h) / scaleFactor

        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Draw base image
        ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Set up NSGraphicsContext pointing at our CGContext, with Y-flip for annotations
        // (annotations are stored in top-left / flipped coords, CGContext is bottom-left)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scaleFactor, y: -scaleFactor)

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsCtx

        let bounds = NSRect(x: 0, y: 0, width: ptW, height: ptH)
        for ann in annotations { ann.draw(in: bounds) }

        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()

        return ctx.makeImage()
    }
}
