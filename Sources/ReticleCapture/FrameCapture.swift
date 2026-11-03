import ScreenCaptureKit
import CoreMedia
import Foundation

/// `SCStreamOutput` + `SCStreamDelegate` that resolves a single `CMSampleBuffer`.
///
/// One instance is created per capture call and discarded once the frame
/// arrives.  The handoff to the waiting task — and the ordering problem that
/// comes with the stream being started before anything waits on it — lives in
/// ``FrameHandoff``.  `@unchecked Sendable` because the only stored property is
/// an immutable reference to that handoff, which is itself safe to share.
final class FrameCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    private let handoff = FrameHandoff<CMSampleBuffer>()

    // MARK: - Public

    /// Suspends until the stream delivers its first *complete* frame, then returns it.
    ///
    /// Safe to call after the frame has already arrived: it returns immediately
    /// in that case rather than waiting for a second one.
    func waitForFrame() async throws -> CMSampleBuffer {
        try await handoff.value()
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer buffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Only handle screen frames; ignore audio (if enabled elsewhere).
        guard type == .screen, buffer.isValid else { return }

        // SCK delivers a few "idle" frames before content is ready — skip them.
        guard isComplete(buffer) else { return }

        handoff.deliver(.success(buffer))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        handoff.deliver(.failure(CaptureError.streamFailed(underlying: error)))
    }

    // MARK: - Private

    private func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                buffer, createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}
