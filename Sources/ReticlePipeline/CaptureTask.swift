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

    public init(workflowID: UUID, triggeredAt: Date = .now) {
        self.workflowID = workflowID
        self.triggeredAt = triggeredAt
        self.outputURLs = []
    }
}
