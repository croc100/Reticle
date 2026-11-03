import Foundation
import XCTest

@testable import ReticleUploaders

/// Signing is checked against AWS's own published test vector first, so the
/// S3-specific expectations in `S3UploaderTests` rest on a construction that is
/// known to match what AWS computes, not on one this project agreed with itself.
final class SigV4Tests: XCTestCase {

    // Credentials from AWS's `aws-sig-v4-test-suite`. Not real.
    private let accessKeyID = "AKIDEXAMPLE"
    private let secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    private let datetime = "20150830T123600Z"
    private let date = "20150830"

    // MARK: - Published vector

    /// `get-vanilla` from AWS's SigV4 test suite.
    func testGetVanillaMatchesPublishedVector() {
        let payloadHash = SigV4.sha256Hex(Data())
        let (canonical, signedHeaders) = SigV4.canonicalRequest(
            method: "GET",
            uri: "/",
            query: "",
            headers: [
                (name: "host", value: "example.amazonaws.com"),
                (name: "x-amz-date", value: datetime),
            ],
            payloadHash: payloadHash
        )

        XCTAssertEqual(signedHeaders, "host;x-amz-date")
        XCTAssertEqual(canonical, """
            GET
            /

            host:example.amazonaws.com
            x-amz-date:20150830T123600Z

            host;x-amz-date
            e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
            """)

        let scope = SigV4.credentialScope(date: date, region: "us-east-1", service: "service")
        XCTAssertEqual(scope, "20150830/us-east-1/service/aws4_request")

        let key = SigV4.signingKey(
            secret: secret, date: date, region: "us-east-1", service: "service"
        )
        XCTAssertEqual(
            SigV4.hexString(key),
            "938127b5336810ddb6a5d6af445fcac9e371f9ed418ed386b022aed82901be75"
        )

        let signature = SigV4.signature(
            stringToSign: SigV4.stringToSign(
                datetime: datetime, scope: scope, canonicalRequest: canonical
            ),
            key: key
        )
        XCTAssertEqual(
            signature,
            "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"
        )
    }

    func testAuthorizationHeaderShape() {
        let header = SigV4.authorizationHeader(
            accessKeyID: accessKeyID,
            scope: "20150830/us-east-1/s3/aws4_request",
            signedHeaders: "host;x-amz-date",
            signature: "deadbeef"
        )
        XCTAssertEqual(header, "AWS4-HMAC-SHA256 "
            + "Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request, "
            + "SignedHeaders=host;x-amz-date, Signature=deadbeef")
    }

    // MARK: - Object key encoding

    func testUnreservedCharactersAndSlashSurviveUnencoded() {
        XCTAssertEqual(
            SigV4.encodeObjectKey("screenshots/2026-01-01_shot.png"),
            "screenshots/2026-01-01_shot.png"
        )
        XCTAssertEqual(SigV4.encodeObjectKey("already~safe-_.name"), "already~safe-_.name")
        XCTAssertEqual(SigV4.encodeObjectKey("a//b"), "a//b")
        XCTAssertEqual(SigV4.encodeObjectKey(""), "")
    }

    /// `CharacterSet.urlPathAllowed` leaves every one of these literal, and S3
    /// percent-encodes them before signing — which is how a prefix containing
    /// one used to make every upload fail with `SignatureDoesNotMatch`.
    func testSubDelimitersAreEncoded() {
        XCTAssertEqual(
            SigV4.encodeObjectKey("a+b,c;d=e:f@g!h$i&j'k(l)m*n"),
            "a%2Bb%2Cc%3Bd%3De%3Af%40g%21h%24i%26j%27k%28l%29m%2An"
        )
    }

    func testSpacesAndNonASCIIAreEncodedAsUTF8() {
        XCTAssertEqual(SigV4.encodeObjectKey("my folder/shot.png"), "my%20folder/shot.png")
        XCTAssertEqual(SigV4.encodeObjectKey("100%.png"), "100%25.png")
        XCTAssertEqual(
            SigV4.encodeObjectKey("스크린샷/화면.png"),
            "%EC%8A%A4%ED%81%AC%EB%A6%B0%EC%83%B7/%ED%99%94%EB%A9%B4.png"
        )
    }

    // MARK: - Canonical request assembly

    func testHeadersAreSortedRegardlessOfInputOrder() {
        let payloadHash = SigV4.sha256Hex(Data())
        let (canonical, signedHeaders) = SigV4.canonicalRequest(
            method: "PUT",
            uri: "/key.png",
            query: "",
            headers: [
                (name: "x-amz-date", value: datetime),
                (name: "content-type", value: "image/png"),
                (name: "host", value: "bucket.s3.us-east-1.amazonaws.com"),
            ],
            payloadHash: payloadHash
        )

        XCTAssertEqual(signedHeaders, "content-type;host;x-amz-date")
        XCTAssertTrue(canonical.hasPrefix("PUT\n/key.png\n\ncontent-type:image/png\n"))
    }

    func testAmzDateIsUTCBasicFormat() {
        // 2015-08-30T12:36:00Z
        let fixed = Date(timeIntervalSince1970: 1_440_938_160)
        XCTAssertEqual(SigV4.amzDate(fixed), datetime)
    }
}
