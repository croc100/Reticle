import Foundation

/// A one-shot handoff of a value from a callback to an `await`.
///
/// The producer can fire before the consumer suspends.  `SCStream` is started
/// before anything waits on it and delivers frames on its own queue, so the
/// first frame can land while the caller is still on its way to `await`.
/// Keeping only the continuation dropped such a frame, and the capture then
/// waited for one the system had no reason to send: on a static screen nothing
/// changes, so ScreenCaptureKit has nothing further to deliver and the capture
/// failed on the five-second timeout holding a frame it had already been given.
/// The same applied to `didStopWithError` — an early failure was lost and
/// surfaced five seconds later as a timeout instead.
///
/// So a result is recorded whether or not anyone is waiting yet, and the first
/// one wins.  `@unchecked Sendable` because the lock guards all mutable state;
/// `Value` is deliberately unconstrained, since `CMSampleBuffer` is not
/// `Sendable` but is consumed by the single waiting task before it escapes.
final class FrameHandoff<Value>: @unchecked Sendable {

    private enum State {
        /// Nothing has happened yet.
        case idle
        /// A task is suspended in ``value()``.
        case waiting(CheckedContinuation<Value, Error>)
        /// A result arrived before anyone waited for it.
        case pending(Result<Value, Error>)
        /// The result has been handed to its waiter.
        case consumed
    }

    private let lock = NSLock()
    private var state: State = .idle

    // MARK: - Consumer

    /// Suspends until ``deliver(_:)`` is called, or returns straight away when
    /// it already has been.
    ///
    /// A second caller gets ``CaptureError/frameAlreadyConsumed`` rather than
    /// hanging on a result that will never come twice.  Cancellation resolves
    /// the wait too, so a capture abandoned by its timeout does not leave the
    /// continuation suspended for the lifetime of the process.
    func value() async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                let immediate: Result<Value, Error>?
                switch state {
                case .idle:
                    state = .waiting(continuation)
                    immediate = nil
                case .pending(let result):
                    state = .consumed
                    immediate = result
                case .waiting, .consumed:
                    immediate = Result.failure(CaptureError.frameAlreadyConsumed)
                }
                lock.unlock()
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            self.deliver(.failure(CancellationError()))
        }
    }

    // MARK: - Producer

    /// Hands `result` to the waiting task, or holds on to it until one arrives.
    ///
    /// Later calls are ignored: the first complete frame — or the first
    /// failure — wins, and the stream keeps delivering frames until
    /// `stopCapture()` has actually taken effect.
    func deliver(_ result: Result<Value, Error>) {
        lock.lock()
        let waiter: CheckedContinuation<Value, Error>?
        switch state {
        case .idle:
            state = .pending(result)
            waiter = nil
        case .waiting(let continuation):
            state = .consumed
            waiter = continuation
        case .pending, .consumed:
            waiter = nil
        }
        lock.unlock()
        waiter?.resume(with: result)
    }

    // MARK: - Introspection

    /// Whether a result has arrived, whoever ends up receiving it.
    var hasResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .pending, .consumed: return true
        case .idle, .waiting:     return false
        }
    }

    /// Whether a task is currently suspended in ``value()``.
    ///
    /// Only the tests use this, to pin down which of the two orderings they are
    /// exercising — the race is invisible otherwise, which is how it survived.
    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .waiting = state { return true }
        return false
    }
}
