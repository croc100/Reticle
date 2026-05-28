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
