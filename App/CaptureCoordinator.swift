import AppKit
import CoreGraphics
import Defaults
import ReticleCapture
import ReticleCore
import ReticleOverlay
import ReticlePipeline
import ReticleUploaders
import ReticleVision
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

    init() {
        // Wire the thumbnail's "Open in Editor" callback so tapping it
        // opens the editor without requiring the user to find the saved file.
        thumbnail.onOpenInEditor = { [weak self] image in
            guard let self else { return }
            Task { await self.openEditorForImage(image) }
        }
    }

    // MARK: - Public actions

    func captureWithOverlay()                   { Task { await runOverlayCapture()           } }
    func captureFullScreen()                    { Task { await runFullScreen()               } }
    func captureLastRegion()                    { Task { await runLastRegion()               } }
    func captureWindowPicker()                  { Task { await runWindowPicker()             } }
    func captureSavedRegion(id: UUID)           { Task { await runSavedRegion(id: id)        } }
    func captureScroll()                        { Task { await runScrollCapture()            } }
    func captureDisplay(displayID: CGDirectDisplayID) { Task { await runDisplayCapture(displayID: displayID) } }
    func openForEditing()                             { Task { await runEditorMode()                        } }
    func runWorkflow(profileID: UUID)                 { Task { await runWorkflowProfile(id: profileID)      } }

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

    // MARK: - Workflow Profile execution

    /// When non-nil, `finalize` uses these output destinations instead of the global defaults.
    /// Set immediately before each workflow capture and cleared at the start of `finalize`.
    private var profileDestinationsOverride: [String]? = nil

    private func runWorkflowProfile(id: UUID) async {
        guard let profile = Defaults[.workflowProfiles].first(where: { $0.id == id }),
              profile.enabled else { return }
        // Inject per-profile output destinations; cleared automatically in finalize.
        profileDestinationsOverride = profile.outputDestinations.isEmpty ? nil : profile.outputDestinations
        switch profile.captureMode {
        case "region":     await runOverlayCapture()
        case "window":     await runWindowPicker()
        case "fullScreen": await runFullScreen()
        default:           await runOverlayCapture()
        }
    }

    // MARK: - Editor mode

    /// Opens the editor pre-loaded with an already-captured CGImage.
    /// Used by the thumbnail "Open in Editor" context-menu item.
    private func openEditorForImage(_ image: CGImage) async {
        // Guess scale: most captures are @2x; exact value isn't critical for editing.
        let scale: CGFloat = 2.0
        let editorResult = await overlay.showEditor(image: image, scaleFactor: scale)
        guard case .captured(let edited, let sourceRect, let sf) = editorResult else { return }
        await finalize(image: edited, sourceRect: sourceRect, scaleFactor: sf)
    }

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
        // Consume the per-profile override (if any) set by runWorkflowProfile.
        let profileDestinations = profileDestinationsOverride
        profileDestinationsOverride = nil

        do {
            // Compute effective option set. When a workflow profile provides explicit output
            // destinations we replace only the "where to send" options and keep all other
            // global options (notifications, OCR, PII, etc.) as configured.
            let globalOptions = Defaults[.afterCaptureOptions]
            let optSet: Set<AfterCaptureOption>
            if let destinations = profileDestinations {
                var effective = Set(globalOptions)
                let outputOptions: Set<AfterCaptureOption> = [
                    .copyToClipboard, .saveToFile, .uploadToImgur, .uploadToS3,
                    .uploadToSFTP, .uploadCustomHTTP
                ]
                effective.subtract(outputOptions)
                for d in destinations {
                    switch d {
                    case "clipboard":  effective.insert(.copyToClipboard)
                    case "localFile":  effective.insert(.saveToFile)
                    case "imgur":      effective.insert(.uploadToImgur)
                    case "s3":         effective.insert(.uploadToS3)
                    case "sftp":       effective.insert(.uploadToSFTP)
                    case "customHTTP": effective.insert(.uploadCustomHTTP)
                    default: break
                    }
                }
                optSet = effective
            } else {
                optSet = Set(globalOptions)
            }
            // Ordered options array (for tasks that iterate in order)
            let options = AfterCaptureOption.allCases.filter { optSet.contains($0) }
            let directory = Defaults[.screenshotsDirectory]

            // Build ordered output tasks
            var outputs: [any OutputTask] = []
            if optSet.contains(.copyToClipboard) {
                outputs.append(ClipboardOutput())
            }
            if optSet.contains(.saveToFile) {
                createDirectoryIfNeeded(directory)
                outputs.append(LocalFileOutput(
                    directory: directory,
                    format: Defaults[.outputFormat],
                    jpegQuality: Defaults[.jpegQuality]))
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

            // Build after-capture tasks (transform the image before saving/uploading).
            // Order: redact PII → add border → stamp watermark → print (sees final image).
            var afterCaptureTasks: [any AfterCaptureTask] = []
            if optSet.contains(.autoRedactPII) { afterCaptureTasks.append(PIIRedactionTask())   }
            if optSet.contains(.imageBorder)   { afterCaptureTasks.append(ImageBorderTask())    }
            if optSet.contains(.watermark)     { afterCaptureTasks.append(WatermarkTask())      }
            if optSet.contains(.print)         { afterCaptureTasks.append(PrintTask())          }

            let screenshot = Screenshot(image: image, sourceRect: sourceRect, scaleFactor: scaleFactor)
            let ctx = try await pipeline.run(
                preCapture: screenshot,
                afterCapture: afterCaptureTasks,
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

            // Upload tasks — all share the same completion handler.
            let openAfterUpload = optSet.contains(.openUploadedURL)

            // Imgur upload
            if optSet.contains(.uploadToImgur) {
                let clientID = Defaults[.imgurClientID]
                guard !clientID.isEmpty else {
                    showError(NSError(domain: "Reticle", code: 0,
                                     userInfo: [NSLocalizedDescriptionKey: "Imgur Client ID not configured. Add it in Settings → Pipeline."]))
                    return
                }
                Task {
                    do {
                        let url = try await ImgurUploader(clientID: clientID).upload(image)
                        handleUploadedURL(url, openInBrowser: openAfterUpload)
                    } catch { await MainActor.run { self.showError(error) } }
                }
            }

            if optSet.contains(.uploadToS3) {
                let bucket = Defaults[.s3Bucket]
                let keyID  = Defaults[.s3AccessKeyID]
                let secret = Defaults[.s3SecretAccessKey]
                guard !bucket.isEmpty && !keyID.isEmpty && !secret.isEmpty else {
                    showError(NSError(domain: "Reticle", code: 0,
                                     userInfo: [NSLocalizedDescriptionKey:
                                        "S3 not configured. Fill in bucket, access key, and secret in Settings → Pipeline."]))
                    return
                }
                let s3Config = S3Uploader.Config(
                    bucket: bucket,
                    region: Defaults[.s3Region].isEmpty ? "us-east-1" : Defaults[.s3Region],
                    accessKeyID: keyID,
                    secretAccessKey: secret,
                    keyPrefix: Defaults[.s3KeyPrefix],
                    publicURLTemplate: Defaults[.s3PublicURLTemplate],
                    pathStyle: Defaults[.s3PathStyle]
                )
                Task {
                    do {
                        let url = try await S3Uploader(config: s3Config).upload(image)
                        handleUploadedURL(url, openInBrowser: openAfterUpload)
                    } catch { await MainActor.run { self.showError(error) } }
                }
            }

            if optSet.contains(.uploadCustomHTTP) {
                let endpointURL = Defaults[.customHTTPURL]
                guard !endpointURL.isEmpty else {
                    showError(NSError(domain: "Reticle", code: 0,
                                     userInfo: [NSLocalizedDescriptionKey:
                                        "Custom HTTP URL not configured. Add it in Settings → Pipeline."]))
                    return
                }
                let headersRaw = Defaults[.customHTTPHeadersRaw]
                var headers: [String: String] = [:]
                for line in headersRaw.components(separatedBy: "\n") {
                    let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 2 { headers[parts[0]] = parts[1...].joined(separator: ":") }
                }
                let httpConfig = CustomHTTPUploader.Config(
                    method: Defaults[.customHTTPMethod],
                    url: endpointURL,
                    fileFormField: Defaults[.customHTTPFileField],
                    responseURLPath: Defaults[.customHTTPResponsePath],
                    headers: headers
                )
                Task {
                    do {
                        let url = try await CustomHTTPUploader(config: httpConfig).upload(image)
                        handleUploadedURL(url, openInBrowser: openAfterUpload)
                    } catch { await MainActor.run { self.showError(error) } }
                }
            }

            if optSet.contains(.uploadToSFTP) {
                let host = Defaults[.sftpHost]
                guard !host.isEmpty else {
                    showError(NSError(domain: "Reticle", code: 0,
                                     userInfo: [NSLocalizedDescriptionKey:
                                        "SFTP host not configured. Add it in Settings → Pipeline."]))
                    return
                }
                let sftpConfig = SFTPUploader.Config(
                    host: host,
                    port: Defaults[.sftpPort],
                    username: Defaults[.sftpUsername],
                    password: Defaults[.sftpPassword],
                    privateKeyPath: Defaults[.sftpPrivateKeyPath],
                    remotePath: Defaults[.sftpRemotePath],
                    publicBaseURL: Defaults[.sftpPublicURL]
                )
                Task {
                    do {
                        let url = try await SFTPUploader(config: sftpConfig).upload(image)
                        handleUploadedURL(url, openInBrowser: openAfterUpload)
                    } catch { await MainActor.run { self.showError(error) } }
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

    // MARK: - Upload completion

    /// Copies the formatted URL to the clipboard and optionally opens it in the default browser.
    @MainActor
    private func handleUploadedURL(_ url: URL, openInBrowser: Bool) {
        let raw = url.absoluteString
        let text: String
        switch Defaults[.uploadLinkFormat] {
        case "html":     text = "<img src=\"\(raw)\" alt=\"Screenshot\">"
        case "markdown": text = "![Screenshot](\(raw))"
        case "bbcode":   text = "[img]\(raw)[/img]"
        default:         text = raw   // "url" = plain URL
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if openInBrowser { NSWorkspace.shared.open(url) }
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
