import AppKit
import SwiftUI

// MARK: - Result

public enum EditorResult: Sendable {
    case saved(CGImage)
    case cancelled
}

// MARK: - EditorWindowController

/// Presents the annotation editor as a resizable window.
/// Call `show(image:scaleFactor:)` and `await` the result.
@MainActor
public final class EditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var continuation: CheckedContinuation<EditorResult, Never>?
    private var vm = EditorViewModel()
    private var canvasView: AnnotationCanvasView?
    private var scaleFactor: CGFloat = 2.0
    private var baseImage: CGImage?

    // MARK: - Show

    public func show(image: CGImage, scaleFactor: CGFloat) async -> EditorResult {
        self.scaleFactor = scaleFactor
        self.baseImage = image

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.openWindow(image: image, scaleFactor: scaleFactor)
        }
    }

    // MARK: - Window setup

    private func openWindow(image: CGImage, scaleFactor: CGFloat) {
        vm = EditorViewModel()

        // Window size = image size in points
        let ptW = CGFloat(image.width) / scaleFactor
        let ptH = CGFloat(image.height) / scaleFactor

        // Toolbar height
        let toolbarH: CGFloat = 44
        let totalH = ptH + toolbarH

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: ptW, height: totalH),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Annotate"
        win.delegate = self
        win.center()
        win.isReleasedWhenClosed = false

        // Root split: toolbar (top) + canvas (bottom)
        let root = NSView()
        root.wantsLayer = true
        win.contentView = root

        // Canvas
        let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: ptW, height: ptH))
        canvas.autoresizingMask = [.width, .height]
        canvas.viewModel = vm
        canvas.setBaseImage(image)
        canvas.onEscape = { [weak self] in self?.handleCancel() }
        root.addSubview(canvas)
        canvasView = canvas

        // Toolbar (SwiftUI)
        let toolbarView = EditorToolbarView(vm: vm) { [weak self] in
            self?.handleDone()
        } onCancel: { [weak self] in
            self?.handleCancel()
        }
        let hosting = NSHostingView(rootView: toolbarView)
        hosting.frame = NSRect(x: 0, y: ptH, width: ptW, height: toolbarH)
        hosting.autoresizingMask = [.width, .minYMargin]
        root.addSubview(hosting)

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    private func handleDone() {
        guard let base = baseImage else { handleCancel(); return }
        let rendered = vm.render(onto: base, scaleFactor: scaleFactor) ?? base
        closeWindow()
        continuation?.resume(returning: .saved(rendered))
        continuation = nil
    }

    private func handleCancel() {
        closeWindow()
        continuation?.resume(returning: .cancelled)
        continuation = nil
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        guard continuation != nil else { return }
        continuation?.resume(returning: .cancelled)
        continuation = nil
    }
}

// MARK: - Toolbar SwiftUI view

private struct EditorToolbarView: View {
    @ObservedObject var vm: EditorViewModel
    let onDone: () -> Void
    let onCancel: () -> Void

    private let tools: [(AnnotationTool, String)] = [
        (.select,    "cursorarrow"),
        (.rect,      "rectangle"),
        (.arrow,     "arrow.up.right"),
        (.text,      "textformat"),
        (.highlight, "highlighter"),
        (.pen,       "pencil"),
        (.step,      "number.circle"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            // Tool buttons
            ForEach(tools, id: \.0.rawValue) { tool, icon in
                Button { vm.activeTool = tool } label: {
                    Image(systemName: icon)
                        .frame(width: 28, height: 28)
                        .background(vm.activeTool == tool
                            ? Color.accentColor.opacity(0.25) : Color.clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help(tool.rawValue.capitalized)
            }

            Divider().frame(height: 22)

            // Color well (hidden for select tool)
            if vm.activeTool != .select { ColorWellButton(color: $vm.strokeColor) }

            // Line width stepper (hidden for select/text/step/highlight)
            if ![.select, .text, .step, .highlight].contains(vm.activeTool) {
                Stepper(value: $vm.lineWidth, in: 1...12, step: 1) {
                    Text("\(Int(vm.lineWidth))px").font(.caption).monospacedDigit()
                }
                .frame(width: 90)
            }

            // Font size stepper (text only)
            if vm.activeTool == .text {
                Stepper(value: $vm.fontSize, in: 10...72, step: 2) {
                    Text("\(Int(vm.fontSize))pt").font(.caption).monospacedDigit()
                }
                .frame(width: 90)
            }

            Spacer()

            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!vm.canUndo)
                .keyboardShortcut("z", modifiers: .command)

            Divider().frame(height: 22)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])

            Button("Done", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.regularMaterial)
    }
}

// MARK: - Color well wrapper

private struct ColorWellButton: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = color
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: ColorWellButton
        init(_ parent: ColorWellButton) { self.parent = parent }
        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = sender.color
        }
    }
}
