import AppKit
import CoreGraphics
import Defaults
import CentreeCapture
import CentreeCore
import CentreeOverlay
import CentreePipeline
import CentreeUploaders
import CentreeVision
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

    func captureWithOverlay()                   { Task { await runOverlayCapture()           } }
    func captureFullScreen()                    { Task { await runFullScreen()               } }
    func captureLastRegion()                    { Task { await runLastRegion()               } }
    func captureWindowPicker()                  { Task { await runWindowPicker()             } }
    func captureSavedRegion(id: UUID)           { Task { await runSavedRegion(id: id)        } }
    func captureScroll()                        { Task { await runScrollCapture()            } }
    func captureDisplay(displayID: CGDirectDisplayID) { Task { await runDisplayCapture(displayID: displayID) } }
    func openForEditing()                             { Task { await runEditorMode()                        } }

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

    // MARK: - Editor mode

    private func runEditorMode() async {
        // Show open panel on main thread
        let result = await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Open Image for Editing"
            panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .gif, .bmp]
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let url = result,
              let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        // Detect if it's a @2x image by comparing NSImage.size vs cgImage pixels
        let scale: CGFloat = {
            let ptW = nsImage.size.width
            let pxW = CGFloat(cgImage.width)
            return pxW > ptW * 1.5 ? 2.0 : 1.0
        }()

        let editorResult = await overlay.showEditor(image: cgImage, scaleFactor: scale)
        guard case .captured(let image, let sourceRect, let scaleFactor) = editorResult else { return }
        await finalize(image: image, sourceRect: sourceRect, scaleFactor: scaleFactor)
    }

    // MARK: - Per-display capture

    private func runDisplayCapture(displayID: CGDirectDisplayID) async {
        do {
            await applyDelay()
            let shot = try await capturer.capture(mode: .fullScreen(displayID: displayID))
            await finalize(image: shot.image, sourceRect: shot.sourceRect, scaleFactor: shot.scaleFactor)
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
            await applyDelay()
            let (displays, scWindows) = try await provider.fetchContent()
            guard !displays.isEmpty else { return }

            var backgrounds: [(frame: CGRect, image: CGImage)] = []
            for display in displays {
                let shot = try await capturer.capture(mode: .fullScreen(displayID: display.displayID))
                backgrounds.append((frame: display.frame, image: shot.image))
            }

            let result = await overlay.show(backgrounds: backgrounds, scWindows: scWindows, windowPickerMode: true)
            guard case .captured(let image, let sourceRect, let scale) = result else { return }

            Defaults[.lastCaptureRect] = StoredRect(sourceRect)
            await finalize(image: image, sourceRect: sourceRect, scaleFactor: scale)
        } catch { showError(error) }
    }

    // MARK: - Scroll Capture

    private func runScrollCapture() async {
        // Accessibility permission is required for CGEvent posting.
        guard AXIsProcessTrusted() else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                Scroll Capture needs to post scroll events to the target window.
                Please grant Accessibility access in System Settings → Privacy & Security → Accessibility, \
                then try again.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            return
        }

        do {
            let (_, scWindows) = try await provider.fetchContent()
            guard !scWindows.isEmpty else { return }

            guard let window = await WindowPickerPanel.shared.pick(from: scWindows) else { return }

            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let scroller = ScrollCapturer()
            let image    = try await scroller.capture(window: window, scrollToTop: true)

            await finalize(image: image, sourceRect: window.frame, scaleFactor: scale)
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

            // Record to capture history
            let thumbData = CaptureHistoryManager.makeThumbnail(from: image)
            let histItem = HistoryItem(
                filePath: ctx.outputURLs.first?.path,
                sourceRect: sourceRect,
                scaleFactor: Double(scaleFactor),
                widthPx: image.width,
                heightPx: image.height,
                thumbnailData: thumbData
            )
            CaptureHistoryManager.shared.add(histItem)

            // Pin to screen (needs raw image, done outside pipeline)
            if optSet.contains(.pinToScreen) {
                PinToScreenPanel.pin(image: image)
            }

            // OCR (async — show result panel when ready)
            // Imgur upload
            if optSet.contains(.uploadToImgur) {
                let clientID = Defaults[.imgurClientID]
                guard !clientID.isEmpty else {
                    showError(NSError(domain: "Centree", code: 0,
                                     userInfo: [NSLocalizedDescriptionKey: "Imgur Client ID not configured. Add it in Settings → Output."]))
                    return
                }
                Task {
                    do {
                        let url = try await ImgurUploader(clientID: clientID).upload(image)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } catch {
                        await MainActor.run { self.showError(error) }
                    }
                }
            }

            if optSet.contains(.ocr) {
                Task {
                    let langs = Defaults[.ocrLanguages]
                    let text = (try? await OCRProcessor(languages: langs).recognizeText(in: image)) ?? ""
                    OCRResultPanel.shared.show(text: text)
                }
            }

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
