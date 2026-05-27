import CentreeCapture
import CentreeCore
import Foundation

/// Executes a complete capture pipeline sequentially:
///
/// ```
/// BeforeCapture → Capture → AfterCapture → Output → AfterOutput
/// ```
///
/// Each stage is optional. Errors in any stage propagate immediately and abort the run.
public actor PipelineRunner {
    private let capturer: Capturer

    public init(capturer: Capturer = Capturer()) {
        self.capturer = capturer
    }

    // MARK: - Capture-mode entry (hotkey → SCK → pipeline)

    @discardableResult
    public func run(
        mode: CaptureMode,
        workflowID: UUID = UUID(),
        beforeCapture: [any BeforeCaptureTask] = [],
        afterCapture: [any AfterCaptureTask] = [],
        outputs: [any OutputTask],
        afterOutput: [any AfterOutputTask] = []
    ) async throws -> CaptureContext {
        var context = CaptureContext(workflowID: workflowID)
        for task in beforeCapture { try await task.execute(context: &context) }
        var screenshot = try await capturer.capture(mode: mode)
        return try await runFrom(screenshot: &screenshot, context: &context,
                                 afterCapture: afterCapture, outputs: outputs, afterOutput: afterOutput)
    }

    // MARK: - Pre-captured entry (overlay already captured the screen)
    //
    // Used by the overlay flow: the frozen screenshot is captured once for the
    // overlay background, then the same image is cropped and passed here —
    // avoiding a second capture (which would miss transient UI like tooltips).

    @discardableResult
    public func run(
        preCapture screenshot: Screenshot,
        workflowID: UUID = UUID(),
        afterCapture: [any AfterCaptureTask] = [],
        outputs: [any OutputTask],
        afterOutput: [any AfterOutputTask] = []
    ) async throws -> CaptureContext {
        var context = CaptureContext(workflowID: workflowID)
        var shot = screenshot
        return try await runFrom(screenshot: &shot, context: &context,
                                 afterCapture: afterCapture, outputs: outputs, afterOutput: afterOutput)
    }

    // MARK: - Shared tail

    private func runFrom(
        screenshot: inout Screenshot,
        context: inout CaptureContext,
        afterCapture: [any AfterCaptureTask],
        outputs: [any OutputTask],
        afterOutput: [any AfterOutputTask]
    ) async throws -> CaptureContext {
        for task in afterCapture { try await task.execute(screenshot: &screenshot, context: context) }
        for task in outputs      { try await task.execute(screenshot: screenshot,  context: &context) }
        for task in afterOutput  { try await task.execute(context: context) }
        return context
    }
}
