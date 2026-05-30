import XCTest
@testable import ReticlePipeline

final class CaptureContextTests: XCTestCase {
    func testInitialOutputURLsAreEmpty() {
        let ctx = CaptureContext(workflowID: UUID())
        XCTAssertTrue(ctx.outputURLs.isEmpty)
    }

    func testMutatingOutputURLs() {
        var ctx = CaptureContext(workflowID: UUID())
        ctx.outputURLs.append(URL(fileURLWithPath: "/tmp/test.png"))
        XCTAssertEqual(ctx.outputURLs.count, 1)
    }
}
