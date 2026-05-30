import AppKit
import ReticleCore
import SwiftUI

// MARK: - CaptureHistoryPanel

/// Floating panel showing a grid of past captures.
final class CaptureHistoryPanel: NSPanel {

    static let shared = CaptureHistoryPanel()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        title = "Capture History"
        isMovableByWindowBackground = true
        isFloatingPanel = false
        contentView = NSHostingView(rootView: HistoryView())
        center()
    }

    func toggle() {
        if isVisible { orderOut(nil) } else { makeKeyAndOrderFront(nil) }
    }
}

// MARK: - HistoryView

private struct HistoryView: View {
    @ObservedObject private var mgr = CaptureHistoryManager.shared
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(mgr.items.count) captures")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    mgr.clear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(mgr.items.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            if mgr.items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("No captures yet")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(mgr.items) { item in
                            HistoryItemCell(item: item)
                                .contextMenu {
                                    if let url = item.fileURL {
                                        Button("Reveal in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                        Button("Copy File Path") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(url.path, forType: .string)
                                        }
                                        Divider()
                                    }
                                    Button("Copy to Clipboard") {
                                        if let url = item.fileURL,
                                           let img = NSImage(contentsOf: url) {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.writeObjects([img])
                                        }
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        mgr.remove(id: item.id)
                                    }
                                }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

// MARK: - HistoryItemCell

private struct HistoryItemCell: View {
    let item: HistoryItem
    @State private var hovered = false

    private var thumbnail: NSImage? {
        guard let data = item.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(4/3, contentMode: .fit)
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if item.fileURL != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.capturedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(item.widthPx) × \(item.heightPx)")
                    .font(.caption).monospacedDigit().foregroundStyle(.primary)
                if let url = item.fileURL {
                    Text(url.lastPathComponent)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(6)
        .background(hovered ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) {
            if let url = item.fileURL { NSWorkspace.shared.open(url) }
        }
    }
}
