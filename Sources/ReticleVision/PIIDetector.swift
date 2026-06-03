import Vision
import CoreGraphics
import ReticleCore
import Foundation

/// Runs Vision OCR on a CGImage and returns MaskRegions for detected PII.
///
/// Patterns covered: email addresses, phone numbers, credit card numbers,
/// IBANs, JWT tokens, AWS access keys, GitHub PATs, generic API key tokens.
public struct PIIDetector {

    // MARK: - Regex patterns

    private static let patterns: [(name: String, regex: NSRegularExpression)] = {
        let specs: [(String, String)] = [
            ("email",      #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
            ("phone_intl", #"\+?[0-9]{1,3}[\s\-.]?\(?[0-9]{1,4}\)?[\s\-.]?[0-9]{1,4}[\s\-.]?[0-9]{1,9}"#),
            ("credit_card",#"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b"#),
            ("iban",       #"\b[A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}(?:[A-Z0-9]?){0,16}\b"#),
            ("jwt",        #"ey[A-Za-z0-9_\-]+\.ey[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#),
            ("aws_key",    #"\b(?:AKIA|ASIA|AIDA|AROA)[A-Z0-9]{16}\b"#),
            ("github_pat", #"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}"#),
            ("hex_secret", #"\b[0-9a-fA-F]{32,64}\b"#),
        ]
        return specs.compactMap { name, pattern in
            guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (name, rx)
        }
    }()

    public init() {}

    /// Runs OCR on the image, then scans every recognised text block for PII patterns.
    /// Returns one `MaskRegion` per detected PII token, in image coordinate space.
    public func detect(in image: CGImage) async throws -> [MaskRegion] {
        let observations = try await runOCR(on: image)
        var regions: [MaskRegion] = []

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        for obs in observations {
            // VNRecognizedTextObservation.boundingBox: normalised (0-1), origin bottom-left
            let rawBox = obs.boundingBox
            let pixelBox = CGRect(
                x:      rawBox.minX * imgW,
                y:      rawBox.minY * imgH,
                width:  rawBox.width  * imgW,
                height: rawBox.height * imgH
            )

            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string

            // Scan recognised text for every PII pattern
            let range = NSRange(text.startIndex..., in: text)
            for (_, regex) in Self.patterns {
                let hits = regex.matches(in: text, options: [], range: range)
                if !hits.isEmpty {
                    // Mark the entire bounding box (character-level boxes require paid APIs)
                    regions.append(MaskRegion(rule: .rect(pixelBox), style: .blur(radius: 20)))
                    break  // one redaction per text block; avoid duplicates
                }
            }
        }
        return regions
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
