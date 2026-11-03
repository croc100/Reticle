import CoreGraphics
import Foundation
import XCTest
@testable import ReticleCore

/// The clipboard history deduplicates by `id`, so `id` is the part that has to
/// be right: the old one collided for text and never matched for images.
final class ClipboardEntryTests: XCTestCase {

    // MARK: - Fixtures

    private func makeThumbnail(width: Int = 8, height: Int = 8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeImageEntry(data: Data) throws -> ClipboardEntry {
        let thumbnail = try makeThumbnail()
        return .image(ClipboardImage(
            data: data,
            type: "public.png",
            pixelWidth: 1920,
            pixelHeight: 1080,
            thumbnail: thumbnail))
    }

    // MARK: - Text identity

    func testSameTextHasSameID() {
        XCTAssertEqual(ClipboardEntry.text("hello").id, ClipboardEntry.text("hello").id)
    }

    /// The regression.  Identity used to be the first 40 characters, so two
    /// different notes that opened with the same line counted as one entry and
    /// pushing the second silently removed the first.
    func testTextsSharingALongPrefixHaveDifferentIDs() {
        let prefix = String(repeating: "a", count: 64)
        let first = ClipboardEntry.text(prefix + "-one")
        let second = ClipboardEntry.text(prefix + "-two")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testTextAndImageIDsCannotCollide() throws {
        let text = ClipboardEntry.text("x")
        let image = try makeImageEntry(data: Data("x".utf8))
        XCTAssertNotEqual(text.id, image.id)
    }

    // MARK: - Image identity

    /// The other half of the regression: identity used to be the
    /// `ObjectIdentifier` of a freshly decoded `NSImage`, which differs on
    /// every poll, so copying the same picture twice always added a new row.
    func testSameImageBytesHaveSameID() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        let first = try makeImageEntry(data: bytes)
        let second = try makeImageEntry(data: bytes)
        XCTAssertEqual(first.id, second.id)
    }

    func testDifferentImageBytesHaveDifferentIDs() throws {
        let first = try makeImageEntry(data: Data([1, 2, 3]))
        let second = try makeImageEntry(data: Data([1, 2, 4]))
        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - Row text

    func testDisplayTextIsOneBoundedLine() {
        // CRLF included on purpose: it is one `Character` in Swift, so a
        // flattener written with `replacingOccurrences(of: "\n")` leaves it in.
        let entry = ClipboardEntry.text("first\nsecond\tthird\r\nfourth")
        XCTAssertEqual(entry.displayText, "first second third fourth")

        let long = ClipboardEntry.text(String(repeating: "x", count: 500))
        XCTAssertEqual(long.displayText.count, 120)
    }

    func testImageDisplayTextReportsPixelDimensions() throws {
        let entry = try makeImageEntry(data: Data([1]))
        XCTAssertEqual(entry.displayText, "Image 1920×1080")
    }

    // MARK: - Type label

    func testTextTypeLabelCountsCharacters() {
        XCTAssertEqual(ClipboardEntry.text("abc").typeLabel, "3 characters")
        XCTAssertEqual(ClipboardEntry.text("a").typeLabel, "1 character")
    }

    /// The label reports what the entry actually retains, which is the point of
    /// keeping the encoded bytes rather than a decoded bitmap.
    func testImageTypeLabelReportsRetainedBytes() throws {
        let small = try makeImageEntry(data: Data(repeating: 0, count: 2048))
        XCTAssertEqual(small.typeLabel, "2 KB")

        let large = try makeImageEntry(data: Data(repeating: 0, count: 3 * 1024 * 1024))
        XCTAssertEqual(large.typeLabel, "3.0 MB")
    }
}
