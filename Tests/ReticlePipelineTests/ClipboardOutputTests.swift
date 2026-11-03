import AppKit
import CoreGraphics
import ImageIO
import XCTest
@testable import ReticlePipeline

/// `NSPasteboard` itself needs a running app, so what is tested here is the
/// part that decides what lands on it: the representations `ClipboardOutput`
/// advertises and the bytes behind each one.
final class ClipboardOutputTests: XCTestCase {

    // MARK: - Fixtures

    /// A flat fill, so the PNG/TIFF size comparison below has something
    /// compressible to work with — which is also the realistic case, since a
    /// screenshot is mostly flat UI.
    private func makeImage(width: Int = 512, height: Int = 512) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        return try XCTUnwrap(raw as? [CFString: Any])
    }

    // MARK: - PNG

    /// The regression: `writeObjects([NSImage])` advertised only TIFF and PDF,
    /// so an app that asked the pasteboard for PNG got nothing at all.
    func testPNGIsRealPNG() throws {
        let image = try makeImage()
        let data = try XCTUnwrap(
            ClipboardImageOwner.data(from: image, as: .png, scaleFactor: 2))

        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(data.prefix(8)), signature)

        let props = try properties(of: data)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 512)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 512)
    }

    // MARK: - TIFF

    func testTIFFIsRealTIFF() throws {
        let image = try makeImage()
        let data = try XCTUnwrap(
            ClipboardImageOwner.data(from: image, as: .tiff, scaleFactor: 2))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source)) as String
        XCTAssertEqual(type, "public.tiff")

        let props = try properties(of: data)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 512)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 512)
    }

    // MARK: - DPI

    /// A Retina capture is twice as many pixels as points, so without the DPI
    /// stamp it pastes at double size.
    func testScaleFactorIsStampedAsDPI() throws {
        let image = try makeImage(width: 64, height: 64)
        for (scale, expected) in [(1.0, 72.0), (2.0, 144.0)] {
            let data = try XCTUnwrap(
                ClipboardImageOwner.data(from: image, as: .png, scaleFactor: scale))
            let props = try properties(of: data)
            let dpi = try XCTUnwrap(props[kCGImagePropertyDPIWidth] as? Double)
            // PNG stores pixels per metre, so the round trip is not exact.
            XCTAssertEqual(dpi, expected, accuracy: 1.0, "scale \(scale)")
        }
    }

    // MARK: - Why TIFF is the lazy one

    /// The reason TIFF is provided on demand rather than written up front.
    /// TIFF here is uncompressed, so it is about `width * height * 4` bytes
    /// whatever the content; PNG of the same frame is a fraction of that.
    func testTIFFIsFarLargerThanPNG() throws {
        let image = try makeImage()
        let png = try XCTUnwrap(
            ClipboardImageOwner.data(from: image, as: .png, scaleFactor: 2))
        let tiff = try XCTUnwrap(
            ClipboardImageOwner.data(from: image, as: .tiff, scaleFactor: 2))

        XCTAssertLessThan(
            png.count * 10, tiff.count,
            "PNG \(png.count) B vs TIFF \(tiff.count) B — if these are close, "
            + "writing TIFF eagerly would cost little and this could be simplified")
    }
}
