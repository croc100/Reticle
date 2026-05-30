import XCTest
@testable import ReticleCapture
import CoreGraphics

/// Unit tests for ReticleCapture types that do NOT invoke SCStream.
/// Tests requiring screen recording permission must be run from Xcode with the entitlement.
final class CaptureModeTests: XCTestCase {

    // MARK: - CaptureMode

    func testRegionModeStoresRect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let mode = CaptureMode.region(rect)
        guard case .region(let r) = mode else {
            return XCTFail("Expected .region")
        }
        XCTAssertEqual(r, rect)
    }

    func testWindowModeStoresID() {
        let mode = CaptureMode.window(CGWindowID(42))
        guard case .window(let id) = mode else {
            return XCTFail("Expected .window")
        }
        XCTAssertEqual(id, 42)
    }

    func testFullScreenModeStoresDisplayID() {
        let mode = CaptureMode.fullScreen(displayID: CGDirectDisplayID(1))
        guard case .fullScreen(let id) = mode else {
            return XCTFail("Expected .fullScreen")
        }
        XCTAssertEqual(id, 1)
    }

    // MARK: - CaptureError descriptions

    func testErrorDescriptionNotNil() {
        let errors: [CaptureError] = [
            .permissionDenied,
            .noMatchingContent,
            .invalidFrame,
            .timeout,
            .streamFailed(underlying: NSError(domain: "test", code: 0)),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "errorDescription should not be nil for \(error)")
        }
    }
}
