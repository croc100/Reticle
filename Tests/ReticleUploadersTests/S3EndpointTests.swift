import Foundation
import XCTest

@testable import ReticleUploaders

/// One signed-PUT implementation serves every S3-compatible service, so what
/// changes per service is the host the request goes to and the host that gets
/// signed. These are the same string by construction in `makeEndpoint`, which
/// is the point: a signature computed over one authority and sent to another is
/// a 403 with nothing in it to explain why.
final class S3EndpointTests: XCTestCase {

    // Credentials from AWS's test suite. Not real.
    private let accessKeyID = "AKIDEXAMPLE"
    private let secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    /// 2015-08-30T12:36:00Z — the test suite's timestamp.
    private let fixedDate = Date(timeIntervalSince1970: 1_440_938_160)
    private let key = "shots/a.png"

    private func uploader(
        bucket: String = "my-screenshots",
        region: String = "us-east-1",
        endpoint: String = "",
        pathStyle: Bool = false,
        publicURLTemplate: String = ""
    ) -> S3Uploader {
        S3Uploader(config: S3Uploader.Config(
            bucket: bucket,
            region: region,
            accessKeyID: accessKeyID,
            secretAccessKey: secret,
            endpoint: endpoint,
            publicURLTemplate: publicURLTemplate,
            pathStyle: pathStyle))
    }

    private func put(_ uploader: S3Uploader) throws -> URLRequest {
        try uploader.signedRequest(
            method: "PUT", key: key, body: Data("x".utf8),
            contentType: "image/png", now: fixedDate)
    }

    private func url(_ request: URLRequest) throws -> String {
        try XCTUnwrap(request.url).absoluteString
    }

    // MARK: - Parsing what people paste

    func testEmptyEndpointMeansAmazon() throws {
        XCTAssertNil(try S3Uploader.parseEndpoint(""))
        XCTAssertNil(try S3Uploader.parseEndpoint("   \n "))
    }

    func testBareHostDefaultsToHTTPS() throws {
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("s3.example.com"),
            S3Uploader.ParsedEndpoint(scheme: "https", host: "s3.example.com"))
    }

    func testSchemeIsHonoured() throws {
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("https://s3.example.com"),
            S3Uploader.ParsedEndpoint(scheme: "https", host: "s3.example.com"))
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("http://localhost:9000"),
            S3Uploader.ParsedEndpoint(scheme: "http", host: "localhost:9000"))
    }

    /// Host names are case-insensitive and SigV4 signs them lower-cased, so the
    /// stored value is normalised rather than left to differ from the signature.
    func testHostIsLowerCased() throws {
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("HTTPS://S3.Example.COM")?.host,
            "s3.example.com")
    }

    func testTrailingSlashesAreDropped() throws {
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("s3.example.com///")?.host, "s3.example.com")
    }

    func testPortSurvives() throws {
        XCTAssertEqual(
            try S3Uploader.parseEndpoint("minio.internal:9000")?.host,
            "minio.internal:9000")
    }

    // MARK: - Parsing what should be refused

    private func assertRefused(
        _ raw: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let parsed = try S3Uploader.parseEndpoint(raw)
            XCTFail("expected \(raw) to be refused, got \(String(describing: parsed))",
                    file: file, line: line)
        } catch let error as UploadError {
            guard case .invalidConfiguration = error else {
                return XCTFail("unexpected \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    /// A path prefix would have to be folded into the canonical URI to be
    /// signed correctly. Dropping it silently signs one path and sends another.
    func testEndpointWithAPathIsRefused() {
        assertRefused("s3.example.com/bucket")
        assertRefused("https://s3.example.com/some/prefix")
    }

    func testUnknownSchemeIsRefused() {
        assertRefused("ftp://s3.example.com")
        assertRefused("s3://my-bucket")
    }

    func testEndpointWithNoHostIsRefused() {
        assertRefused("https://")
        assertRefused("https:///")
    }

    func testEndpointWithCredentialsOrSpacesIsRefused() {
        assertRefused("user@s3.example.com")
        assertRefused("s3 example.com")
        assertRefused("s3.example.com?x=1")
    }

    // MARK: - Where the request actually goes

    /// Amazon still derives its host from the region, with no endpoint set.
    /// Here as a regression guard: the endpoint field must not change the
    /// existing path for anyone who never touches it.
    func testAmazonIsUnchangedWhenNoEndpointIsSet() throws {
        XCTAssertEqual(
            try url(put(uploader())),
            "https://my-screenshots.s3.us-east-1.amazonaws.com/shots/a.png")
        XCTAssertEqual(
            try url(put(uploader(pathStyle: true))),
            "https://s3.us-east-1.amazonaws.com/my-screenshots/shots/a.png")
    }

    func testCloudflareR2VirtualHosted() throws {
        let request = try put(uploader(
            region: "auto",
            endpoint: "abc123.r2.cloudflarestorage.com"))
        XCTAssertEqual(
            try url(request),
            "https://my-screenshots.abc123.r2.cloudflarestorage.com/shots/a.png")
    }

    func testCloudflareR2PathStyle() throws {
        let request = try put(uploader(
            region: "auto",
            endpoint: "https://abc123.r2.cloudflarestorage.com",
            pathStyle: true))
        XCTAssertEqual(
            try url(request),
            "https://abc123.r2.cloudflarestorage.com/my-screenshots/shots/a.png")
    }

    /// A self-hosted MinIO over plain HTTP on a non-default port — the case
    /// that exercises scheme and port together.
    func testMinioKeepsSchemeAndPort() throws {
        let request = try put(uploader(
            endpoint: "http://localhost:9000", pathStyle: true))
        XCTAssertEqual(
            try url(request),
            "http://localhost:9000/my-screenshots/shots/a.png")
    }

    /// Virtual-hosted addressing puts the bucket in front of the authority,
    /// and a port stays at the end of it.
    func testVirtualHostedWithAPortKeepsThePortLast() throws {
        let request = try put(uploader(endpoint: "localhost:9000"))
        XCTAssertEqual(
            try url(request),
            "https://my-screenshots.localhost:9000/shots/a.png")
    }

    /// The host is signed, so a request whose authority changed without the
    /// signature changing would be rejected. One variable feeds both in
    /// `makeEndpoint`; this pins that `host` is in the signed set at all.
    func testTheHostIsPartOfTheSignature() throws {
        let request = try put(uploader(endpoint: "abc123.r2.cloudflarestorage.com"))
        let authorization = try XCTUnwrap(
            request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.contains("SignedHeaders=content-type;host;"),
                      "host missing from the signed headers: \(authorization)")
    }

    // MARK: - Public URL

    func testPublicURLUsesTheCustomEndpoint() throws {
        let uploaded = try uploader(
            region: "auto",
            endpoint: "abc123.r2.cloudflarestorage.com",
            pathStyle: true
        ).publicURL(for: "shots/a.png")
        XCTAssertEqual(
            uploaded.absoluteString,
            "https://abc123.r2.cloudflarestorage.com/my-screenshots/shots/a.png")
    }

    // MARK: - Bucket names

    /// The bucket goes straight into a host name or a path, so a name carrying
    /// a separator would corrupt the canonical URI.
    func testBucketNamesThatWouldCorruptThePathAreRefused() throws {
        for bucket in ["", "a/b", "a b", "a?b", "a#b", "a@b", "a:b", "a\\b", "a\tb"] {
            do {
                _ = try put(uploader(bucket: bucket))
                XCTFail("expected bucket \(bucket.debugDescription) to be refused")
            } catch let error as UploadError {
                guard case .invalidConfiguration = error else {
                    return XCTFail("unexpected \(error) for \(bucket.debugDescription)")
                }
            }
        }
    }

    func testOrdinaryBucketNamesPass() throws {
        for bucket in ["a", "my-screenshots", "my.bucket.name", "bucket123"] {
            XCTAssertNoThrow(try put(uploader(bucket: bucket)), bucket)
        }
    }

    // MARK: - Provider presets

    /// R2 rejects a signature scoped to anything but "auto", which is the one
    /// preset value that is a hard requirement rather than a convenience.
    func testCloudflareR2PinsItsRegionAndStyle() {
        XCTAssertEqual(S3Provider.cloudflareR2.defaultRegion, "auto")
        XCTAssertTrue(S3Provider.cloudflareR2.prefersPathStyle)
        XCTAssertTrue(S3Provider.cloudflareR2.usesEndpoint)
    }

    func testOnlyAmazonDerivesItsOwnEndpoint() {
        for provider in S3Provider.allCases {
            XCTAssertEqual(provider.usesEndpoint, provider != .aws, provider.rawValue)
        }
    }

    /// Where the region depends on the account rather than the service, the
    /// preset leaves it blank so the user has to supply it instead of
    /// inheriting a wrong guess.
    func testAccountDependentRegionsAreNotGuessed() {
        for provider in [S3Provider.backblazeB2, .wasabi, .digitalOceanSpaces, .custom] {
            XCTAssertTrue(provider.defaultRegion.isEmpty, provider.rawValue)
        }
    }

    func testEveryProviderIsPresentable() {
        for provider in S3Provider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, provider.rawValue)
            XCTAssertFalse(provider.note.isEmpty, provider.rawValue)
            XCTAssertEqual(
                provider.endpointPlaceholder.isEmpty, !provider.usesEndpoint,
                "a provider that takes an endpoint needs a placeholder: \(provider.rawValue)")
        }
    }

    func testProviderRawValuesRoundTrip() {
        for provider in S3Provider.allCases {
            XCTAssertEqual(S3Provider(rawValue: provider.rawValue), provider)
        }
        XCTAssertNil(S3Provider(rawValue: "something-from-a-newer-build"))
    }
}
