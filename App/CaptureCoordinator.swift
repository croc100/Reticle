import AppKit
import CoreGraphics
import Defaults
import CentreeCapture
import CentreeCore
import CentreeOverlay
import CentreePipeline
import Foundation

/// Top-level coordinator — owns the full ShareX-style capture flow.
@MainActor
final class CaptureCoordinator: ObservableObject {

    // MARK: - Dependencies

    private let capturer  = Capturer()
    private let provider  = DisplayProvider()
    private let pipeline  = PipelineRunner()
    private let overlay   = OverlayWindowController()
    private let thumbnail = ThumbnailController()

    // MARK: - Public actions

    func captureWithOverlay()         { Task { await runOverlayCapture()        } }
    func captureFullScreen()          { Task { await runFullScreen()            } }
    func captureLastRegion()          { Task { await runLastRegion()            } }
    func captureWindowPicker()        { Task { await runWindowPicker()          } }
    func captureSavedRegion(id: UUID) { Task { await runSavedRegion(id: id)    } }

    // MARK: - Overlay flow

    private func runOverlayCapture() async {
        do {
            await applyDelay()

            let (displays, scWindows) = try await provider.fetchContent()
            guard !displays.isEmpty else { return }

            var backgrounds: [(frame: CGRect, image: CGImage)] = []
            for display in displays {
                let shot = try await capturer.capture(mode: .fullScreen(displayID: display.displayID))
                backgrounds.append((frame: display.frame, image: shot.image))
            }

            let result = await overlay.show(backgrounds: backgrounds, scWindows: scWindows)
            guard case .captured(let image, let sourceRect, let scale) = result else { return }

            // Persist for Last Region
            Defaults[.lastCaptureRect] = StoredRect(sourceRect)

            await finalize(image: image, sourceRect: sourceRect, scaleFactor: scale)

        } catch { showError(error) }
    }

    // MARK: - Full-screen flow

    private func runFullScreen() async {
        do {
            await applyDelay()
            let shot = try await capturer.capture(mode: .fullScreen(displayID: CGMainDisplayID()))
            await finalize(image: shot.image, sourceRect: shot.sourceRect, scaleFactor: shot.scaleFactor)
        } catch { showError(error) }
    }

    // MARK: - Last Region

    private func runLastRegion() async {
        guard let stored = Defaults[.lastCaptureRect] else {
            // No previous region → fall back to overlay
            await runOverlayCapture()
            return
        }
        do {
            await applyDelay()
            let shot = try await capturer.capture(mode: .region(stored.cgRect))
            await finalize(image: shot.image, sourceRect: shot.sourceRect, scaleFactor: shot.scaleFactor)
        } catch { showError(error) }
    }

    // MARK: - Window Picker

    private func runWindowPicker() async {
        do {
            let (_, scWindows) = try await provider.fetchContent()
            guard !scWindows.isEmpty else { return }

            guard let window = await WindowPickerPanel.shared.pick(from: scWindows) else { return }

            await applyDelay()
            let shot = try await capturer.capture(mode: .window(CGWindowID(window.windowID)))
            await finalize(image: shot.image, sourceRect: shot.sourceRect, scaleFactor: shot.scaleFactor)
        } catch { showError(error) }
    }

    // MARK: - Saved Region

    private func runSavedRegion(id: UUID) async {
        guard let region = Defaults[.savedRegions].first(where: { $0.id == id }) else { return }
        do {
            await applyDelay()
            let shot = try await capturer.capture(mode: .region(region.rect.cgRect))
            await finalize(image: shot.image, sourceRect: shot.sourceRect, scaleFactor: shot.scaleFactor)
        } catch { showError(error) }
    }

    // MARK: - Shared finalize

    private func finalize(image: CGImage, sourceRect: CGRect, scaleFactor: CGFloat) async {
        do {
            let options  = Defaults[.afterCaptureOptions]
            let optSet   = Set(options)
            let directory = Defaults[.screenshotsDirectory]

            // Build ordered output tasks
            var outputs: [any OutputTask] = []
            if optSet.contains(.copyToClipboard) {
                outputs.append(ClipboardOutput())
            }
            if optSet.contains(.saveToFile) {
                createDirectoryIfNeeded(directory)
                outputs.append(LocalFileOutput(directory: directory))
            }

            // Build after-output tasks (same order as options list for predictability)
            var afterOutputs: [any AfterOutputTask] = []
            for option in options {
                switch option {
                case .revealInFinder: afterOutputs.append(RevealInFinderTask())
                case .copyFilePath:   afterOutputs.append(CopyFilePathTask())
                case .openInViewer:   afterOutputs.append(OpenInViewerTask())
                default: break
                }
            }

            let screenshot = Screenshot(image: image, sourceRect: sourceRect, scaleFactor: scaleFactor)
            let ctx = try await pipeline.run(
                preCapture: screenshot,
                outputs: outputs,
                afterOutput: afterOutputs
            )

            if optSet.contains(.showNotification) {
                thumbnail.show(image: image, savedAt: ctx.outputURLs.first)
            }
            playShutterSound()
        } catch { showError(error) }
    }

    // MARK: - Delay

    private func applyDelay() async {
        let seconds = Defaults[.captureDelay]
        guard seconds > 0 else { return }
        await CountdownPanel.shared.show(seconds: seconds)
    }

    // MARK: - Helpers

    private func playShutterSound() {
        guard Defaults[.captureSoundEnabled] else { return }
        let name = Defaults[.captureSoundName]
        NSSound(named: name.isEmpty ? "Grab" : name)?.play()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func createDirectoryIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
