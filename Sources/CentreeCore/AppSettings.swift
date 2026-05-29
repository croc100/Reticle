import AppKit
import Foundation
import Defaults

// MARK: - Geometry helpers (Codable wrappers for Defaults)

public struct StoredRect: Codable, Sendable, Defaults.Serializable {
    public var x, y, width, height: Double
    public init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct SavedRegion: Identifiable, Codable, Sendable, Defaults.Serializable {
    public let id: UUID
    public var name: String
    public var rect: StoredRect
    public init(id: UUID = UUID(), name: String, rect: CGRect) {
        self.id = id; self.name = name; self.rect = StoredRect(rect)
    }
}

// MARK: - Defaults Keys

public extension Defaults.Keys {

    // MARK: Output

    /// Directory where screenshots are saved.
    static let screenshotsDirectory = Key<URL>(
        "screenshotsDirectory",
        default: FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Centree")
    )

    /// Filename token pattern (see NameParser for supported tokens).
    static let filenamePattern = Key<String>(
        "filenamePattern",
        default: "%year%-%month%-%day%_%hour%%minute%%second%_%counter%.png"
    )

    // MARK: Sound

    /// Play shutter sound after a successful capture.
    static let captureSoundEnabled = Key<Bool>("captureSoundEnabled", default: true)

    /// NSSound name to play. Empty string = system "Grab" sound.
    static let captureSoundName = Key<String>("captureSoundName", default: "")

    // MARK: Hotkeys — Region capture (⌃⌘4 default; Carbon ctrlKey|cmdKey = 4352, keyCode 21 = '4')
    // ⌘⇧3/⌘⇧4 are reserved by macOS screenshot system; use ⌃⌘3/⌃⌘4 instead.

    static let regionHotkeyKeyCode  = Key<UInt32>("regionHotkeyKeyCode",  default: 21)
    static let regionHotkeyMods     = Key<UInt32>("regionHotkeyMods",     default: 4352)

    // MARK: Hotkeys — Full-screen capture (⌃⌘3 default; Carbon 4352, keyCode 20 = '3')

    static let fullscreenHotkeyKeyCode = Key<UInt32>("fullscreenHotkeyKeyCode", default: 20)
    static let fullscreenHotkeyMods    = Key<UInt32>("fullscreenHotkeyMods",    default: 4352)

    // MARK: Hotkeys — Last Region / Window Picker (no default = 0/0 = disabled)

    static let lastRegionHotkeyKeyCode   = Key<UInt32>("lastRegionHotkeyKeyCode",   default: 0)
    static let lastRegionHotkeyMods      = Key<UInt32>("lastRegionHotkeyMods",      default: 0)
    static let windowPickerHotkeyKeyCode = Key<UInt32>("windowPickerHotkeyKeyCode", default: 0)
    static let windowPickerHotkeyMods    = Key<UInt32>("windowPickerHotkeyMods",    default: 0)

    // MARK: Capture behaviour

    /// Seconds to wait before capture fires (0 = immediate).
    static let captureDelay = Key<Int>("captureDelay", default: 0)

    // MARK: Capture history / saved regions

    /// Last successfully captured region in screen coordinates.
    static let lastCaptureRect = Key<StoredRect?>("lastCaptureRect", default: nil)

    /// User-saved named regions.
    static let savedRegions = Key<[SavedRegion]>("savedRegions", default: [])

    // MARK: After Capture pipeline

    /// Ordered list of tasks to execute after every capture.
    static let afterCaptureOptions = Key<[AfterCaptureOption]>(
        "afterCaptureOptions",
        default: [.copyToClipboard, .saveToFile, .showNotification]
    )

    // MARK: OCR

    /// BCP-47 language codes for OCR (empty = auto-detect).
    static let ocrLanguages = Key<[String]>("ocrLanguages", default: [])

    // MARK: Upload

    /// Imgur Client ID for anonymous image uploads.
    static let imgurClientID = Key<String>("imgurClientID", default: "")

    // MARK: S3 Upload

    static let s3Bucket            = Key<String>("s3Bucket",            default: "")
    static let s3Region            = Key<String>("s3Region",            default: "us-east-1")
    static let s3AccessKeyID       = Key<String>("s3AccessKeyID",       default: "")
    static let s3SecretAccessKey   = Key<String>("s3SecretAccessKey",   default: "")
    static let s3KeyPrefix         = Key<String>("s3KeyPrefix",         default: "")
    static let s3PublicURLTemplate = Key<String>("s3PublicURLTemplate", default: "")
    static let s3PathStyle         = Key<Bool>("s3PathStyle",           default: false)

    // MARK: Custom HTTP Upload

    static let customHTTPMethod          = Key<String>("customHTTPMethod",          default: "POST")
    static let customHTTPURL             = Key<String>("customHTTPURL",             default: "")
    static let customHTTPFileField       = Key<String>("customHTTPFileField",       default: "file")
    static let customHTTPResponsePath    = Key<String>("customHTTPResponsePath",    default: "")
    /// Newline-separated "Key: Value" pairs.
    static let customHTTPHeadersRaw      = Key<String>("customHTTPHeadersRaw",      default: "")

    // MARK: Watermark

    /// Text template for the watermark (supports NameParser tokens such as %year%, %app%, etc.).
    static let watermarkText       = Key<String>("watermarkText",       default: "")
    /// One of: topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight
    static let watermarkPosition   = Key<String>("watermarkPosition",   default: "bottomRight")
    /// Point size of the watermark text (before scale-factor multiplication).
    static let watermarkFontSize   = Key<Double>("watermarkFontSize",   default: 14.0)
    /// Alpha 0–1 (0 = invisible, 1 = fully opaque).
    static let watermarkOpacity    = Key<Double>("watermarkOpacity",    default: 0.65)
    /// Hex colour string without '#', e.g. "FFFFFF" for white.
    static let watermarkColorHex   = Key<String>("watermarkColorHex",   default: "FFFFFF")
    /// When true a semi-transparent dark pill is drawn behind the text for legibility.
    static let watermarkBackground = Key<Bool>("watermarkBackground",   default: false)

    // MARK: SFTP Upload

    static let sftpHost           = Key<String>("sftpHost",           default: "")
    static let sftpPort           = Key<Int>("sftpPort",               default: 22)
    static let sftpUsername       = Key<String>("sftpUsername",        default: "")
    static let sftpPassword       = Key<String>("sftpPassword",        default: "")
    static let sftpPrivateKeyPath = Key<String>("sftpPrivateKeyPath",  default: "")
    /// Remote directory to upload into, e.g. "/var/www/screenshots/".
    static let sftpRemotePath     = Key<String>("sftpRemotePath",      default: "/")
    /// Base URL to prepend to the filename for the public link, e.g. "https://cdn.example.com/screenshots/".
    static let sftpPublicURL      = Key<String>("sftpPublicURL",       default: "")

    // MARK: Output Format

    /// File format for saved screenshots: "png", "jpeg", "tiff", "webp".
    static let outputFormat  = Key<String>("outputFormat",  default: "png")
    /// JPEG compression quality 0.0–1.0.
    static let jpegQuality   = Key<Double>("jpegQuality",   default: 0.9)

    // MARK: Image Border / Shadow

    /// Width of the solid border in points (before scale-factor multiplication).
    static let borderWidth      = Key<Double>("borderWidth",      default: 4.0)
    /// Hex colour string for the border fill, e.g. "000000" for black.
    static let borderColorHex   = Key<String>("borderColorHex",   default: "000000")
    /// Alpha of the border colour.
    static let borderOpacity    = Key<Double>("borderOpacity",    default: 1.0)
    /// When true a soft drop shadow is added around the image.
    static let borderShadow     = Key<Bool>("borderShadow",       default: false)
    /// Blur radius of the drop shadow in pixels.
    static let borderShadowBlur = Key<Double>("borderShadowBlur", default: 20.0)

    // MARK: Workflow Profiles

    /// User-defined capture workflow profiles.
    static let workflowProfiles = Key<[StoredWorkflowProfile]>("workflowProfiles", default: [])

    // MARK: Auto Capture

    static let autoCaptureEnabled  = Key<Bool>("autoCaptureEnabled",  default: false)
    static let autoCaptureInterval = Key<Int>("autoCaptureInterval",   default: 5)
    static let autoCaptureMode     = Key<AutoCaptureMode>("autoCaptureMode", default: .activeScreen)
}

// MARK: - Auto Capture Mode

public enum AutoCaptureMode: String, CaseIterable, Codable, Sendable, Defaults.Serializable {
    case activeScreen = "activeScreen"
    case fullScreen   = "fullScreen"
    case lastRegion   = "lastRegion"

    public var title: String {
        switch self {
        case .activeScreen: return "Active Screen"
        case .fullScreen:   return "Full Screen (All Displays)"
        case .lastRegion:   return "Last Region"
        }
    }
}

// MARK: - Workflow Profile (lightweight, Defaults-serializable)

/// Lightweight representation of a workflow profile stored in Defaults.
/// Uses the same field names as CentreeWorkflow.WorkflowProfile for easy migration.
public struct StoredWorkflowProfile: Identifiable, Codable, Sendable, Defaults.Serializable {
    public let id: UUID
    public var name: String
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// Raw value of WorkflowCaptureMode
    public var captureMode: String
    /// Raw values of OutputDestination
    public var outputDestinations: [String]
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        keyCode: UInt32 = 0,
        modifiers: UInt32 = 0,
        captureMode: String = "region",
        outputDestinations: [String] = ["clipboard"],
        enabled: Bool = true
    ) {
        self.id = id; self.name = name
        self.keyCode = keyCode; self.modifiers = modifiers
        self.captureMode = captureMode
        self.outputDestinations = outputDestinations
        self.enabled = enabled
    }
}

// MARK: - Carbon modifier helpers

/// Converts Carbon-style modifier flags (stored in Defaults) ↔ NSEvent.ModifierFlags.
public enum CarbonModifiers {
    // Carbon modifier constants
    static let cmdKey:   UInt32 = 1 << 8   // 256
    static let shiftKey: UInt32 = 1 << 9   // 512
    static let optKey:   UInt32 = 1 << 11  // 2048
    static let ctrlKey:  UInt32 = 1 << 12  // 4096

    public static func toNSFlags(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & cmdKey   != 0 { flags.insert(.command) }
        if carbon & shiftKey != 0 { flags.insert(.shift) }
        if carbon & optKey   != 0 { flags.insert(.option) }
        if carbon & ctrlKey  != 0 { flags.insert(.control) }
        return flags
    }

    public static func fromNSFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.shift)   { carbon |= shiftKey }
        if flags.contains(.option)  { carbon |= optKey }
        if flags.contains(.control) { carbon |= ctrlKey }
        return carbon
    }

    /// Human-readable string like "⌘⇧".
    public static func symbol(_ carbon: UInt32) -> String {
        var s = ""
        if carbon & ctrlKey  != 0 { s += "⌃" }
        if carbon & optKey   != 0 { s += "⌥" }
        if carbon & shiftKey != 0 { s += "⇧" }
        if carbon & cmdKey   != 0 { s += "⌘" }
        return s
    }
}
