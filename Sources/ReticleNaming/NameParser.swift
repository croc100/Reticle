import AppKit
import ReticleCore
import Foundation

/// Resolves filename templates into concrete filenames.
/// Follows ShareX's CodeMenuEntryFilename token set (ShareX.HelpersLib/NameParser/).
///
/// Date/time:  %year%, %yy%, %month%, %mon%, %day%, %hour%, %h12%, %minute%, %second%,
///             %ms%, %pm%, %unix%, %weekday%, %weeknum%
/// Capture:    %width%, %height%, %app%
/// Counter:    %counter%, %ix% (hex), %ia% (alphanumeric lower)
/// Random:     %rn%, %ra%, %rx%, %guid%
/// System:     %un%, %cn%
/// UUID:       %uuid%
public struct NameParser: @unchecked Sendable {
    public static let defaultPattern = "%year%-%month%-%day%_%hour%%minute%%second%_%counter%.png"

    private let pattern: String
    private let counter: () -> Int

    /// Optional image dimensions (for %width% / %height%).
    public var imageWidth: Int = 0
    public var imageHeight: Int = 0

    /// Optional process name of the frontmost app (for %app% / %pn%).
    public var processName: String = ""

    public init(pattern: String = defaultPattern, counter: @escaping () -> Int = { 1 }) {
        self.pattern = pattern
        self.counter = counter
    }

    /// Resolves the pattern against the given date.
    public func resolve(date: Date = .now) -> String {
        let cal = Calendar.current
        var result = pattern

        // ── Date / Time ──────────────────────────────────────────────
        let year   = cal.component(.year,   from: date)
        let month  = cal.component(.month,  from: date)
        let day    = cal.component(.day,    from: date)
        let hour   = cal.component(.hour,   from: date)
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let millis = cal.component(.nanosecond, from: date) / 1_000_000

        let isPM = hour >= 12
        let hour12 = hour % 12 == 0 ? 12 : hour % 12

        // Week-of-year (ISO 8601 style)
        let weekNum = cal.component(.weekOfYear, from: date)

        let dayName  = cal.weekdaySymbols[cal.component(.weekday, from: date) - 1]
        let monthName = DateFormatter().monthSymbols?[month - 1] ?? ""

        let unixTimestamp = Int(date.timeIntervalSince1970)

        // %pm% replaces %hour% with 12h; resolve %pm% before %hour%
        let hasAmPm = result.contains("%pm%")
        let hourStr = hasAmPm ? String(format: "%02d", hour12) : String(format: "%02d", hour)

        result = result
            .replacingOccurrences(of: "%pm%",      with: isPM ? "PM" : "AM")
            .replacingOccurrences(of: "%year%",    with: String(format: "%04d", year))
            .replacingOccurrences(of: "%yy%",      with: String(format: "%02d", year % 100))
            .replacingOccurrences(of: "%month%",   with: String(format: "%02d", month))
            .replacingOccurrences(of: "%mon%",     with: monthName)
            .replacingOccurrences(of: "%day%",     with: String(format: "%02d", day))
            .replacingOccurrences(of: "%hour%",    with: hourStr)
            .replacingOccurrences(of: "%h12%",     with: String(format: "%02d", hour12))
            .replacingOccurrences(of: "%minute%",  with: String(format: "%02d", minute))
            .replacingOccurrences(of: "%second%",  with: String(format: "%02d", second))
            .replacingOccurrences(of: "%ms%",      with: String(format: "%03d", millis))
            .replacingOccurrences(of: "%weekday%", with: dayName)
            .replacingOccurrences(of: "%weeknum%", with: String(format: "%02d", weekNum))
            .replacingOccurrences(of: "%unix%",    with: String(unixTimestamp))

        // ── Counter / Increment ──────────────────────────────────────
        let n = counter()
        result = result
            .replacingOccurrences(of: "%counter%", with: String(n))
            .replacingOccurrences(of: "%ix%",      with: String(format: "%x", n))
            .replacingOccurrences(of: "%ia%",      with: toBase36(n).lowercased())

        // ── Random ───────────────────────────────────────────────────
        result = result
            .replacingOccurrences(of: "%rn%",   with: String(Int.random(in: 0...9)))
            .replacingOccurrences(of: "%ra%",   with: randomAlphanumeric(1))
            .replacingOccurrences(of: "%rx%",   with: String(format: "%x", Int.random(in: 0...15)))
            .replacingOccurrences(of: "%guid%", with: UUID().uuidString.lowercased())
            .replacingOccurrences(of: "%uuid%", with: UUID().uuidString)

        // ── Image dimensions ─────────────────────────────────────────
        result = result
            .replacingOccurrences(of: "%width%",  with: imageWidth  > 0 ? String(imageWidth)  : "")
            .replacingOccurrences(of: "%height%", with: imageHeight > 0 ? String(imageHeight) : "")

        // ── System / app ─────────────────────────────────────────────
        let pn = processName.isEmpty ? (activeAppName() ?? "unknown") : processName
        result = result
            .replacingOccurrences(of: "%app%",  with: pn)
            .replacingOccurrences(of: "%pn%",   with: pn)
            .replacingOccurrences(of: "%un%",   with: ProcessInfo.processInfo.environment["USER"] ?? NSUserName())
            .replacingOccurrences(of: "%cn%",   with: Host.current().localizedName ?? ProcessInfo.processInfo.hostName)

        return result
    }

    // MARK: - Helpers

    private func activeAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func toBase36(_ n: Int) -> String {
        if n == 0 { return "0" }
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var n = n; var result = ""
        while n > 0 { result = String(chars[n % 36]) + result; n /= 36 }
        return result
    }

    private func randomAlphanumeric(_ length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}
