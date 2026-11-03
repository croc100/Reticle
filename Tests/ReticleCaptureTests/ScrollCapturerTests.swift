import CoreGraphics
import XCTest
@testable import ReticleCapture

/// Scroll capture needs a window, Accessibility permission and posted scroll
/// events — but the parts that decide whether the result is right need none of
/// that.  Alignment and stitching are arithmetic over coordinate spaces, and
/// synthetic frames cut out of a known page exercise both exactly.
///
/// Frames here are built the way a real window shows a page: an optional fixed
/// header, a window onto the scrolling content, and an optional fixed footer.
/// That is what makes the sticky-band cases testable at all.
final class ScrollCapturerTests: XCTestCase {

    // MARK: - Geometry of the fixture

    private let bandHeight = 16
    /// The value step between consecutive bands, which has to clear the row
    /// matcher's tolerance of 10.
    private let bandStep = 16
    /// 16 bands, so the page is 256 tall.
    private let bandCount = 16
    private let pageWidth = 64
    private let frameHeight = 160

    private var pageHeight: Int { bandHeight * bandCount }

    /// Distinctive, and nothing like a grey band, so a sticky band is never
    /// confused with page content.
    private let headerColour: (red: CGFloat, green: CGFloat, blue: CGFloat) = (1, 0, 0)
    private let footerColour: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 1)

    // MARK: - Fixtures

    private func makeContext(height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil, width: pageWidth, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    /// A tall page of distinct grey bands, band 0 at the **top** in image
    /// coordinates.
    ///
    /// Grey rather than one coloured channel: the matcher samples by byte
    /// offset, so a page varying only a single channel could match everywhere
    /// and these tests would pass for the wrong reason.
    private func makePage() throws -> CGImage {
        let context = try makeContext(height: pageHeight)
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

    /// A frame as a window would show the page: `header` fixed rows at the top,
    /// `footer` fixed rows at the bottom, and the page scrolled by `offset` in
    /// between.
    private func makeFrame(
        of page: CGImage,
        scrolledBy offset: Int,
        header: Int = 0,
        footer: Int = 0
    ) throws -> CGImage {
        let context = try makeContext(height: frameHeight)
        let windowHeight = frameHeight - header - footer

        let slice = try XCTUnwrap(page.cropping(to: CGRect(
            x: 0, y: offset, width: pageWidth, height: windowHeight)))
        // Image rows [header, frameHeight - footer) are user y
        // [footer, footer + windowHeight) in a y-up context.
        context.draw(slice, in: CGRect(x: 0, y: CGFloat(footer),
                                       width: CGFloat(pageWidth),
                                       height: CGFloat(windowHeight)))

        if header > 0 {
            context.setFillColor(red: headerColour.red, green: headerColour.green,
                                 blue: headerColour.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: CGFloat(frameHeight - header),
                                width: CGFloat(pageWidth), height: CGFloat(header)))
        }
        if footer > 0 {
            context.setFillColor(red: footerColour.red, green: footerColour.green,
                                 blue: footerColour.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0,
                                width: CGFloat(pageWidth), height: CGFloat(footer)))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func makeSolid(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try makeContext(height: frameHeight)
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pageWidth), height: CGFloat(frameHeight)))
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: - Reading pixels back

    /// Reads one pixel without assuming anything about buffer row order: the
    /// pixel is cropped out in image coordinates first, so the bitmap it is
    /// drawn into has a single row and cannot be read upside down.
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

    /// The grey value the page carries at image row `y`.
    private func expectedGrey(atPageRow y: Int) -> Int {
        (y / bandHeight) * bandStep
    }

    /// Colour round-trips through a device colour space, so pixels are compared
    /// with a little slack rather than for exact equality.
    private func assertPixel(
        _ actual: (Int, Int, Int),
        isAbout expected: (Int, Int, Int),
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let delta = max(abs(actual.0 - expected.0),
                        max(abs(actual.1 - expected.1), abs(actual.2 - expected.2)))
        XCTAssertLessThanOrEqual(
            delta, 2,
            "\(context): sampled \(actual), expected about \(expected)",
            file: file, line: line)
    }

    private func assertGrey(
        _ image: CGImage,
        row: Int,
        isAbout level: Int,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sampled = try pixel(of: image, x: pageWidth / 2, y: row)
        assertPixel(sampled, isAbout: (level, level, level), context, file: file, line: line)
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
            try assertGrey(page, row: row, isAbout: band * bandStep,
                           "band \(band) at row \(row)")
        }
    }

    func testFrameFixturePlacesHeaderFooterAndWindow() throws {
        let page = try makePage()
        let frame = try makeFrame(of: page, scrolledBy: 32, header: 24, footer: 24)

        let headerPixel = try pixel(of: frame, x: pageWidth / 2, y: 12)
        assertPixel(headerPixel, isAbout: (255, 0, 0), "header")
        let footerPixel = try pixel(of: frame, x: pageWidth / 2, y: frameHeight - 12)
        assertPixel(footerPixel, isAbout: (0, 0, 255), "footer")
        // Frame row 24 is the first scrolling row, showing page row 32.
        try assertGrey(frame, row: 24 + bandHeight / 2,
                       isAbout: expectedGrey(atPageRow: 32 + bandHeight / 2),
                       "first scrolling band")
    }

    // MARK: - align, without sticky bands

    func testAlignReportsScrollDistance() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()

        for scroll in [16, 32, 48] {
            let previous = try makeFrame(of: page, scrolledBy: 0)
            let current = try makeFrame(of: page, scrolledBy: scroll)
            let alignment = try XCTUnwrap(capturer.align(prev: previous, curr: current),
                                          "scrolled by \(scroll)")
            XCTAssertEqual(alignment.stickyTop, 0, "scrolled by \(scroll)")
            XCTAssertEqual(alignment.stickyBottom, 0, "scrolled by \(scroll)")
            XCTAssertEqual(alignment.scrolled, scroll)
            XCTAssertEqual(alignment.overlap, frameHeight - scroll)
        }
    }

    /// The case the capture loop leans on to stop: a frame identical to the one
    /// before it has not scrolled at all.
    func testAlignReportsNoMovementForAnIdenticalFrame() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let still = try makeFrame(of: page, scrolledBy: 0)

        let alignment = try XCTUnwrap(capturer.align(prev: still, curr: still))
        XCTAssertEqual(alignment.scrolled, 0)
        XCTAssertEqual(alignment.overlap, alignment.scrollingHeight)
    }

    func testAlignGivesUpOnMismatchedSizes() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let full = try makeFrame(of: page, scrolledBy: 0)
        let short = try XCTUnwrap(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: frameHeight - 8)))

        XCTAssertNil(capturer.align(prev: full, curr: short))
    }

    func testAlignGivesUpWhenFramesShareNothing() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let frame = try makeFrame(of: page, scrolledBy: 0)
        // Red, so no grey band can match it on all three channels.
        let unrelated = try makeSolid(red: 1, green: 0, blue: 0)

        XCTAssertNil(capturer.align(prev: frame, curr: unrelated))
    }

    // MARK: - align, with sticky bands

    /// What this change is for.  A header and a footer pinned to the same rows
    /// of every frame are identical in both, so the old matcher found the
    /// footer matching itself and reported an enormous overlap — the capture
    /// then concluded the page had stopped moving.
    func testAlignMeasuresStickyHeaderAndFooter() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let header = 24
        let footer = 24
        let scroll = 32

        let previous = try makeFrame(of: page, scrolledBy: 0, header: header, footer: footer)
        let current = try makeFrame(of: page, scrolledBy: scroll,
                                    header: header, footer: footer)

        let alignment = try XCTUnwrap(capturer.align(prev: previous, curr: current))
        XCTAssertEqual(alignment.stickyTop, header)
        XCTAssertEqual(alignment.stickyBottom, footer)
        XCTAssertEqual(alignment.scrollingHeight, frameHeight - header - footer)
        XCTAssertEqual(alignment.scrolled, scroll,
                       "the sticky bands must not be read as overlap")
    }

    /// Only a footer, which is the common case: a cookie bar or a floating
    /// action button.
    func testAlignMeasuresAStickyFooterAlone() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 32

        let previous = try makeFrame(of: page, scrolledBy: 0, footer: 32)
        let current = try makeFrame(of: page, scrolledBy: scroll, footer: 32)

        let alignment = try XCTUnwrap(capturer.align(prev: previous, curr: current))
        XCTAssertEqual(alignment.stickyTop, 0)
        XCTAssertEqual(alignment.stickyBottom, 32)
        XCTAssertEqual(alignment.scrolled, scroll)
    }

    // MARK: - stitch

    /// `stitch` used to flip the CTM and then draw `CGImage`s into it, which
    /// mirrors each one top-to-bottom: strips in the right order with their
    /// contents upside down.
    func testStitchReconstructsThePageRightSideUp() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 48

        let first = try makeFrame(of: page, scrolledBy: 0)
        let second = try makeFrame(of: page, scrolledBy: scroll)
        let stitched = try capturer.stitch([first, second])

        XCTAssertEqual(stitched.width, pageWidth)
        XCTAssertEqual(stitched.height, frameHeight + scroll)

        // A mirrored first strip fails at the very first band.
        for row in stride(from: bandHeight / 2, to: stitched.height, by: bandHeight) {
            try assertGrey(stitched, row: row, isAbout: expectedGrey(atPageRow: row),
                           "row \(row)")
        }
    }

    func testStitchOfThreeFramesKeepsGoing() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 32

        let frames = try [0, scroll, scroll * 2].map {
            try makeFrame(of: page, scrolledBy: $0)
        }
        let stitched = try capturer.stitch(frames)

        XCTAssertEqual(stitched.height, frameHeight + scroll * 2)
        for row in stride(from: bandHeight / 2, to: stitched.height, by: bandHeight) {
            try assertGrey(stitched, row: row, isAbout: expectedGrey(atPageRow: row),
                           "row \(row)")
        }
    }

    /// The whole point, end to end: a page with a sticky header and footer
    /// reconstructs with the header once at the top, the page content
    /// continuous through the middle, and the footer once at the bottom.
    func testStitchPlacesStickyBandsOnceEach() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let header = 24
        let footer = 24
        let scroll = 32
        let window = frameHeight - header - footer

        let first = try makeFrame(of: page, scrolledBy: 0, header: header, footer: footer)
        let second = try makeFrame(of: page, scrolledBy: scroll,
                                   header: header, footer: footer)
        let stitched = try capturer.stitch([first, second])

        // Header, then the page from row 0 for `window + scroll` rows, then the
        // footer.
        XCTAssertEqual(stitched.height, header + window + scroll + footer)

        let topPixel = try pixel(of: stitched, x: pageWidth / 2, y: header / 2)
        assertPixel(topPixel, isAbout: (255, 0, 0), "header at the top")
        let bottomPixel = try pixel(
            of: stitched, x: pageWidth / 2, y: stitched.height - footer / 2)
        assertPixel(bottomPixel, isAbout: (0, 0, 255), "footer at the bottom")

        // Nothing in the middle may be header or footer, and every band has to
        // be the band the page carries there.
        for row in stride(from: header + bandHeight / 2,
                          to: header + window + scroll, by: bandHeight) {
            try assertGrey(stitched, row: row,
                           isAbout: expectedGrey(atPageRow: row - header),
                           "page row \(row - header)")
        }
    }

    func testStitchOfOneFrameReturnsItUnchanged() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let only = try makeFrame(of: page, scrolledBy: 0)

        let stitched = try capturer.stitch([only])
        XCTAssertEqual(stitched.height, frameHeight)
        try assertGrey(stitched, row: bandHeight / 2, isAbout: 0, "top band")
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

    func testStitchRejectsTheWrongNumberOfAlignments() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let first = try makeFrame(of: page, scrolledBy: 0)
        let second = try makeFrame(of: page, scrolledBy: 32)

        XCTAssertThrowsError(try capturer.stitch([first, second], alignments: [])) { error in
            guard let scrollError = error as? ScrollCaptureError,
                  case .alignmentMismatch = scrollError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testStitchThrowsWhenTheFirstPairSharesNothing() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let frame = try makeFrame(of: page, scrolledBy: 0)
        let unrelated = try makeSolid(red: 1, green: 0, blue: 0)

        XCTAssertThrowsError(try capturer.stitch([frame, unrelated])) { error in
            guard let scrollError = error as? ScrollCaptureError,
                  case .noOverlap = scrollError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    /// A frame that matches nothing, after one that did, reuses the last known
    /// distance rather than ending the capture: pages scroll by a fixed amount,
    /// so one bad frame mid animation is not a reason to throw away the rest.
    func testStitchFallsBackToTheLastKnownDistance() throws {
        let page = try makePage()
        let capturer = ScrollCapturer()
        let scroll = 32

        let first = try makeFrame(of: page, scrolledBy: 0)
        let second = try makeFrame(of: page, scrolledBy: scroll)
        let unrelated = try makeSolid(red: 1, green: 0, blue: 0)

        let stitched = try capturer.stitch([first, second, unrelated])
        // Two real strips plus one assumed to be the same size as the last.
        XCTAssertEqual(stitched.height, frameHeight + scroll * 2)
    }
}
