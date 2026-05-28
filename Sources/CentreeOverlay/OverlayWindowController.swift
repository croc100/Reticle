import AppKit
import SwiftUI
import CoreGraphics
import ScreenCaptureKit
import CentreeCore

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
        scWindows: [SCWindow] = []
    ) async -> OverlayResult {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.present(backgrounds: backgrounds, scWindows: scWindows)
        }
    }

    // MARK: - Present

    private func present(backgrounds: [(frame: CGRect, image: CGImage)], scWindows: [SCWindow]) {
        viewModel = OverlayViewModel()
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

            // Place toolbar on the display that has the cursor
            if frame == cursorScreen?.frame ?? frame {
                addToolbar(to: window, screen: NSScreen.screens.first(where: { $0.frame == frame }))
            }
        }
        NSCursor.crosshair.set()
    }

    // MARK: - Toolbar

    private func addToolbar(to window: OverlayNSWindow, screen: NSScreen?) {
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
