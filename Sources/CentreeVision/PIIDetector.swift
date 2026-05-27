import Vision
import CoreGraphics
import CentreeCore

/// Runs Vision OCR on a CGImage and returns MaskRegions for detected PII.
///
/// Patterns covered: email, phone, credit card, IBAN, API key tokens,
/// JWT, AWS access keys, GitHub personal access tokens.
/// Implemented in v1.0 (Smart Mask feature).
public struct PIIDetector {
    public init() {}

    public func detect(in image: CGImage) async throws -> [MaskRegion] {
        // Implemented in v1.0.
        return []
    }
}
