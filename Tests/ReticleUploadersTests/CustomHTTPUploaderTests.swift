import Foundation
import XCTest

@testable import ReticleUploaders

/// The dot-path response parser handles array indices and missing keys and had
/// never been exercised — one of those paths took the app down with it.
final class CustomHTTPUploaderTests: XCTestCase {

    private func extract(_ json: String, _ path: String) throws -> URL {
        try CustomHTTPUploader.extractURL(from: Data(json.utf8), path: path)
    }

    private func assertRejects(
        _ json: String,
        _ path: String,
        _ message: String,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CustomHTTPUploader.extractURL(from: Data(json.utf8), path: path),
            message,
            line: line
        )
    }

    // MARK: - Dot paths that resolve

    func testNestedObjectPath() throws {
        let url = try extract(#"{"data":{"url":"https://img.example/a.png"}}"#, "data.url")
        XCTAssertEqual(url.absoluteString, "https://img.example/a.png")
    }

    func testTopLevelKey() throws {
        let url = try extract(#"{"link":"https://img.example/b.png"}"#, "link")
        XCTAssertEqual(url.absoluteString, "https://img.example/b.png")
    }

    /// The Discord webhook shape the documentation comment advertises.
    func testArrayIndexInThePath() throws {
        let json = #"{"attachments":[{"proxy_url":"https://cdn.example/c.png"}]}"#
        let url = try extract(json, "attachments.0.proxy_url")
        XCTAssertEqual(url.absoluteString, "https://cdn.example/c.png")
    }

    func testSecondArrayElement() throws {
        let json = #"{"files":["https://x.example/0.png","https://x.example/1.png"]}"#
        let url = try extract(json, "files.1")
        XCTAssertEqual(url.absoluteString, "https://x.example/1.png")
    }

    // MARK: - Dot paths that do not resolve

    func testMissingKeyIsReported() {
        assertRejects(#"{"data":{"url":"https://img.example/a.png"}}"#, "data.link",
                      "a key that is not there should throw")
    }

    func testIndexPastTheEndIsReported() {
        assertRejects(#"{"files":["https://x.example/0.png"]}"#, "files.5",
                      "an index past the end should throw")
    }

    /// `Int("-1")` is -1, which passed the old `idx < array.count` check and
    /// then trapped on the subscript. `responseURLPath` comes from Settings,
    /// so this was a crash reachable by typing.
    func testNegativeIndexIsReportedRatherThanTrapping() {
        assertRejects(#"{"files":["https://x.example/0.png"]}"#, "files.-1",
                      "a negative index should throw, not trap")
    }

    func testIndexIntoAnObjectIsReported() {
        assertRejects(#"{"data":{"url":"https://img.example/a.png"}}"#, "data.0",
                      "an index into an object should throw")
    }

    func testNonStringValueIsReported() {
        assertRejects(#"{"url":42}"#, "url", "a number is not a URL string")
    }

    func testStringWithoutASchemeIsReported() {
        assertRejects(#"{"url":"upload failed"}"#, "url", "a bare string is not a URL")
    }

    func testNonJSONBodyWithAPathIsReported() {
        assertRejects("<html>502 Bad Gateway</html>", "data.url",
                      "an HTML error page should throw, not parse")
    }

    // MARK: - Empty path: the body is the URL

    func testEmptyPathUsesTheWholeBody() throws {
        let url = try extract("  https://img.example/d.png\n", "")
        XCTAssertEqual(url.absoluteString, "https://img.example/d.png")
    }

    func testEmptyPathRejectsABodyThatIsNotAURL() {
        assertRejects("something went wrong", "", "a prose body should throw")
    }

    // MARK: - Multipart body

    func testMultipartBodyIsWellFormed() {
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let body = CustomHTTPUploader.multipartBody(
            data: payload, field: "file", filename: "shot.png", boundary: "B123"
        )

        let crlf = "\r\n"
        let header = "--B123\(crlf)"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"shot.png\"\(crlf)"
            + "Content-Type: image/png\(crlf)\(crlf)"
        let footer = "\(crlf)--B123--\(crlf)"

        XCTAssertEqual(body, Data(header.utf8) + payload + Data(footer.utf8))
    }

    func testMultipartBodyCarriesTheFieldAndFilenameItWasGiven() {
        let body = CustomHTTPUploader.multipartBody(
            data: Data(), field: "upload", filename: "a b.png", boundary: "XYZ"
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"upload\""))
        XCTAssertTrue(text.contains("filename=\"a b.png\""))
        XCTAssertTrue(text.hasSuffix("--XYZ--\r\n"))
    }
}
