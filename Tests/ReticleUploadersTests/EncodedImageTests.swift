import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import ReticleUploaders

/// `EncodedImage` exists so one capture bound for several destinations is
/// encoded once rather than once per uploader. These tests check the bytes it
/// hands out are a real PNG, since every destination now trusts them blindly.
final class EncodedImageTests: XCTestCase {

    func testPNGEncodingReportsPNGMetadata() throws {
        let encoded = try EncodedImage.png(from: try makeImage(width: 4, height: 3))
        XCTAssertEqual(encoded.contentType, "image/png")
        XCTAssertEqual(encoded.fileExtension, "png")
        XCTAssertFalse(encoded.data.isEmpty)
    }

    func testPNGEncodingWritesThePNGSignature() throws {
        let encoded = try EncodedImage.png(from: try makeImage(width: 4, height: 3))
        // The 8-byte PNG signature — proof these are encoded bytes, not raw pixels.
        XCTAssertEqual(Array(encoded.data.prefix(8)),
                       [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testEncodedBytesDecodeBackToTheSameDimensions() throws {
        let encoded = try EncodedImage.png(from: try makeImage(width: 11, height: 7))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded.data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 11)
        XCTAssertEqual(decoded.height, 7)
    }

    func testMemberwiseInitKeepsItsValues() {
        let encoded = EncodedImage(data: Data([1, 2, 3]), contentType: "image/webp",
                                   fileExtension: "webp")
        XCTAssertEqual(encoded.data, Data([1, 2, 3]))
        XCTAssertEqual(encoded.contentType, "image/webp")
        XCTAssertEqual(encoded.fileExtension, "webp")
    }
}

// MARK: - Helpers

private enum TestImageError: Error {
    case contextUnavailable
    case imageUnavailable
}

private func makeImage(width: Int, height: Int) throws -> CGImage {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestImageError.contextUnavailable
    }
    guard let image = ctx.makeImage() else {
        throw TestImageError.imageUnavailable
    }
    return image
}
