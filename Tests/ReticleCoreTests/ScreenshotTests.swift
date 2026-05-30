import XCTest
@testable import ReticleCore

final class ScreenshotTests: XCTestCase {
    func testDefaultScaleFactor() {
        let image = makeTestImage()
        let shot = Screenshot(image: image, sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(shot.scaleFactor, 2.0)
    }

    func testMaskRegionCodable() throws {
        let mask = MaskRegion(rect: CGRect(x: 10, y: 20, width: 100, height: 50), style: .blur(radius: 15))
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(MaskRegion.self, from: data)
        XCTAssertEqual(decoded.id, mask.id)
        XCTAssertEqual(decoded.rect, mask.rect)
    }

    private func makeTestImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
