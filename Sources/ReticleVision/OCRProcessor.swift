import Vision
import CoreGraphics
import ReticleCore

public struct OCRProcessor {
    /// BCP-47 language codes to hint to Vision; empty = auto-detect.
    public var languages: [String] = []

    public init(languages: [String] = []) {
        self.languages = languages
    }

    /// All languages Vision supports on this system for text recognition.
    public static var supportedLanguages: [String] {
        (try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
    }

    public func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
