import Defaults
import Foundation

/// All configurable tasks that can run after a capture completes.
/// Stored in Defaults and presented as toggles in Settings → Pipeline.
public enum AfterCaptureOption: String, CaseIterable, Codable, Sendable, Defaults.Serializable {

    // MARK: Output tasks (write the image somewhere)

    /// Copy the captured image to the system clipboard.
    case copyToClipboard

    /// Save the image as a PNG file in the configured directory.
    case saveToFile

    // MARK: After-save tasks (require saveToFile to produce a URL)

    /// Reveal the saved file in Finder.
    case revealInFinder

    /// Copy the saved file's path to the clipboard.
    case copyFilePath

    /// Open the saved file in the default image viewer (Preview.app).
    case openInViewer

    // MARK: Notification

    /// Show the floating thumbnail notification after capture.
    case showNotification

    // MARK: Image actions

    /// Extract text from the captured image using Vision OCR.
    case ocr

    /// Pin the captured image to the screen as a floating overlay.
    case pinToScreen

    // MARK: Upload

    /// Upload image to Imgur and copy the link to the clipboard.
    case uploadToImgur

    // MARK: Metadata

    public var title: String {
        switch self {
        case .copyToClipboard: return "Copy image to clipboard"
        case .saveToFile:      return "Save image to file"
        case .revealInFinder:  return "Reveal in Finder"
        case .copyFilePath:    return "Copy file path to clipboard"
        case .openInViewer:    return "Open in Preview"
        case .showNotification:return "Show capture notification"
        case .ocr:             return "Extract text (OCR)"
        case .pinToScreen:     return "Pin to screen"
        case .uploadToImgur:   return "Upload to Imgur"
        }
    }

    public var description: String {
        switch self {
        case .copyToClipboard: return "Paste directly into any app"
        case .saveToFile:      return "Saved to Output → Save Location"
        case .revealInFinder:  return "Opens a Finder window at the saved file"
        case .copyFilePath:    return "Copies the absolute path as text"
        case .openInViewer:    return "Opens file in the default viewer (Preview)"
        case .showNotification:return "Floating thumbnail in the corner"
        case .ocr:             return "Reads text from the image via Vision"
        case .pinToScreen:     return "Floating window that stays on top"
        case .uploadToImgur:   return "Requires Imgur Client ID in Settings → Output"
        }
    }

    /// Tasks that require saveToFile to have run first (need an output URL).
    public var requiresSave: Bool {
        switch self {
        case .revealInFinder, .copyFilePath, .openInViewer: return true
        default: return false
        }
    }
}
