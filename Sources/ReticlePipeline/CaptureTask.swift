import ReticleCore
import Foundation

// MARK: - Pipeline stages

/// A discrete step executed before the capture source fires.
public protocol BeforeCaptureTask: Sendable {
    func execute(context: inout CaptureContext) async throws
}

/// A discrete step executed after the raw CGImage is available.
public protocol AfterCaptureTask: Sendable {
    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws
}

/// A discrete step that writes the final image somewhere (file, clipboard, uploader).
/// Receives `context` as `inout` so it can append to `context.outputURLs`.
public protocol OutputTask: Sendable {
    func execute(screenshot: Screenshot, context: inout CaptureContext) async throws
}

/// A discrete step executed after all outputs complete (notify, copy URL, …).
public protocol AfterOutputTask: Sendable {
    func execute(context: CaptureContext) async throws
}

// MARK: - Context

/// Mutable bag of metadata threaded through the entire pipeline.
public struct CaptureContext: Sendable {
    public var workflowID: UUID
    public var triggeredAt: Date
    public var outputURLs: [URL]
    /// The screenshot as it stood once every ``AfterCaptureTask`` had run, so
    /// after static masks, PII redaction, the border and the watermark.
    ///
    /// Anything that consumes the capture *outside* the pipeline — uploads, OCR,
    /// the history thumbnail, pin-to-screen — has to read the image from here.
    /// Reaching back to the pre-pipeline `CGImage` publishes the unredacted
    /// original, which is the one thing redaction exists to prevent.
    public var finalScreenshot: Screenshot?

    public init(workflowID: UUID, triggeredAt: Date = .now) {
        self.workflowID = workflowID
        self.triggeredAt = triggeredAt
        self.outputURLs = []
        self.finalScreenshot = nil
    }
}
