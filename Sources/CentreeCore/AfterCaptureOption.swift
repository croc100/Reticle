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

    /// Automatically detect and blur PII (emails, phone numbers, API keys, etc.).
    case autoRedactPII

    /// Stamp a configurable text watermark onto the image.
    case watermark

    /// Add a coloured border (and optional drop shadow) around the image.
    case imageBorder

    /// Print the captured image via the system print dialog.
    case print

    /// Pin the captured image to the screen as a floating overlay.
    case pinToScreen

    // MARK: Upload

    /// Upload image to Imgur and copy the link to the clipboard.
    case uploadToImgur

    /// Upload image to an AWS S3 bucket (or S3-compatible service) and copy the link.
    case uploadToS3

    /// POST/PUT image to any HTTP endpoint and copy the returned link.
    case uploadCustomHTTP

    /// Upload image via SFTP and copy the public link to the clipboard.
    case uploadToSFTP

    /// After any upload completes, open the returned URL in the default browser.
    case openUploadedURL

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
        case .autoRedactPII:   return "Auto-redact PII"
        case .watermark:       return "Stamp watermark"
        case .imageBorder:     return "Add border / shadow"
        case .print:           return "Print"
        case .pinToScreen:     return "Pin to screen"
        case .uploadToImgur:   return "Upload to Imgur"
        case .uploadToS3:          return "Upload to Amazon S3"
        case .uploadCustomHTTP:    return "Upload via Custom HTTP"
        case .uploadToSFTP:        return "Upload via SFTP"
        case .openUploadedURL:     return "Open uploaded URL in browser"
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
        case .autoRedactPII:   return "Blurs emails, phone numbers, API keys, credit card numbers"
        case .watermark:       return "Configure text, position and style in Settings → Pipeline"
        case .imageBorder:     return "Configure thickness, colour and shadow in Settings → Pipeline"
        case .print:           return "Opens the system print dialog with the captured image"
        case .pinToScreen:     return "Floating window that stays on top"
        case .uploadToImgur:   return "Requires Imgur Client ID in Settings → Pipeline"
        case .uploadToS3:       return "Requires S3 credentials in Settings → Pipeline"
        case .uploadCustomHTTP: return "Configure URL, field name, and headers in Settings → Pipeline"
        case .uploadToSFTP:     return "Configure host, username and remote path in Settings → Pipeline"
        case .openUploadedURL:  return "Automatically opens the link in your default browser"
        }
    }

    /// Tasks that transform the image (run before output tasks).
    public var isImageTransform: Bool {
        switch self {
        case .autoRedactPII, .watermark, .imageBorder: return true
        default: return false
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
