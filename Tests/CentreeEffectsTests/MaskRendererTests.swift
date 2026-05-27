import XCTest
@testable import CentreeEffects
import CentreeCore

final class MaskRendererTests: XCTestCase {
    func testRenderWithNoMasksReturnsOriginal() throws {
        let renderer = MaskRenderer()
        let image = makeTestImage()
        let result = try renderer.render(image: image, masks: [])
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    private func makeTestImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 100, height: 100,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
