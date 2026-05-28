import SwiftUI

// MARK: - OverlayToolbarView

struct OverlayToolbarView: View {
    @ObservedObject var vm: OverlayViewModel

    private let regionGroup: [(AnnotationTool, String, String)] = [
        (.region, "camera.viewfinder",   "Select Region"),
        (.select, "cursorarrow",          "Select / Move"),
        (.crop,   "crop",                 "Crop"),
        (.eraser, "eraser",               "Eraser"),
    ]
    private let shapeGroup: [(AnnotationTool, String, String)] = [
        (.rect,    "rectangle",           "Rectangle"),
        (.ellipse, "oval",                "Ellipse"),
        (.line,    "line.diagonal",       "Line"),
        (.arrow,   "arrow.up.right",      "Arrow"),
        (.pen,     "pencil",              "Freehand"),
    ]
    private let textGroup: [(AnnotationTool, String, String)] = [
        (.text,          "textformat",       "Text"),
        (.step,          "number.circle",    "Step Number"),
        (.speechBalloon, "bubble.left",      "Speech Balloon"),
        (.emoji,         "face.smiling",     "Emoji / Sticker"),
    ]
    private let insertGroup: [(AnnotationTool, String, String)] = [
        (.cursor, "cursorarrow.click", "Mouse Cursor"),
        (.image,  "photo",             "Insert Image"),
    ]
    private let effectGroup: [(AnnotationTool, String, String)] = [
        (.highlight, "highlighter",                    "Highlight"),
        (.blur,      "aqi.medium",                     "Blur"),
        (.pixelate,  "squareshape.squareshape.dashed", "Pixelate"),
        (.blackout,  "rectangle.fill",                 "Blackout"),
        (.spotlight, "circle.dashed.inset.filled",     "Spotlight"),
        (.magnify,   "magnifyingglass",                "Magnify"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            toolGroup(regionGroup)
            divider()
            toolGroup(shapeGroup)
            divider()
            toolGroup(textGroup)
            divider()
            toolGroup(insertGroup)
            divider()
            toolGroup(effectGroup)
            divider()

            toolOptions()

            UndoButton(vm: vm)
            divider()

            Button("Cancel") { vm.onCancel?() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .keyboardShortcut(.escape, modifiers: [])

            Button(action: { vm.onDone?() }) {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(vm.hasSelection ? Color.accentColor : Color.secondary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(!vm.hasSelection)
            .padding(.trailing, 8)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .padding(14)
    }

    // MARK: Helpers

    @ViewBuilder
    private func toolGroup(_ tools: [(AnnotationTool, String, String)]) -> some View {
        HStack(spacing: 2) {
            ForEach(tools, id: \.0.rawValue) { tool, icon, tip in
                ToolbarButton(tool: tool, icon: icon, tip: tip, vm: vm)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func toolOptions() -> some View {
        HStack(spacing: 6) {
            if ![.region, .select, .blur, .pixelate, .blackout, .spotlight,
                 .crop, .eraser, .cursor, .image, .emoji].contains(vm.activeTool) {
                ColorWellRepresentable(color: $vm.strokeColor)
                    .frame(width: 28, height: 22)
            }
            if [.rect, .ellipse, .line, .arrow, .pen].contains(vm.activeTool) {
                Stepper(value: $vm.lineWidth, in: 1...12, step: 1) {
                    Text("\(Int(vm.lineWidth))px")
                        .font(.caption).monospacedDigit().frame(width: 32)
                }.frame(width: 88)
            }
            if vm.activeTool == .text {
                Stepper(value: $vm.fontSize, in: 10...72, step: 2) {
                    Text("\(Int(vm.fontSize))pt")
                        .font(.caption).monospacedDigit().frame(width: 32)
                }.frame(width: 88)
            }
            if vm.activeTool == .blur {
                HStack(spacing: 4) {
                    Image(systemName: "aqi.low")
                    Slider(value: $vm.blurRadius, in: 5...50).frame(width: 80)
                    Image(systemName: "aqi.high")
                }.font(.caption)
            }
            if vm.activeTool == .pixelate {
                HStack(spacing: 4) {
                    Text("Size:").font(.caption)
                    Stepper(value: $vm.pixelateSize, in: 4...40, step: 2) {
                        Text("\(Int(vm.pixelateSize))")
                            .font(.caption).monospacedDigit().frame(width: 24)
                    }.frame(width: 72)
                }
            }
            if vm.activeTool == .magnify {
                HStack(spacing: 4) {
                    Text("Zoom:").font(.caption)
                    Stepper(value: $vm.magnifyScale, in: 1.5...8, step: 0.5) {
                        Text("×\(String(format: "%.1f", vm.magnifyScale))")
                            .font(.caption).monospacedDigit().frame(width: 36)
                    }.frame(width: 88)
                }
            }
            if vm.activeTool == .emoji {
                Stepper(value: $vm.emojiSize, in: 16...96, step: 4) {
                    Text("\(Int(vm.emojiSize))pt")
                        .font(.caption).monospacedDigit().frame(width: 36)
                }.frame(width: 88)
            }
            if vm.activeTool == .cursor {
                Stepper(value: $vm.cursorSize, in: 16...80, step: 4) {
                    Text("\(Int(vm.cursorSize))px")
                        .font(.caption).monospacedDigit().frame(width: 36)
                }.frame(width: 88)
            }
        }
        .padding(.horizontal, 6)
    }

    private func divider() -> some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }
}

// MARK: - ToolbarButton

private struct ToolbarButton: View {
    let tool: AnnotationTool
    let icon: String
    let tip: String
    @ObservedObject var vm: OverlayViewModel
    @State private var hovered = false

    var body: some View {
        Button { vm.activeTool = tool } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tip)
        .onHover { hovered = $0 }
    }

    private var bgColor: Color {
        if vm.activeTool == tool { return Color.primary.opacity(0.12) }
        if hovered               { return Color.primary.opacity(0.06) }
        return .clear
    }
}

// MARK: - UndoButton

private struct UndoButton: View {
    @ObservedObject var vm: OverlayViewModel
    @State private var hovered = false

    var body: some View {
        Button { vm.undo() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(hovered ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!vm.canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .padding(.trailing, 4)
        .onHover { hovered = $0 }
    }
}

// MARK: - ColorWell

struct ColorWellRepresentable: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let w = NSColorWell()
        w.color = color
        w.target = context.coordinator
        w.action = #selector(Coordinator.changed(_:))
        return w
    }

    func updateNSView(_ v: NSColorWell, context: Context) { v.color = color }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: ColorWellRepresentable
        init(_ p: ColorWellRepresentable) { parent = p }
        @objc func changed(_ s: NSColorWell) { parent.color = s.color }
    }
}
