import AppKit
import CoreGraphics

/// Shows a small floating preview in the bottom-right corner after a capture.
///
/// - Auto-dismisses after 5 seconds with a fade-out animation.
/// - Clicking the thumbnail opens the image in Preview.app.
/// - The panel slides in from the right on appearance.
@MainActor
public final class ThumbnailController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var savedURL: URL?
    private weak var hostingView: ThumbnailHostingView?

    // MARK: - Callbacks

    /// Called when the user chooses "Open in Editor" from the thumbnail context menu.
    public var onOpenInEditor: ((CGImage) -> Void)?

    public init() {}

    // MARK: - Public

    public func show(image: CGImage, savedAt url: URL?) {
        dismiss(animated: false)
        savedURL = url

        let thumbSize = thumbnailSize(for: image)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let margin: CGFloat = 16
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - thumbSize.width - margin,
            y: screen.visibleFrame.minY + margin
        )

        let p = makePanelPanel(frame: CGRect(origin: origin, size: thumbSize))
        let hv = ThumbnailHostingView(
            image: image,
            size: thumbSize,
            savedURL: url,
            onTap: { [weak self] in self?.openInPreview() },
            onOpenInEditor: { [weak self] img in
                self?.dismiss(animated: true)
                self?.onOpenInEditor?(img)
            }
        )
        hv.frame = p.contentView!.bounds
        hv.autoresizingMask = [.width, .height]
        p.contentView!.addSubview(hv)
        p.alphaValue = 0
        hostingView = hv

        panel = p
        p.orderFront(nil)

        // Slide in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        }

        // Auto-dismiss after 5 s
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.dismiss(animated: true) }
        }
    }

    public func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let p = panel else { return }
        panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                p.animator().alphaValue = 0
            }, completionHandler: { p.orderOut(nil) })
        } else {
            p.orderOut(nil)
        }
    }

    // MARK: - Private

    private func openInPreview() {
        dismiss(animated: true)
        if let url = savedURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func thumbnailSize(for image: CGImage) -> CGSize {
        let maxW: CGFloat = 240
        let ratio = CGFloat(image.height) / CGFloat(image.width)
        return CGSize(width: maxW, height: maxW * ratio)
    }

    private func makePanelPanel(frame: CGRect) -> NSPanel {
        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = false
        return p
    }
}

// MARK: - Hosting view (AppKit wrapper for the thumbnail image)

private final class ThumbnailHostingView: NSView, NSDraggingSource {
    private let image: CGImage
    private let onTap: () -> Void
    private let onOpenInEditor: (CGImage) -> Void
    /// File URL set by ThumbnailController when the image has been saved to disk.
    var savedURL: URL?

    // Track whether the mouse moved enough to be a drag vs a tap.
    private var mouseDownLocation: NSPoint = .zero
    private static let dragThreshold: CGFloat = 4

    init(image: CGImage, size: CGSize, savedURL: URL?,
         onTap: @escaping () -> Void,
         onOpenInEditor: @escaping (CGImage) -> Void) {
        self.image          = image
        self.savedURL       = savedURL
        self.onTap          = onTap
        self.onOpenInEditor = onOpenInEditor
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 6
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Draw image (flip for CG coordinate system)
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: bounds)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let cur = convert(event.locationInWindow, from: nil)
        let dx = cur.x - mouseDownLocation.x
        let dy = cur.y - mouseDownLocation.y
        guard hypot(dx, dy) > Self.dragThreshold else { return }

        // Prefer a real file drag (gives the receiver the actual PNG path).
        // Fall back to an image-data drag (NSImage → TIFF on the pasteboard).
        let writer: NSPasteboardWriting
        if let url = savedURL {
            writer = url as NSURL
        } else {
            writer = NSImage(cgImage: image, size: .zero)
        }

        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))

        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let cur = convert(event.locationInWindow, from: nil)
        let dx = cur.x - mouseDownLocation.x
        let dy = cur.y - mouseDownLocation.y
        // Only fire tap if the mouse didn't travel far (i.e. not a drag).
        if hypot(dx, dy) < Self.dragThreshold { onTap() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "")
        menu.addItem(withTitle: "Open in Preview",
                     action: #selector(menuOpenPreview), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open in Editor",
                     action: #selector(menuOpenEditor), keyEquivalent: "")
            .target = self
        if let url = savedURL {
            menu.addItem(withTitle: "Reveal in Finder",
                         action: #selector(menuRevealInFinder), keyEquivalent: "")
                .target = self
            let copyPathItem = menu.addItem(withTitle: "Copy File Path",
                                            action: #selector(menuCopyFilePath), keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.representedObject = url
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy Image",
                     action: #selector(menuCopyImage), keyEquivalent: "")
            .target = self
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    @objc private func menuOpenPreview()    { onTap() }
    @objc private func menuOpenEditor()     { onOpenInEditor(image) }
    @objc private func menuRevealInFinder() {
        guard let url = savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc private func menuCopyFilePath() {
        guard let url = savedURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
    }
    @objc private func menuCopyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }
}
