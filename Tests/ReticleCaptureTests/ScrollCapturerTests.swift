import CoreGraphics
import XCTest
@testable import ReticleCapture

/// Scroll capture needs a window, Accessibility permission and posted scroll
/// events — but the two parts that were wrong need none of that.  Overlap
/// detection and stitching are arithmetic over coordinate spaces, and synthetic
/// frames cut out of a known page exercise both exactly.
final class ScrollCapturerTests: XCTestCase {

    // MARK: - Geometry of the fixture

    private let bandHeight = 16
    /// The value step between consecutive bands, which has to clear the
    /// matcher's tolerance of 10.
    private let bandStep = 16
    private let pageWidth = 64
    /// 16 bands, so the page is 256 tall.
    private let bandCount = 16
    /// Taller than `refH * 4` = 128, which `findOverlap` requires.
    private let frameHeight = 160

    private var pageHeight: Int { bandHeight * bandCount }

    // MARK: - Fixtures

    /// A tall page of distinct grey bands, band 0 at the **top** in image
    /// coordinates.
    ///
    /// Grey rather than one coloured channel: the matcher samples by byte
    /// offset, so a page varying only a single channel could match everywhere
    /// and the tests would pass for the wrong reason.
    private func makePage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: pageWidth, height: pageHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))

        for band in 0..<bandCount {
            // User space is y-up, so band 0 — the topmost in image space — is
            // the highest rect here.
            let level = CGFloat(band * bandStep) / 255
            context.setFillColor(red: level, green: level, blue: level, alpha: 1)
            let top = CGFloat(pageHeight - band * bandHeight)
            context.fill(CGRect(x: 0, y: top - CGFloat(bandHeight),
                                width: CGFloat(pageWidth), height: CGFloat(bandHeight)))
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// The page as it looks scrolled down by `offset` pixels.
    private func frame(of page: CGImage, scrolledBy offset: Int) throws -> CGImage {
        try XCTUnwrap(page.cropping(to: CGRect(
            x: 0, y: offset, width: pageWidth, height: frameHeight)))
    }

    /// Reads one pixel without assuming anything about buffer row order: the
    /// pixel is cropped out in image coordinates first, so the bitmap it is
    /// drawn into has a single row and cannot be read upside down.
    private func grey(of image: CGImage, x: Int, y: Int) throws -> Int {
        let pixel = try XCTUnwrap(image.cropping(
            to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Int(bytes[0])
    }

    /// The grey value the page carries at image row `y`.
    private func expectedGrey(atPageRow y: Int) -> Int {
        (y / bandHeight) * bandStep
    }

    /// Colour round-trips through a device colour space, so bands are compared
    /// with a little slack rather than for exact equality.
    private func assertGrey(
        _ actual: Int,
        isAbout expected: Int,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            abs(actual - expected), 2,
            "\(context): sampled \(actual), expected about \(expected)",
            file: file, line: line)
    }

    // MARK: - The fixture itself

    /// If this fails, every assertion below it is meaningless — so it is
    /// checked rather than assumed.
    func testPageFixtureHasBandsTopDown() throws {
        let page = try makePage()
        XCTAssertEqual(page.width, pageWidth)
        XCTAssertEqual(page.height, pageHeight)

        for band in 0..<bandCount {
            let row = band * bandHeight + bandHeight / 2
            let sampled = try grey(of: page, x: 8, y: row)
            assertGrey(sampled, isAbout: band * bandStep, "band \(band) at row \(row)")
        }
    }

    // MARK: - findOverlap

    func testFindOverlapReportsRowsSharedWithThePreviousFrame() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()

        // Multiples of the band height, so every case lands on a band boundary
        // and the expected answer is unambiguous.
        for scroll in [16, 32, 48, 80, 96] {
            let previous = try frame(of: page, scrolledBy: 0)
            let current = try frame(of: page, scrolledBy: scroll)
            XCTAssertEqual(capturer.findOverlap(prev: previous, curr: current),
                           frameHeight - scroll,
                           "scrolled by \(scroll)")
        }
    }

    /// The case the capture loop leans on to stop.  A frame identical to the
    /// one before it overlaps completely, which makes the new strip zero rows
    /// high and trips the no-progress counter.
    ///
    /// The old arithmetic returned 32 here — the reference strip height — so an
    /// unscrollable page always looked like progress, and the capture ran all
    /// the way to `maxSteps` stitching sixty copies of the same screen.
    func testFindOverlapIsTotalWhenNothingScrolled() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let still = try frame(of: page, scrolledBy: 0)

        XCTAssertEqual(capturer.findOverlap(prev: still, curr: still), frameHeight)
    }

    func testFindOverlapGivesUpOnMismatchedSizes() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let tall = try frame(of: page, scrolledBy: 0)
        let short = try XCTUnwrap(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: frameHeight - 8)))

        XCTAssertEqual(capturer.findOverlap(prev: tall, curr: short), 0)
    }

    // MARK: - stitch

    /// The regression.  `stitch` flipped the CTM and then drew `CGImage`s into
    /// it, which mirrors each one top-to-bottom: strips in the right order with
    /// their contents upside down.
    func testStitchReconstructsThePageRightSideUp() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 48

        let first = try frame(of: page, scrolledBy: 0)
        let second = try frame(of: page, scrolledBy: scroll)
        let stitched = try capturer.stitch([first, second])

        XCTAssertEqual(stitched.width, pageWidth)
        XCTAssertEqual(stitched.height, frameHeight + scroll)

        // Every band of the reconstruction has to be the band the page carries
        // at that row.  A mirrored first strip fails at the very first one.
        for row in stride(from: bandHeight / 2, to: stitched.height, by: bandHeight) {
            let sampled = try grey(of: stitched, x: 8, y: row)
            assertGrey(sampled, isAbout: expectedGrey(atPageRow: row), "row \(row)")
        }
    }

    func testStitchOfThreeFramesKeepsGoing() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 32

        let first = try frame(of: page, scrolledBy: 0)
        let second = try frame(of: page, scrolledBy: scroll)
        let third = try frame(of: page, scrolledBy: scroll * 2)
        let stitched = try capturer.stitch([first, second, third])

        XCTAssertEqual(stitched.height, frameHeight + scroll * 2)
        for row in stride(from: bandHeight / 2, to: stitched.height, by: bandHeight) {
            let sampled = try grey(of: stitched, x: 8, y: row)
            assertGrey(sampled, isAbout: expectedGrey(atPageRow: row), "row \(row)")
        }
    }

    func testStitchOfOneFrameReturnsItUnchanged() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let only = try frame(of: page, scrolledBy: 0)

        let stitched = try capturer.stitch([only])
        XCTAssertEqual(stitched.height, frameHeight)
        let sampled = try grey(of: stitched, x: 8, y: bandHeight / 2)
        assertGrey(sampled, isAbout: 0, "top band")
    }

    func testStitchOfNothingThrows() {
        let capturer = ScrollCapturer()
        XCTAssertThrowsError(try capturer.stitch([])) { error in
            guard let scrollError = error as? ScrollCaptureError,
                  case .noFrames = scrollError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }
}
