import CoreGraphics
import XCTest
@testable import ReticleEffects
import ReticleCore

/// Coordinate-space tests for `MaskRenderer`.
///
/// Three origin conventions meet inside the renderer: mask rects are screen points with
/// origin top-left, `CGImage.cropping(to:)` reads top-left pixel rects, and `CGContext`
/// draws in bottom-left user space. Confusing any two of them either puts a mask in the
/// wrong place or fills it with pixels copied from the wrong place.
///
/// The second failure mode is the reason these tests read individual pixels rather than
/// just checking that *something* changed: a redacted region ends up covered either way,
/// so a mask that pastes the mirrored half of the screen over its target still looks
/// plausible in a thumbnail. Only the pixel values give it away.
final class MaskRendererCoordinateTests: XCTestCase {

    // MARK: - Where the mask lands

    func testSolidFillCoversTheNamedRegionAndNothingElse() throws {
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        let inside = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(inside.g, 200, "the named region should be filled")

        // Same column, mirrored across the horizontal centre line. A stray flip puts the
        // fill down here instead.
        let mirrored = try pixel(out, x: 20, y: 80)
        XCTAssertLessThan(mirrored.g, 60, "fill landed at the vertically mirrored position")
        XCTAssertGreaterThan(mirrored.b, 200, "the bottom half should be untouched")
    }

    func testMaskStraddlingAnEdgeIsClippedRatherThanDropped() throws {
        let image = try makeSplitImage()
        // Half of this rect hangs off the right edge.
        let mask = MaskRegion(rule: .rect(CGRect(x: 80, y: 0, width: 40, height: 40)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        let inBounds = try pixel(out, x: 90, y: 20)
        XCTAssertGreaterThan(inBounds.g, 200, "the in-bounds part should still be filled")
    }

    func testMaskEntirelyOutsideTheImageIsDropped() throws {
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 500, y: 300, width: 40, height: 40)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        XCTAssertEqual(out.width, image.width)
        XCTAssertEqual(out.height, image.height)
        let untouched = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(untouched.r, 200, "nothing should have been drawn")
    }

    func testDisabledMasksAreIgnored() throws {
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                              style: .solidFill(red: 0, green: 1, blue: 0),
                              enabled: false)

        let out = try MaskRenderer().render(image: image, masks: [mask])

        let untouched = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(untouched.r, 200)
        XCTAssertLessThan(untouched.g, 60, "a disabled mask should not render")
    }

    // MARK: - Which pixels the mask is built from

    func testPixelateSamplesThePixelsItCovers() throws {
        let image = try makeSplitImage()
        // Well inside the red half; the colour boundary sits 10px below this rect.
        let mask = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                              style: .pixelate(blockSize: 8))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        // Pixelating a solid red block yields red. Cropping the source from the mirrored
        // position instead pastes the blue half over this corner.
        let inside = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(inside.r, 200, "pixelate should keep the red it covers")
        XCTAssertLessThan(inside.b, 60, "pixelate sampled the vertically mirrored region")
    }

    func testBlurSamplesThePixelsItCovers() throws {
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                              style: .blur(radius: 6))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        let inside = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(inside.r, 180, "blur should keep the red it covers")
        XCTAssertLessThan(inside.b, 80, "blur sampled the vertically mirrored region")
    }

    func testBlurDoesNotDarkenTheRegionItCovers() throws {
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 20, y: 10, width: 30, height: 30)),
                              style: .blur(radius: 10))

        let out = try MaskRenderer().render(image: image, masks: [mask])

        // Blurring an exact crop samples transparent black past its edges, which bleeds a
        // dark halo inward. The renderer widens the crop by the radius to avoid that, so a
        // pixel near the mask's edge should still read as red rather than muddied.
        let nearEdge = try pixel(out, x: 22, y: 12)
        XCTAssertGreaterThan(nearEdge.r, 150, "blur crop was not expanded; edges darkened")
    }

    // MARK: - Screen space → image space

    func testSourceOriginTranslatesScreenRectsIntoACrop() throws {
        // A 100×100 region capture whose top-left pixel is screen point (500, 300) —
        // a region grab, a window grab, or anything off a secondary display.
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 500, y: 300, width: 40, height: 40)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image,
                                            masks: [mask],
                                            scaleFactor: 1,
                                            sourceOrigin: CGPoint(x: 500, y: 300))

        let inside = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(inside.g, 200,
                             "a screen rect should map onto the crop's own origin")
    }

    func testSourceOriginShiftsTheMaskByTheCaptureOffset() throws {
        // The mask sits 30pt right and 20pt down from the capture origin, so it should
        // land at image pixel (30, 20) — not at (80, 70), and not off-image.
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 80, y: 70, width: 20, height: 20)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image,
                                            masks: [mask],
                                            scaleFactor: 1,
                                            sourceOrigin: CGPoint(x: 50, y: 50))

        let shifted = try pixel(out, x: 35, y: 25)
        XCTAssertGreaterThan(shifted.g, 200, "mask should be offset by the capture origin")

        let unshifted = try pixel(out, x: 85, y: 75)
        XCTAssertLessThan(unshifted.g, 60, "mask was placed at raw screen coordinates")
    }

    func testScaleFactorConvertsPointsToPixels() throws {
        let image = try makeSplitImage()
        // 20×20 points at 2× covers the top-left 40×40 pixels.
        let mask = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 20, height: 20)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image, masks: [mask], scaleFactor: 2)

        let inside = try pixel(out, x: 30, y: 30)
        XCTAssertGreaterThan(inside.g, 200, "20pt at 2× should reach 40px")

        let beyond = try pixel(out, x: 45, y: 45)
        XCTAssertLessThan(beyond.g, 60, "the fill should stop at 40px")
    }

    func testScaleFactorAndSourceOriginCompose() throws {
        // Origin is in points and is subtracted before scaling, so a 10pt offset at 2×
        // moves the mask 20px.
        let image = try makeSplitImage()
        let mask = MaskRegion(rule: .rect(CGRect(x: 20, y: 10, width: 20, height: 20)),
                              style: .solidFill(red: 0, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image,
                                            masks: [mask],
                                            scaleFactor: 2,
                                            sourceOrigin: CGPoint(x: 10, y: 5))

        // (20-10)*2 = 20, (10-5)*2 = 10 → a 40×40px block at pixel (20, 10).
        let inside = try pixel(out, x: 30, y: 20)
        XCTAssertGreaterThan(inside.g, 200, "origin should be subtracted before scaling")

        let beforeOrigin = try pixel(out, x: 10, y: 5)
        XCTAssertLessThan(beforeOrigin.g, 60, "mask should not start at the raw rect origin")
    }

    // MARK: - Multiple masks

    func testMasksApplyInOrder() throws {
        let image = try makeSplitImage()
        let first = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                               style: .solidFill(red: 0, green: 1, blue: 0))
        let second = MaskRegion(rule: .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                                style: .solidFill(red: 1, green: 1, blue: 0))

        let out = try MaskRenderer().render(image: image, masks: [first, second])

        // The later mask wins where they overlap.
        let inside = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(inside.r, 200, "the last mask should be on top")
        XCTAssertGreaterThan(inside.g, 200)
    }

    func testEmptyMaskListReturnsTheOriginalImage() throws {
        let image = try makeSplitImage()

        let out = try MaskRenderer().render(image: image, masks: [])

        XCTAssertEqual(out.width, image.width)
        XCTAssertEqual(out.height, image.height)
        let untouched = try pixel(out, x: 20, y: 20)
        XCTAssertGreaterThan(untouched.r, 200)
    }

    // MARK: - Helpers

    /// 100×100 with a solid red top half and a solid blue bottom half, so that a vertical
    /// flip anywhere in the pipeline is unmistakable in a single pixel read.
    private func makeSplitImage(width: Int = 100, height: Int = 100) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // The context draws bottom-up, so the image's top half is the upper half here.
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// Reads one pixel, with `y` measured from the **top** of the image.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        data.initialize(repeating: 0, count: bytesPerRow * height)
        defer { data.deallocate() }

        let ctx = try XCTUnwrap(CGContext(
            data: data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Row 0 of the bitmap holds the image's top row, which is why `y` reads downward.
        let offset = y * bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }
}
