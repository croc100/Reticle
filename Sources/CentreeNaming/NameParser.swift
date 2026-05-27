import CentreeCore
import Foundation

/// Resolves filename templates like `%year%-%month%-%day%_%app%_%counter%.png`
/// into concrete filenames.
///
/// Supported tokens: %year%, %month%, %day%, %hour%, %minute%, %second%,
///                   %app%, %counter%, %uuid%, %weekday%
/// - Note: `@unchecked Sendable` because the `counter` closure may capture mutable state.
///   Callers are responsible for ensuring `counter` is not called concurrently.
public struct NameParser: @unchecked Sendable {
    public static let defaultPattern = "%year%-%month%-%day%_%hour%%minute%%second%_%counter%.png"

    private let pattern: String
    private let counter: () -> Int

    public init(pattern: String = defaultPattern, counter: @escaping () -> Int = { 1 }) {
        self.pattern = pattern
        self.counter = counter
    }

    /// Resolves the pattern against the given date and active app name.
    public func resolve(date: Date = .now, appName: String = "") -> String {
        let cal = Calendar.current
        var result = pattern

        let replacements: [(String, String)] = [
            ("%year%",    String(format: "%04d", cal.component(.year, from: date))),
            ("%month%",   String(format: "%02d", cal.component(.month, from: date))),
            ("%day%",     String(format: "%02d", cal.component(.day, from: date))),
            ("%hour%",    String(format: "%02d", cal.component(.hour, from: date))),
            ("%minute%",  String(format: "%02d", cal.component(.minute, from: date))),
            ("%second%",  String(format: "%02d", cal.component(.second, from: date))),
            ("%app%",     appName.isEmpty ? "unknown" : appName),
            ("%counter%", String(counter())),
            ("%uuid%",    UUID().uuidString),
            ("%weekday%", Locale.current.calendar.weekdaySymbols[cal.component(.weekday, from: date) - 1]),
        ]

        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }
}
