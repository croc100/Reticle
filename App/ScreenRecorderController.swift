import AppKit
import SwiftUI
import Defaults
import ReticleRecorder
import ReticleCore

/// Coordinates the screen recording UI: region picker → recording → stop → pipeline.
@MainActor
final class ScreenRecorderController: ObservableObject {

    // MARK: - Published state

    @Published var isRecording = false
    @Published var elapsedSeconds = 0

    // MARK: - Private

    private let recorder = ScreenRecorder()
    private var statusItem: NSStatusItem?
    private var observationTask: Task<Void, Never>?

    // MARK: - Actions

    /// Called from the menu. Shows a crosshair picker, then starts recording.
    func startInteractive() {
        Task { await self.beginRecording(captureRect: nil) }
    }

    /// Starts recording the given rect immediately (for workflow profiles).
    func startRegion(_ rect: CGRect) {
        Task { await self.beginRecording(captureRect: rect) }
    }

    /// Stops the active recording, encodes, and runs the after-capture pipeline.
    func stop() {
        Task {
            do {
                let url = try await recorder.stop()
                isRecording = false
                removeStatusItem()
                await handleFinished(url: url)
            } catch {
                isRecording = false
                removeStatusItem()
                showError(error)
            }
        }
    }

    func cancel() {
        recorder.cancel()
        isRecording = false
        removeStatusItem()
    }

    // MARK: - Private: begin

    private func beginRecording(captureRect: CGRect?) async {
        guard !isRecording else { return }

        // Choose output directory and format from user settings
        let format = RecordingFormat(rawValue: Defaults[.recordingFormatRaw]) ?? .mp4
        let dir = Defaults[.screenshotsDirectory]
        createDirectoryIfNeeded(dir)

        let filename = "\(formattedTimestamp())_recording.\(format.fileExtension)"
        let outputURL = dir.appendingPathComponent(filename)

        let config = RecordingConfig(
            captureRect: captureRect,
            fps: Defaults[.recordingFPS],
            format: format,
            outputURL: outputURL
        )

        do {
            try await recorder.start(config: config)
            isRecording = true
            elapsedSeconds = 0
            showStatusItem()
            observeElapsed()
        } catch {
            showError(error)
        }
    }

    // MARK: - Private: after recording

    private func handleFinished(url: URL) async {
        // Copy URL to clipboard as plain text (like ShareX's URL copy)
        if Defaults[.recordingCopyPathToClipboard] {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }

        // Desktop notification
        if Defaults[.recordingShowNotification] {
            let notification = NSUserNotification()
            notification.title = "Recording saved"
            notification.informativeText = url.lastPathComponent
            NSUserNotificationCenter.default.deliver(notification)
        }

        // Open in Finder
        if Defaults[.recordingRevealInFinder] {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Status item (recording indicator in menu bar)

    private func showStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⏺ 0:00"
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self

        let menu = NSMenu()
        menu.addItem(withTitle: "Stop Recording", action: #selector(stopFromMenu), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Cancel", action: #selector(cancelFromMenu), keyEquivalent: "")
            .target = self
        item.menu = menu

        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        observationTask?.cancel()
    }

    @objc private func statusItemClicked() {
        statusItem?.menu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: statusItem?.button?.bounds.height ?? 0),
            in: statusItem?.button
        )
    }

    @objc private func stopFromMenu()   { stop()   }
    @objc private func cancelFromMenu() { cancel() }

    // MARK: - Elapsed timer

    private func observeElapsed() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.elapsedSeconds = self.recorder.elapsedSeconds
                let m = self.elapsedSeconds / 60
                let s = self.elapsedSeconds % 60
                self.statusItem?.button?.title = String(format: "⏺ %d:%02d", m, s)
            }
        }
    }

    // MARK: - Helpers

    private func formattedTimestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        return df.string(from: Date())
    }

    private func createDirectoryIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Recording failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
