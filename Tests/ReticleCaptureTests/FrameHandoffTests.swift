import Foundation
import XCTest
@testable import ReticleCapture

/// `FrameHandoff` is the piece that decides whether a frame delivered by
/// ScreenCaptureKit actually reaches the task that asked for it.  Both
/// orderings are exercised explicitly, because the one that used to lose the
/// frame — delivery first — is also the one that normally succeeds anyway, by
/// accident, when a second frame happens to follow.
final class FrameHandoffTests: XCTestCase {

    // MARK: - Ordering

    /// The regression: the stream is started before `waitForFrame()` runs, so
    /// the first frame can be delivered before anything is waiting for it.
    func testDeliveryBeforeWaitIsStillReturned() async throws {
        let handoff = FrameHandoff<Int>()
        handoff.deliver(.success(7))
        XCTAssertTrue(handoff.hasResult)
        XCTAssertFalse(handoff.isWaiting)

        let value = try await handoff.value()
        XCTAssertEqual(value, 7)
    }

    /// The ordering that always worked, kept so a fix for the other one cannot
    /// quietly break it.
    func testDeliveryWhileWaitingIsReturned() async throws {
        let handoff = FrameHandoff<Int>()

        async let received = handoff.value()

        // Spin until the child task has actually suspended, so this test pins
        // down the ordering it means to and not whichever one it happens to
        // win.  Bounded, so a handoff that never suspends fails the assertion
        // below rather than hanging the run.
        var spins = 0
        while !handoff.isWaiting, spins < 1_000_000 {
            spins += 1
            await Task.yield()
        }
        XCTAssertTrue(handoff.isWaiting, "expected value() to have suspended")

        handoff.deliver(.success(11))
        let value = try await received
        XCTAssertEqual(value, 11)
    }

    // MARK: - Failures

    /// `didStopWithError` can also fire before anything waits.  It used to be
    /// discarded, and the capture then failed on the timeout five seconds
    /// later, reporting the wrong reason.
    func testFailureBeforeWaitIsThrown() async {
        let handoff = FrameHandoff<Int>()
        handoff.deliver(.failure(CaptureError.permissionDenied))

        do {
            _ = try await handoff.value()
            XCTFail("expected the stored failure to be thrown")
        } catch let error as CaptureError {
            guard case .permissionDenied = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - First result wins

    func testFirstResultWins() async throws {
        let handoff = FrameHandoff<Int>()
        handoff.deliver(.success(1))
        handoff.deliver(.success(2))
        handoff.deliver(.failure(CaptureError.timeout))

        let value = try await handoff.value()
        XCTAssertEqual(value, 1, "a later frame must not replace the one already accepted")
    }

    // MARK: - Second waiter

    /// The stream keeps running until `stopCapture()` takes effect, so a second
    /// wait is possible; it must fail rather than block forever.
    func testSecondWaitFailsRatherThanHanging() async throws {
        let handoff = FrameHandoff<Int>()
        handoff.deliver(.success(3))

        let first = try await handoff.value()
        XCTAssertEqual(first, 3)

        do {
            _ = try await handoff.value()
            XCTFail("a second wait should not succeed")
        } catch let error as CaptureError {
            guard case .frameAlreadyConsumed = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Cancellation

    /// A capture abandoned by its timeout cancels the waiting task.  Without a
    /// cancellation handler the continuation stayed suspended for the lifetime
    /// of the process, one per failed capture.
    func testCancellationResolvesTheWait() async {
        let handoff = FrameHandoff<Int>()

        let waiter = Task { try await handoff.value() }
        var spins = 0
        while !handoff.isWaiting, spins < 1_000_000 {
            spins += 1
            await Task.yield()
        }
        XCTAssertTrue(handoff.isWaiting, "expected value() to have suspended")
        waiter.cancel()

        let result = await waiter.result
        switch result {
        case .success(let value):
            XCTFail("expected cancellation, got \(value)")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "unexpected \(error)")
        }
    }
}
