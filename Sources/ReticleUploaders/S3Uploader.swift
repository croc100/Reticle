import CoreGraphics
import Foundation
import ImageIO

/// Uploads an encoded screenshot directly to an AWS S3 bucket using a PUT request
/// signed with AWS Signature Version 4.  No third-party SDK required.
///
/// Required IAM permissions: `s3:PutObject` on the target bucket/prefix.
/// For public links the bucket (or the prefix) must allow public reads, or
/// use a CloudFront distribution and set `publicURLTemplate`.
public struct S3Uploader: Uploader, Sendable {

    // MARK: - Configuration

    public struct Config: Sendable {
        /// Target bucket name, e.g. "my-screenshots"
        public var bucket: String
        /// AWS region identifier, e.g. "us-east-1"
        public var region: String
        /// IAM access key ID
        public var accessKeyID: String
        /// IAM secret access key
        public var secretAccessKey: String
        /// Optional key prefix (folder), e.g. "screenshots/".  No leading slash.
        public var keyPrefix: String
        /// If non-empty, the public link is the template with the key appended.
        /// Useful for CloudFront.  Leave empty to use the standard S3 HTTPS URL.
        public var publicURLTemplate: String
        /// Use path-style endpoint ("s3.amazonaws.com/bucket/key") instead of
        /// virtual-hosted ("bucket.s3.amazonaws.com/key").  Some S3-compatible
        /// services require this.
        public var pathStyle: Bool

        public init(
            bucket: String,
            region: String,
            accessKeyID: String,
            secretAccessKey: String,
            keyPrefix: String = "",
            publicURLTemplate: String = "",
            pathStyle: Bool = false
        ) {
            self.bucket = bucket
            self.region = region
            self.accessKeyID = accessKeyID
            self.secretAccessKey = secretAccessKey
            self.keyPrefix = keyPrefix
            self.publicURLTemplate = publicURLTemplate
            self.pathStyle = pathStyle
        }
    }

    public let config: Config

    public init(config: Config) {
        self.config = config
    }

    // MARK: - Uploader

    public func upload(_ image: EncodedImage) async throws -> URL {
        let key = config.keyPrefix + objectFilename(extension: image.fileExtension)
        let request = try signedRequest(
            method: "PUT", key: key, body: image.data,
            contentType: image.contentType, now: Date()
        )

        let http = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.serverError(statusCode: http.statusCode, body: "S3 PUT failed")
        }

        return try publicURL(for: key)
    }

    /// Sends a signed HEAD request to the bucket to verify credentials and connectivity.
    /// Succeeds on HTTP 200 (OK) or 403 (reachable but access denied — misconfigured permissions).
    public func testConnection() async throws {
        let request = try signedRequest(
            method: "HEAD", key: "", body: Data(), contentType: nil, now: Date()
        )

        let http = try await send(request)
        guard http.statusCode == 200 || http.statusCode == 403 else {
            throw UploadError.serverError(statusCode: http.statusCode, body: "")
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.networkError(underlying: URLError(.badServerResponse))
        }
        return http
    }

    // MARK: - AWS Signature V4

    /// Builds the signed request for both the object PUT and the HEAD probe, so
    /// there is one copy of the signing rules rather than one per request shape.
    ///
    /// `now` is a parameter rather than `Date()` inside, so the signature is
    /// reproducible in tests.
    func signedRequest(
        method: String,
        key: String,
        body: Data,
        contentType: String?,
        now: Date
    ) throws -> URLRequest {
        let endpoint = try makeEndpoint(encodedKey: SigV4.encodeObjectKey(key))

        let datetime = SigV4.amzDate(now)
        let date = String(datetime.prefix(8))
        let payloadHash = SigV4.sha256Hex(body)

        var headers: [(name: String, value: String)] = [
            (name: "host", value: endpoint.host),
            (name: "x-amz-content-sha256", value: payloadHash),
            (name: "x-amz-date", value: datetime),
        ]
        if let contentType {
            headers.append((name: "content-type", value: contentType))
        }

        let (canonical, signedHeaders) = SigV4.canonicalRequest(
            method: method,
            uri: endpoint.canonicalURI,
            query: "",
            headers: headers,
            payloadHash: payloadHash
        )
        let scope = SigV4.credentialScope(date: date, region: config.region, service: "s3")
        let signature = SigV4.signature(
            stringToSign: SigV4.stringToSign(
                datetime: datetime, scope: scope, canonicalRequest: canonical
            ),
            key: SigV4.signingKey(
                secret: config.secretAccessKey, date: date, region: config.region, service: "s3"
            )
        )

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method
        if !body.isEmpty { request.httpBody = body }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(
            SigV4.authorizationHeader(
                accessKeyID: config.accessKeyID,
                scope: scope,
                signedHeaders: signedHeaders,
                signature: signature
            ),
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    // MARK: - URL helpers

    /// The request URL and the canonical URI are built from one already-encoded
    /// key, so the path that gets signed is byte-for-byte the path that is sent.
    /// Reading the path back off a `URL` does not work: `URL.path` percent-decodes.
    private struct Endpoint {
        let url: URL
        let canonicalURI: String
        let host: String
    }

    private func makeEndpoint(encodedKey: String) throws -> Endpoint {
        let host: String
        let canonicalURI: String
        if config.pathStyle {
            host = "s3.\(config.region).amazonaws.com"
            canonicalURI = "/\(config.bucket)/\(encodedKey)"
        } else {
            host = "\(config.bucket).s3.\(config.region).amazonaws.com"
            canonicalURI = "/\(encodedKey)"
        }
        guard let url = URL(string: "https://\(host)\(canonicalURI)") else {
            throw UploadError.invalidConfiguration(
                "Bucket and region do not form a valid S3 URL: \(config.bucket) / \(config.region)"
            )
        }
        return Endpoint(url: url, canonicalURI: canonicalURI, host: host)
    }

    func publicURL(for key: String) throws -> URL {
        let encodedKey = SigV4.encodeObjectKey(key)
        guard !config.publicURLTemplate.isEmpty else {
            return try makeEndpoint(encodedKey: encodedKey).url
        }
        guard let url = URL(string: config.publicURLTemplate + encodedKey) else {
            throw UploadError.invalidConfiguration(
                "Public URL template is not a valid URL: \(config.publicURLTemplate)"
            )
        }
        return url
    }

    /// A date-sortable object name.  Pinned to POSIX so a non-Gregorian system
    /// calendar cannot put a different year in the filename.
    private func objectFilename(extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        return "\(stamp)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
    }

    // MARK: - Image encoding

}
