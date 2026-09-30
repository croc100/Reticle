import Vision
import CoreGraphics
import ReticleCore
import Defaults
import Foundation

/// Runs Vision OCR on a CGImage and returns MaskRegions for detected PII.
///
/// Patterns covered: email addresses, phone numbers, credit card numbers,
/// IBANs, JWT tokens, AWS access keys, GitHub PATs, generic API key tokens.
///
/// Redaction is coarse by design: one match anywhere in a recognised text block hides the
/// whole block. That makes false positives expensive — a single over-eager pattern blacks
/// out entire lines — so patterns prone to matching ordinary numbers pair their regex with
/// a second check. `matchedPatterns(in:enabled:)` holds that logic and is pure, so it can
/// be exercised without going through Vision.
public struct PIIDetector {

    // MARK: - Patterns

    /// One PII pattern: a regex that finds candidates, plus a check for what a regex alone
    /// gets wrong.
    struct Pattern {
        let name: String
        let regex: NSRegularExpression
        /// Second-stage check on the matched substring. Defaults to accepting every match.
        let accepts: @Sendable (String) -> Bool
    }

    static let patterns: [Pattern] = {
        let specs: [(name: String, pattern: String, accepts: @Sendable (String) -> Bool)] = [
            ("email",
             #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
             { _ in true }),

            // Deliberately loose on shape and strict on digit count. The previous pattern
            // made every separator optional around four one-digit groups, so any 4-digit
            // number — a year, a port, a screen dimension — hid the line it sat on.
            ("phone_intl",
             #"\+?[0-9][0-9\s.\-()]{5,18}[0-9]"#,
             isPlausiblePhoneNumber),

            ("credit_card",
             #"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b"#,
             passesLuhnCheck),

            // The trailing group was written `(?:[A-Z0-9]?){0,16}` — an optional atom inside
            // a bounded repeat, which is just a slower way to spell the same thing.
            ("iban",
             #"\b[A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}[A-Z0-9]{0,16}\b"#,
             { _ in true }),

            ("jwt",
             #"ey[A-Za-z0-9_\-]+\.ey[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#,
             { _ in true }),

            ("aws_key",
             #"\b(?:AKIA|ASIA|AIDA|AROA)[A-Z0-9]{16}\b"#,
             { _ in true }),

            ("github_pat",
             #"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}"#,
             { _ in true }),

            ("hex_secret",
             #"\b[0-9a-fA-F]{32,64}\b"#,
             { _ in true }),
        ]
        return specs.compactMap { spec in
            guard let regex = try? NSRegularExpression(pattern: spec.pattern, options: []) else { return nil }
            return Pattern(name: spec.name, regex: regex, accepts: spec.accepts)
        }
    }()

    /// Every pattern name Reticle knows about, in detection order.
    public static var allPatternNames: [String] { patterns.map(\.name) }

    public init() {}

    // MARK: - Matching

    /// Names of the patterns in `enabled` that match somewhere in `text`.
    ///
    /// An empty `enabled` set matches nothing — clearing every toggle in Settings turns
    /// redaction off rather than on.
    public static func matchedPatterns(in text: String, enabled: Set<String>) -> Set<String> {
        guard !enabled.isEmpty, !text.isEmpty else { return [] }

        var hits: Set<String> = []
        let fullRange = NSRange(text.startIndex..., in: text)

        for pattern in patterns where enabled.contains(pattern.name) {
            for match in pattern.regex.matches(in: text, options: [], range: fullRange) {
                guard let range = Range(match.range, in: text) else { continue }
                if pattern.accepts(String(text[range])) {
                    hits.insert(pattern.name)
                    break
                }
            }
        }
        return hits
    }

    /// Whether `text` holds anything worth redacting under the given pattern set.
    public static func containsPII(_ text: String, enabled: Set<String>) -> Bool {
        !matchedPatterns(in: text, enabled: enabled).isEmpty
    }

    // MARK: - Second-stage checks

    /// Rejects the number-shaped things that are not phone numbers.
    ///
    /// Phone numbers have no syntax to key off, so this leans on length: E.164 allows at
    /// most 15 digits, and 7 is the shortest local number. A run of digits with no grouping
    /// at all has to reach 10 to count, since shorter bare runs are far more often order
    /// numbers, ports, or IDs.
    static let isPlausiblePhoneNumber: @Sendable (String) -> Bool = { candidate in
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)

        // An IPv4 address or a dotted version string is the same shape as a phone number
        // written with dots.
        if trimmed.range(of: #"^[0-9]{1,3}(?:\.[0-9]{1,3}){3}$"#, options: .regularExpression) != nil {
            return false
        }

        let digitCount = trimmed.filter(\.isNumber).count
        guard (7...15).contains(digitCount) else { return false }

        let isGrouped = trimmed.contains { "+ .-()".contains($0) }
        return isGrouped || digitCount >= 10
    }

    /// The Luhn checksum every major card scheme uses.
    ///
    /// The card regexes match on prefix and length alone, so without this any 16-digit run
    /// starting with a 4 reads as a Visa number.
    static let passesLuhnCheck: @Sendable (String) -> Bool = { candidate in
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard digits.count >= 12 else { return false }

        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    // MARK: - Detection

    /// Runs OCR on the image, then scans every recognised text block for PII patterns.
    /// Returns one `MaskRegion` per matching text block, in image pixel space.
    ///
    /// The rects use Vision's own origin — bottom-left — and the caller is responsible for
    /// flipping them into the top-left space `MaskRenderer` expects.
    public func detect(in image: CGImage) async throws -> [MaskRegion] {
        let observations = try await runOCR(on: image)

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let enabled = Set(Defaults[.piiEnabledPatterns])
        guard !enabled.isEmpty else { return [] }
        let style = Self.redactionStyle()

        var regions: [MaskRegion] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            guard Self.containsPII(candidate.string, enabled: enabled) else { continue }

            // VNRecognizedTextObservation.boundingBox: normalised (0-1), origin bottom-left
            let rawBox = obs.boundingBox
            let pixelBox = CGRect(
                x:      rawBox.minX * imgW,
                y:      rawBox.minY * imgH,
                width:  rawBox.width  * imgW,
                height: rawBox.height * imgH
            )
            regions.append(MaskRegion(rule: .rect(pixelBox), style: style))
        }
        return regions
    }

    private static func redactionStyle() -> MaskStyle {
        switch Defaults[.piiRedactionStyle] {
        case "pixelate":  return .pixelate(blockSize: Defaults[.piiPixelateSize])
        case "solidFill": return .solidFill(red: 0, green: 0, blue: 0)
        default:          return .blur(radius: Defaults[.piiBlurRadius])
        }
    }

    // MARK: - Vision OCR

    private func runOCR(on image: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let results = req.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // raw text = better for API keys / hex strings

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
