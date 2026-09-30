import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ReticlePipeline
import ReticleCore
import ReticleNaming

/// File-writing tests for `LocalFileOutput`.
///
/// These do real I/O into a temporary directory, so they check what actually landed on
/// disk rather than what the code intended to write — which matters most for the format
/// handling, where the file's name and its contents used to be decided separately.
final class LocalFileOutputTests: XCTestCase {

    private var tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalFileOutputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Basic writing

    func testWritesAFileAndRecordsItsURL() async throws {
        let output = makeOutput(pattern: "shot.png")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first, "the output URL should be recorded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(context.outputURLs.count, 1)
    }

    func testOrganisesFilesIntoADailyFolder() async throws {
        let output = makeOutput(pattern: "shot.png")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first)
        let folder = url.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().path,
                       tempDirectory.path,
                       "the daily folder should sit directly under the configured directory")
        assertMatchesDailyFolderFormat(folder)
    }

    func testResolvesFilenameTokens() async throws {
        let output = makeOutput(pattern: "%year%-%month%-%day%.png")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first)
        assertMatchesDailyFolderFormat(url.deletingPathExtension().lastPathComponent)
    }

    func testReplacesAnExtensionAlreadyInThePattern() async throws {
        // The pattern ends in .png but JPEG was requested; the real format wins.
        let output = makeOutput(pattern: "shot.png", format: "jpeg")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first)
        XCTAssertEqual(url.lastPathComponent, "shot.jpg")
    }

    // MARK: - Format and payload agreement

    /// The invariant that matters: whatever extension the file ends up with, its bytes are
    /// actually that format. Deriving the extension and the encoder separately let a WebP
    /// request on a system without a WebP encoder write PNG bytes into a `.webp` file.
    func testExtensionAlwaysMatchesTheEncodedPayload() async throws {
        for requested in ["png", "jpeg", "jpg", "tiff", "tif", "webp", "nonsense", ""] {
            let output = makeOutput(pattern: "shot-\(requested.isEmpty ? "empty" : requested).png",
                                    format: requested)
            var context = CaptureContext(workflowID: UUID())
            try await output.execute(screenshot: try makeScreenshot(), context: &context)

            let url = try XCTUnwrap(context.outputURLs.first)
            let actual = try encodedType(of: url)
            let fromExtension = try XCTUnwrap(
                UTType(filenameExtension: url.pathExtension),
                "no known type for extension .\(url.pathExtension)"
            )
            XCTAssertEqual(actual, fromExtension.identifier,
                           "format \"\(requested)\" wrote \(actual) into a .\(url.pathExtension) file")
        }
    }

    func testPNGIsTheDefaultAndTheFallback() async throws {
        for requested in ["png", "nonsense", ""] {
            let output = makeOutput(pattern: "shot-\(requested.isEmpty ? "empty" : requested).png",
                                    format: requested)
            var context = CaptureContext(workflowID: UUID())
            try await output.execute(screenshot: try makeScreenshot(), context: &context)

            let url = try XCTUnwrap(context.outputURLs.first)
            XCTAssertEqual(url.pathExtension, "png", "\"\(requested)\" should fall back to PNG")
            XCTAssertEqual(try encodedType(of: url), UTType.png.identifier)
        }
    }

    func testJPEGAndTIFFUseTheirOwnExtensions() async throws {
        let cases: [(format: String, ext: String, type: UTType)] = [
            ("jpeg", "jpg", .jpeg),
            ("jpg", "jpg", .jpeg),
            ("tiff", "tiff", .tiff),
            ("tif", "tiff", .tiff),
        ]
        for entry in cases {
            let output = makeOutput(pattern: "shot-\(entry.format).png", format: entry.format)
            var context = CaptureContext(workflowID: UUID())
            try await output.execute(screenshot: try makeScreenshot(), context: &context)

            let url = try XCTUnwrap(context.outputURLs.first)
            XCTAssertEqual(url.pathExtension, entry.ext)
            XCTAssertEqual(try encodedType(of: url), entry.type.identifier)
        }
    }

    func testResolvedFormatNeverNamesATypeItCannotEncode() {
        // Whatever the system supports, the pair is always self-consistent.
        for requested in ["png", "jpeg", "tiff", "webp", "nonsense"] {
            let output = makeOutput(pattern: "shot.png", format: requested)
            let resolved = output.resolvedFormat
            let fromExtension = UTType(filenameExtension: resolved.pathExtension)
            XCTAssertEqual(resolved.type, fromExtension,
                           "\"\(requested)\" resolved to \(resolved.type) with .\(resolved.pathExtension)")
        }
    }

    // MARK: - Name collisions

    func testASecondSaveDoesNotOverwriteTheFirst() async throws {
        // A fixed pattern with no counter and no time token resolves to the same name every
        // time, and CGImageDestination overwrites silently.
        let output = makeOutput(pattern: "shot.png")
        let screenshot = try makeScreenshot()

        var first = CaptureContext(workflowID: UUID())
        try await output.execute(screenshot: screenshot, context: &first)
        var second = CaptureContext(workflowID: UUID())
        try await output.execute(screenshot: screenshot, context: &second)

        let firstURL = try XCTUnwrap(first.outputURLs.first)
        let secondURL = try XCTUnwrap(second.outputURLs.first)

        XCTAssertNotEqual(firstURL, secondURL, "the second save reused the first path")
        XCTAssertEqual(secondURL.lastPathComponent, "shot (2).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path),
                      "the first screenshot was overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testCollisionSuffixesKeepCounting() async throws {
        let output = makeOutput(pattern: "shot.png")
        let screenshot = try makeScreenshot()
        var names: [String] = []

        for _ in 0..<3 {
            var context = CaptureContext(workflowID: UUID())
            try await output.execute(screenshot: screenshot, context: &context)
            names.append(try XCTUnwrap(context.outputURLs.first).lastPathComponent)
        }

        XCTAssertEqual(names, ["shot.png", "shot (2).png", "shot (3).png"])
    }

    func testSuffixIsInsertedBeforeTheExtension() throws {
        let url = tempDirectory.appendingPathComponent("photo.png")
        XCTAssertEqual(LocalFileOutput.byAddingSuffixIfTaken(url), url,
                       "an unused path should come back untouched")

        try Data("x".utf8).write(to: url)
        let next = LocalFileOutput.byAddingSuffixIfTaken(url)
        XCTAssertEqual(next.lastPathComponent, "photo (2).png")
        XCTAssertEqual(next.pathExtension, "png", "the extension must stay last")
    }

    // MARK: - Metadata

    func testWritesDPIDerivedFromTheScaleFactor() async throws {
        let output = makeOutput(pattern: "shot.png")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(scaleFactor: 2.0), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let dpi = try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double)
        XCTAssertEqual(dpi, 144, accuracy: 0.5, "2× should be written as 144 dpi")
    }

    func testPreservesImageDimensions() async throws {
        let output = makeOutput(pattern: "shot.png")
        var context = CaptureContext(workflowID: UUID())

        try await output.execute(screenshot: try makeScreenshot(width: 64, height: 32), context: &context)

        let url = try XCTUnwrap(context.outputURLs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 32)
    }

    // MARK: - Helpers

    private func makeOutput(pattern: String, format: String = "png") -> LocalFileOutput {
        LocalFileOutput(directory: tempDirectory,
                        nameParser: NameParser(pattern: pattern, counter: { 1 }),
                        format: format)
    }

    private func makeScreenshot(width: Int = 8,
                                height: Int = 8,
                                scaleFactor: CGFloat = 2.0) throws -> Screenshot {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())

        return Screenshot(image: image,
                          capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                          sourceRect: CGRect(x: 0, y: 0, width: width, height: height),
                          scaleFactor: scaleFactor)
    }

    /// The type ImageIO reports for the bytes actually on disk.
    private func encodedType(of url: URL) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil),
                                   "could not read back \(url.lastPathComponent)")
        let type = try XCTUnwrap(CGImageSourceGetType(source),
                                 "no type for \(url.lastPathComponent)")
        return type as String
    }

    private func assertMatchesDailyFolderFormat(_ name: String,
                                                file: StaticString = #filePath,
                                                line: UInt = #line) {
        let matched = name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        XCTAssertTrue(matched, "expected a YYYY-MM-DD name, got \"\(name)\"", file: file, line: line)
    }
}
