import CoreGraphics
import XCTest
@testable import ReticleCapture

/// Laying displays out into one image is arithmetic over coordinate spaces, so
/// it is tested with made-up arrangements rather than whatever monitors the CI
/// runner has — which is none.
///
/// Orientation is the thing under test as much as position: one tile here is
/// two-toned on purpose, because a flipped CTM would place the tiles correctly
/// and mirror what is inside each of them.
final class DisplayCompositorTests: XCTestCase {

    // MARK: - Colours

    private let red = (255, 0, 0)
    private let green = (0, 255, 0)
    private let blue = (0, 0, 255)
    private let black = (0, 0, 0)

    // MARK: - Fixtures

    /// An image whose top half is `top` and bottom half is `bottom`, in image
    /// coordinates — so the top half is what should appear at the top.
    private func makeImage(
        width: Int,
        height: Int,
        top: (Int, Int, Int),
        bottom: (Int, Int, Int)? = nil
    ) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))

        func fill(_ colour: (Int, Int, Int), _ rect: CGRect) {
            context.setFillColor(
                red: CGFloat(colour.0) / 255,
                green: CGFloat(colour.1) / 255,
                blue: CGFloat(colour.2) / 255,
                alpha: 1)
            context.fill(rect)
        }

        guard let bottom else {
            fill(top, CGRect(x: 0, y: 0, width: width, height: height))
            return try XCTUnwrap(context.makeImage())
        }
        // User space is y-up, so the top half of the image is the upper rect.
        let half = CGFloat(height) / 2
        fill(bottom, CGRect(x: 0, y: 0, width: CGFloat(width), height: half))
        fill(top, CGRect(x: 0, y: half, width: CGFloat(width), height: half))
        return try XCTUnwrap(context.makeImage())
    }

    /// Reads one pixel with no assumption about buffer row order: the pixel is
    /// cropped out in image coordinates first, so the bitmap it is drawn into
    /// has a single row and cannot be read upside down.
    private func pixel(of image: CGImage, x: Int, y: Int) throws -> (Int, Int, Int) {
        let cropped = try XCTUnwrap(image.cropping(
            to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func assertPixel(
        _ image: CGImage,
        x: Int,
        y: Int,
        is expected: (Int, Int, Int),
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try pixel(of: image, x: x, y: y)
        let delta = max(abs(actual.0 - expected.0),
                        max(abs(actual.1 - expected.1), abs(actual.2 - expected.2)))
        XCTAssertLessThanOrEqual(
            delta, 2,
            "\(context) at (\(x), \(y)): got \(actual), expected \(expected)",
            file: file, line: line)
    }

    // MARK: - Side by side

    func testTwoDisplaysSideBySide() throws {
        let left = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        let right = DisplayCompositor.Tile(
            placement: CGRect(x: 100, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: green))

        let composed = try DisplayCompositor.composite(
            tiles: [left, right], size: CGSize(width: 200, height: 100), scale: 1)

        XCTAssertEqual(composed.width, 200)
        XCTAssertEqual(composed.height, 100)
        try assertPixel(composed, x: 50, y: 50, is: red, "left display")
        try assertPixel(composed, x: 150, y: 50, is: green, "right display")
    }

    // MARK: - Stacked, which is where orientation shows

    /// A display physically above another has a **higher** y origin in AppKit's
    /// screen space, and has to end up at the **top** of the image. Its own
    /// contents have to stay the right way up too, which is why the upper tile
    /// is two-toned.
    func testADisplayAboveLandsAtTheTopTheRightWayUp() throws {
        let lower = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        let upper = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 100, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: green, bottom: blue))

        let composed = try DisplayCompositor.composite(
            tiles: [lower, upper], size: CGSize(width: 100, height: 200), scale: 1)

        XCTAssertEqual(composed.height, 200)
        // The upper display occupies image rows 0..<100, green over blue.
        try assertPixel(composed, x: 50, y: 25, is: green, "upper display, its top half")
        try assertPixel(composed, x: 50, y: 75, is: blue, "upper display, its bottom half")
        // The lower display is the bottom half of the image.
        try assertPixel(composed, x: 50, y: 150, is: red, "lower display")
    }

    // MARK: - Scale

    func testScaleMultipliesThePixelCanvasAndKeepsTheLayout() throws {
        let lower = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        let upper = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 100, width: 100, height: 100),
            image: try makeImage(width: 200, height: 200, top: green, bottom: blue))

        let composed = try DisplayCompositor.composite(
            tiles: [lower, upper], size: CGSize(width: 100, height: 200), scale: 2)

        XCTAssertEqual(composed.width, 200)
        XCTAssertEqual(composed.height, 400)
        try assertPixel(composed, x: 100, y: 50, is: green, "upper display, its top half")
        try assertPixel(composed, x: 100, y: 150, is: blue, "upper display, its bottom half")
        try assertPixel(composed, x: 100, y: 300, is: red, "lower display")
    }

    // MARK: - Gaps

    /// Displays need not tile the plane. A diagonal arrangement leaves two
    /// corners with no display in them, and a single rectangular image has to
    /// put something there.
    func testAreaNoDisplayOccupiesIsBlack() throws {
        let lowerLeft = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        let upperRight = DisplayCompositor.Tile(
            placement: CGRect(x: 100, y: 100, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: green))

        let composed = try DisplayCompositor.composite(
            tiles: [lowerLeft, upperRight], size: CGSize(width: 200, height: 200), scale: 1)

        try assertPixel(composed, x: 50, y: 150, is: red, "lower-left display")
        try assertPixel(composed, x: 150, y: 50, is: green, "upper-right display")
        try assertPixel(composed, x: 50, y: 50, is: black, "upper-left gap")
        try assertPixel(composed, x: 150, y: 150, is: black, "lower-right gap")
    }

    // MARK: - Refusals

    private func assertThrows(
        _ expression: () throws -> CGImage,
        _ expected: CaptureError,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("\(context): expected a throw", file: file, line: line)
        } catch let error as CaptureError {
            XCTAssertEqual(error.errorDescription, expected.errorDescription,
                           context, file: file, line: line)
        } catch {
            XCTFail("\(context): unexpected \(error)", file: file, line: line)
        }
    }

    func testNoTilesThrows() throws {
        assertThrows(
            { try DisplayCompositor.composite(
                tiles: [], size: CGSize(width: 100, height: 100), scale: 1) },
            .noMatchingContent, "no tiles")
    }

    func testNonPositiveScaleThrows() throws {
        let tile = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        for scale in [CGFloat(0), -1] {
            assertThrows(
                { try DisplayCompositor.composite(
                    tiles: [tile], size: CGSize(width: 100, height: 100), scale: scale) },
                .compositeFailed, "scale \(scale)")
        }
    }

    func testEmptySizeThrows() throws {
        let tile = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        assertThrows(
            { try DisplayCompositor.composite(tiles: [tile], size: .zero, scale: 2) },
            .compositeFailed, "zero size")
    }

    /// A tile with an empty rect is skipped rather than refused: a display that
    /// disappeared between being listed and being placed should not take the
    /// whole capture down with it.
    func testAnEmptyPlacementIsSkipped() throws {
        let real = DisplayCompositor.Tile(
            placement: CGRect(x: 0, y: 0, width: 100, height: 100),
            image: try makeImage(width: 100, height: 100, top: red))
        let vanished = DisplayCompositor.Tile(
            placement: .zero,
            image: try makeImage(width: 10, height: 10, top: green))

        let composed = try DisplayCompositor.composite(
            tiles: [real, vanished], size: CGSize(width: 100, height: 100), scale: 1)
        try assertPixel(composed, x: 50, y: 50, is: red, "the display that is still there")
    }
}
