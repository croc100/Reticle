import CoreGraphics
import XCTest
@testable import ReticleCapture

/// `Capturer` needs the screen-recording entitlement for anything that reaches
/// `SCStream`, so what is covered here is the part that does not: the shape of
/// the multi-display entry point before any stream is created.
final class CapturerTests: XCTestCase {

    /// `SCShareableContent` returning no displays is a real state — every
    /// screen asleep, or a headless machine — and the overlay flow guards on
    /// the empty list, so this must come back empty rather than throw or trap.
    func testCaptureNoDisplaysReturnsEmpty() async throws {
        let capturer = Capturer()
        let shots = try await capturer.capture(displays: [])
        XCTAssertTrue(shots.isEmpty)
    }
}
