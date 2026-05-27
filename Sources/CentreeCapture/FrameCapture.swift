import ScreenCaptureKit
import CoreMedia
import Foundation

/// `SCStreamOutput` + `SCStreamDelegate` that resolves a single `CMSampleBuffer`
/// via a `CheckedContinuation`.
///
/// One instance is created per capture call and discarded once the frame arrives.
/// Thread-safety is provided by `NSLock`; `@unchecked Sendable` is safe here because
/// the lock guards the only mutable state (`continuation`).
final class FrameCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<CMSampleBuffer, Error>?

    // MARK: - Public

    /// Suspends until the stream delivers its first *complete* frame, then returns it.
    func waitForFrame() async throws -> CMSampleBuffer {
        try await withCheckedThrowingContinuation { cont in
            lock.withLock { continuation = cont }
        }
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

        resume(with: .success(buffer))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        resume(with: .failure(CaptureError.streamFailed(underlying: error)))
    }

    // MARK: - Private

    private func resume(with result: Result<CMSampleBuffer, Error>) {
        let cont = lock.withLock { () -> CheckedContinuation<CMSampleBuffer, Error>? in
            let c = continuation
            continuation = nil
            return c
        }
        cont?.resume(with: result)
    }

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

// MARK: - NSLock convenience

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
