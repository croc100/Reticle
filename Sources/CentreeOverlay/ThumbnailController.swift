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
        let hostingView = ThumbnailHostingView(image: image, size: thumbSize, onTap: { [weak self] in
            self?.openInPreview()
        })
        hostingView.frame = p.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        p.contentView!.addSubview(hostingView)
        p.alphaValue = 0

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

private final class ThumbnailHostingView: NSView {
    private let image: CGImage
    private let onTap: () -> Void

    init(image: CGImage, size: CGSize, onTap: @escaping () -> Void) {
        self.image = image
        self.onTap = onTap
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

    override func mouseDown(with event: NSEvent) {
        onTap()
    }
}
