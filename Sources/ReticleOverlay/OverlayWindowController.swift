import AppKit
import SwiftUI
import CoreGraphics
import ScreenCaptureKit
import ReticleCore

// MARK: - Result type

public enum OverlayResult: Sendable {
    case captured(image: CGImage, sourceRect: CGRect, scaleFactor: CGFloat)
    case cancelled
}

// MARK: - Controller

@MainActor
public final class OverlayWindowController {
    private var windows: [OverlayNSWindow] = []
    private var overlayViews: [OverlayView] = []
    private var toolbarHostingView: NSView?
    private var continuation: CheckedContinuation<OverlayResult, Never>?
    private var viewModel = OverlayViewModel()

    public init() {}

    // MARK: - Public API

    public func show(
        backgrounds: [(frame: CGRect, image: CGImage)],
        scWindows: [SCWindow] = [],
        windowPickerMode: Bool = false
    ) async -> OverlayResult {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.present(backgrounds: backgrounds, scWindows: scWindows, windowPickerMode: windowPickerMode)
        }
    }

    /// Open an existing image for annotation editing.
    /// The overlay is presented as a regular (non-fullscreen) window.
    /// The full image area is pre-selected so annotation tools work immediately.
    public func showEditor(image: CGImage, scaleFactor: CGFloat = 1) async -> OverlayResult {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.presentEditor(image: image, scaleFactor: scaleFactor)
        }
    }

    // MARK: - Present (Editor)

    private func presentEditor(image: CGImage, scaleFactor: CGFloat) {
        let ptW = CGFloat(image.width)  / scaleFactor
        let ptH = CGFloat(image.height) / scaleFactor

        // Constrain editor window to 80% of the main screen
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let maxW = screen.visibleFrame.width  * 0.85
        let maxH = screen.visibleFrame.height * 0.85
        let fitScale = min(1.0, min(maxW / ptW, maxH / ptH))
        let winW = (ptW * fitScale).rounded()
        let winH = (ptH * fitScale).rounded()
        let winOrigin = NSPoint(
            x: screen.visibleFrame.midX - winW / 2,
            y: screen.visibleFrame.midY - winH / 2
        )
        let winFrame = NSRect(origin: winOrigin, size: NSSize(width: winW, height: winH))

        let window = NSWindow(
            contentRect: winFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Edit Image — Reticle"
        window.isReleasedWhenClosed = false

        viewModel = OverlayViewModel()
        viewModel.onDone   = { [weak self] in self?.handleDone() }
        viewModel.onCancel = { [weak self] in self?.finish(with: .cancelled) }

        let view = OverlayView(backgroundImage: image, scaleFactor: scaleFactor)
        view.delegate = self
        view.viewModel = viewModel
        view.frame = window.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)

        // Pre-select the entire image so annotation tools are immediately active
        viewModel.selectionRect = NSRect(x: 0, y: 0, width: ptW, height: ptH)

        // Add toolbar (editor always shows toolbar)
        addToolbar(to: window, screen: screen)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        overlayViews.append(view)
        editorWindow = window
    }

    private var editorWindow: NSWindow?

    // MARK: - Present

    private func present(backgrounds: [(frame: CGRect, image: CGImage)], scWindows: [SCWindow], windowPickerMode: Bool = false) {
        viewModel = OverlayViewModel()
        viewModel.windowPickerMode = windowPickerMode
        viewModel.onDone   = { [weak self] in self?.handleDone() }
        viewModel.onCancel = { [weak self] in self?.finish(with: .cancelled) }

        let cursorScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                           ?? NSScreen.main

        for (frame, image) in backgrounds {
            let scale = NSScreen.screens.first(where: { $0.frame == frame })?.backingScaleFactor ?? 2.0
            let window = OverlayNSWindow(frame: frame)
            let view = OverlayView(backgroundImage: image, scaleFactor: scale)
            view.scWindows = scWindows
            view.delegate = self
            view.viewModel = viewModel
            view.frame = window.contentView!.bounds
            view.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(view)
            window.makeFirstResponder(view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            overlayViews.append(view)

            // Toolbar not shown in window-picker mode (click-to-capture, no annotation)
            if !windowPickerMode, frame == cursorScreen?.frame ?? frame {
                addToolbar(to: window, screen: NSScreen.screens.first(where: { $0.frame == frame }))
            }
        }
        NSCursor.crosshair.set()
    }

    // MARK: - Toolbar

    private func addToolbar(to window: NSWindow, screen: NSScreen?) {
        let safeTop: CGFloat = screen?.safeAreaInsets.top ?? 0
        let w = window.contentView!.bounds.width
        let h = window.contentView!.bounds.height

        let toolbarView = OverlayToolbarView(vm: viewModel)
        let hosting = NSHostingView(rootView: toolbarView)
        hosting.wantsLayer = true

        // Temporarily place offscreen so SwiftUI can compute intrinsic size
        hosting.frame = NSRect(x: 0, y: h + 300, width: w, height: 200)
        window.contentView!.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        let toolbarW = fit.width > 10 ? fit.width : min(w - 40, 900)
        let toolbarH = fit.height > 10 ? fit.height : 72
        let startX   = ((w - toolbarW) / 2).rounded()
        let finalY   = h - safeTop - toolbarH - 4
        let startY   = h + toolbarH

        hosting.frame = NSRect(x: startX, y: startY, width: toolbarW, height: toolbarH)
        hosting.autoresizingMask = [.minXMargin, .maxXMargin]
        toolbarHostingView = hosting

        // Dock-like spring slide-in (overshoot cubic bezier)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            ctx.allowsImplicitAnimation = true
            hosting.animator().frame.origin.y = finalY
        }
    }

    // MARK: - Done

    private func handleDone() {
        for view in overlayViews {
            if view.viewModel?.selectionRect != nil {
                view.requestFinish()
                return
            }
        }
        // No selection — nothing to do
    }

    // MARK: - Finish

    private func finish(with result: OverlayResult) {
        // Slide toolbar out
        if let th = toolbarHostingView {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                let target = th.superview?.bounds.height ?? 0
                th.animator().frame.origin.y = target
            }, completionHandler: { [weak self] in
                self?.tearDown(result: result)
            })
        } else {
            tearDown(result: result)
        }
    }

    private func tearDown(result: OverlayResult) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        editorWindow?.orderOut(nil)
        editorWindow = nil
        overlayViews.removeAll()
        toolbarHostingView = nil
        NSCursor.arrow.set()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

// MARK: - OverlayViewDelegate

extension OverlayWindowController: OverlayViewDelegate {
    func overlayView(_ view: OverlayView, didFinish image: CGImage,
                     sourceRect: CGRect, scaleFactor: CGFloat) {
        finish(with: .captured(image: image, sourceRect: sourceRect, scaleFactor: scaleFactor))
    }

    func overlayViewDidCancel(_ view: OverlayView) {
        finish(with: .cancelled)
    }
}

// MARK: - NSWindow subclass

private final class OverlayNSWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        ignoresMouseEvents = false; acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
