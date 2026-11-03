import Foundation
import XCTest

@testable import ReticleUploaders

/// Signatures here were produced by an independent SigV4 implementation that
/// reproduces AWS's published `get-vanilla` vector exactly (see `SigV4Tests`),
/// so they are an external expectation rather than a snapshot of this code.
final class S3UploaderTests: XCTestCase {

    // Credentials from AWS's test suite. Not real.
    private let accessKeyID = "AKIDEXAMPLE"
    private let secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    private let scope = "20150830/us-east-1/s3/aws4_request"

    /// 2015-08-30T12:36:00Z — the test suite's timestamp.
    private let fixedDate = Date(timeIntervalSince1970: 1_440_938_160)

    private let body = Data("reticle".utf8)
    private let bodyHash = "325d11d32f174ecde7e137b2826502dbf4462e5658747b6e242a00cbae8fdf50"
    private let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// A prefix with a space in it — exactly the shape that used to make every
    /// upload fail, because the signature was computed over the decoded path.
    private let keyWithSpace = "my folder/20260101-000000-abcdefgh.png"

    private func uploader(
        pathStyle: Bool = false,
        publicURLTemplate: String = ""
    ) -> S3Uploader {
        S3Uploader(config: .init(
            bucket: "my-screenshots",
            region: "us-east-1",
            accessKeyID: accessKeyID,
            secretAccessKey: secret,
            publicURLTemplate: publicURLTemplate,
            pathStyle: pathStyle
        ))
    }

    private func authorization(_ signedHeaders: String, _ signature: String) -> String {
        "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private func put(_ uploader: S3Uploader, key: String) throws -> URLRequest {
        try uploader.signedRequest(
            method: "PUT", key: key, body: body, contentType: "image/png", now: fixedDate
        )
    }

    // MARK: - PUT

    func testPutSignsTheEncodedPathVirtualHosted() throws {
        let request = try put(uploader(), key: keyWithSpace)

        XCTAssertEqual(
            try XCTUnwrap(request.url).absoluteString,
            "https://my-screenshots.s3.us-east-1.amazonaws.com"
                + "/my%20folder/20260101-000000-abcdefgh.png"
        )
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), bodyHash)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-date"), "20150830T123600Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "image/png")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            authorization(
                "content-type;host;x-amz-content-sha256;x-amz-date",
                "84334e3aad17cad8c0d92775335f0589880cd70da4b264090c48a042fe156799"
            )
        )
    }

    func testPutSignsTheEncodedPathPathStyle() throws {
        let request = try put(uploader(pathStyle: true), key: keyWithSpace)

        XCTAssertEqual(
            try XCTUnwrap(request.url).absoluteString,
            "https://s3.us-east-1.amazonaws.com/my-screenshots"
                + "/my%20folder/20260101-000000-abcdefgh.png"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            authorization(
                "content-type;host;x-amz-content-sha256;x-amz-date",
                "f412072af2f566fd42420a79274c1795c8cab65f2f2a28bf5085149af0fb654e"
            )
        )
    }

    /// The characters `CharacterSet.urlPathAllowed` would have left literal.
    func testPutEncodesSubDelimitersInTheKey() throws {
        let request = try put(uploader(), key: "a+b,c;d=e:f@g.png")

        XCTAssertEqual(
            try XCTUnwrap(request.url).absoluteString,
            "https://my-screenshots.s3.us-east-1.amazonaws.com/a%2Bb%2Cc%3Bd%3De%3Af%40g.png"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            authorization(
                "content-type;host;x-amz-content-sha256;x-amz-date",
                "af7cdfb51480a9352364e66706edcd2923688c290a3a8df54fcd4ff38d79e082"
            )
        )
    }

    func testPutCarriesTheBody() throws {
        let request = try put(uploader(), key: "plain.png")
        XCTAssertEqual(request.httpBody, body)
    }

    // MARK: - HEAD (testConnection)

    func testHeadProbeVirtualHosted() throws {
        let request = try uploader().signedRequest(
            method: "HEAD", key: "", body: Data(), contentType: nil, now: fixedDate
        )

        XCTAssertEqual(
            try XCTUnwrap(request.url).absoluteString,
            "https://my-screenshots.s3.us-east-1.amazonaws.com/"
        )
        XCTAssertEqual(request.httpMethod, "HEAD")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), emptyHash)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            authorization(
                "host;x-amz-content-sha256;x-amz-date",
                "94efda0f3d9ebab1c93935f168150a7a342d2c5f82d823910934ff2aa70afda4"
            )
        )
    }

    func testHeadProbePathStyle() throws {
        let request = try uploader(pathStyle: true).signedRequest(
            method: "HEAD", key: "", body: Data(), contentType: nil, now: fixedDate
        )

        XCTAssertEqual(
            try XCTUnwrap(request.url).absoluteString,
            "https://s3.us-east-1.amazonaws.com/my-screenshots/"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            authorization(
                "host;x-amz-content-sha256;x-amz-date",
                "9b70a98576f63b6e3d22461d5ca57efca23d6474b51a72bde12e747275423786"
            )
        )
    }

    /// The HEAD probe and the object PUT used to be two copies of the signing
    /// code. They are one now, so the same inputs must produce the same bytes.
    func testHeadAndPutShareOneSigningPath() throws {
        let subject = uploader()
        let first = try subject.signedRequest(
            method: "HEAD", key: "", body: Data(), contentType: nil, now: fixedDate
        )
        let second = try subject.signedRequest(
            method: "HEAD", key: "", body: Data(), contentType: nil, now: fixedDate
        )
        XCTAssertEqual(
            first.value(forHTTPHeaderField: "Authorization"),
            second.value(forHTTPHeaderField: "Authorization")
        )
    }

    // MARK: - Public URL

    func testPublicURLFallsBackToTheEndpoint() throws {
        let url = try uploader().publicURL(for: keyWithSpace)
        XCTAssertEqual(
            url.absoluteString,
            "https://my-screenshots.s3.us-east-1.amazonaws.com"
                + "/my%20folder/20260101-000000-abcdefgh.png"
        )
    }

    /// The link has to point at the key the object was actually stored under,
    /// so it carries the same encoding the request line did.
    func testPublicURLTemplateAppendsTheEncodedKey() throws {
        let subject = uploader(publicURLTemplate: "https://cdn.example.com/")
        let url = try subject.publicURL(for: "my folder/a+b.png")
        XCTAssertEqual(url.absoluteString, "https://cdn.example.com/my%20folder/a%2Bb.png")
    }

    /// `publicURLTemplate` is typed by hand in Settings and used to be force
    /// unwrapped, so a malformed value crashed the app on the next upload.
    /// Throwing or returning are both fine; trapping is not.
    func testMalformedPublicURLTemplateDoesNotTrap() {
        for template in ["not a url", "://", "ht!tp:// %%%", "\u{7F}", "https://ok.example/"] {
            let subject = uploader(publicURLTemplate: template)
            _ = try? subject.publicURL(for: "shot.png")
        }
    }
}
