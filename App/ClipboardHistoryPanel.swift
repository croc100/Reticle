import SwiftUI
import AppKit
import ReticleCore

// MARK: - ClipboardHistoryPanel

/// Floating panel that shows clipboard history — opens from menu bar or ⌘⇧V.
@MainActor
final class ClipboardHistoryPanel {
    static let shared = ClipboardHistoryPanel()
    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil); return }
        show()
    }

    func show() {
        let view = ClipboardHistoryView { [weak self] in self?.panel?.orderOut(nil) }
        let hosting = NSHostingController(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Clipboard History"
        p.contentViewController = hosting
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position near top-right
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 360
            let y = screen.visibleFrame.maxY - 520
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

// MARK: - ClipboardHistoryView

private struct ClipboardHistoryView: View {
    @StateObject private var manager = ClipboardHistoryManager.shared
    let onClose: () -> Void

    @State private var searchText = ""

    private var filtered: [ClipboardEntry] {
        guard !searchText.isEmpty else { return manager.items }
        return manager.items.filter { $0.displayText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clipboard").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(manager.items.isEmpty ? "No clipboard history yet" : "No results")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filtered) { entry in
                    ClipboardRowView(entry: entry) {
                        ClipboardHistoryManager.shared.copyToClipboard(entry)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer
            HStack {
                Text("\(manager.items.count) items")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { manager.clear() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            .padding(8)
        }
    }
}

// MARK: - ClipboardRowView

private struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon / thumbnail
            Group {
                switch entry {
                case .text:
                    Image(systemName: "doc.text").frame(width: 32, height: 32)
                        .foregroundStyle(.secondary)
                case .image(let image):
                    // The row-sized preview, not the full frame: this List used
                    // to hand SwiftUI up to thirty multi-megapixel images and
                    // ask it to resample every one of them down to 32 points.
                    Image(decorative: image.thumbnail, scale: 2)
                        .resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayText)
                    .lineLimit(2)
                    .font(.system(size: 12))
                Text(entry.typeLabel)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            if isHovered {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onCopy() }
    }
}
