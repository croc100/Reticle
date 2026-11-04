import CoreGraphics
import Foundation
import ImageIO

/// Uploads a CGImage directly to an AWS S3 bucket using a PUT request
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
        /// Region identifier used in the credential scope, e.g. "us-east-1".
        /// Cloudflare R2 requires "auto"; services that ignore regions still
        /// need the signature to agree with whatever they were started with.
        public var region: String
        /// Host of an S3-compatible service, with an optional scheme and port:
        /// `"<account>.r2.cloudflarestorage.com"`,
        /// `"https://s3.us-west-004.backblazeb2.com"`, `"http://localhost:9000"`.
        ///
        /// Empty means Amazon, whose endpoint follows from the region.
        public var endpoint: String
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
            endpoint: String = "",
            keyPrefix: String = "",
            publicURLTemplate: String = "",
            pathStyle: Bool = false
        ) {
            self.bucket = bucket
            self.region = region
            self.endpoint = endpoint
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

    public func upload(_ image: CGImage) async throws -> URL {
        guard let pngData = pngData(from: image) else {
            throw UploadError.encodingFailed
        }

        let key = config.keyPrefix + objectFilename()
        let request = try signedRequest(
            method: "PUT", key: key, body: pngData, contentType: "image/png", now: Date()
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
        try Self.validateBucket(config.bucket)

        let base = try Self.parseEndpoint(config.endpoint)
        // Amazon's host follows from the region; anything else supplies its own.
        let serviceHost = base?.host ?? "s3.\(config.region).amazonaws.com"
        let scheme = base?.scheme ?? "https"

        let host: String
        let canonicalURI: String
        if config.pathStyle {
            host = serviceHost
            canonicalURI = "/\(config.bucket)/\(encodedKey)"
        } else {
            // A port stays at the end of the authority, so prefixing the
            // bucket as a subdomain is still the right shape: with
            // "localhost:9000" this reads "bucket.localhost:9000".
            host = "\(config.bucket).\(serviceHost)"
            canonicalURI = "/\(encodedKey)"
        }
        guard let url = URL(string: "\(scheme)://\(host)\(canonicalURI)") else {
            throw UploadError.invalidConfiguration(
                "Bucket, region and endpoint do not form a valid URL: "
                    + "\(config.bucket) / \(config.region) / \(config.endpoint)"
            )
        }
        return Endpoint(url: url, canonicalURI: canonicalURI, host: host)
    }

    // MARK: - Typed-input validation

    /// A custom endpoint, split into the parts a signed request needs.
    struct ParsedEndpoint: Equatable {
        let scheme: String
        /// Host including the port when one was given: SigV4 signs the `host`
        /// header verbatim, and a non-default port belongs in it.
        let host: String
    }

    /// Splits a typed endpoint into scheme and host, or nil for "use Amazon".
    ///
    /// Accepts what people actually paste — a bare host, a host with a port,
    /// either with a scheme in front, with or without a trailing slash.
    ///
    /// Throws rather than guessing when the value carries a path. A path prefix
    /// would have to be folded into the canonical URI to be signed correctly,
    /// and silently dropping it signs one path and sends another: a 403 with
    /// nothing in it to explain why.
    static func parseEndpoint(_ raw: String) throws -> ParsedEndpoint? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var scheme = "https"
        if let separator = text.range(of: "://") {
            let given = String(text[text.startIndex..<separator.lowerBound]).lowercased()
            guard given == "https" || given == "http" else {
                throw UploadError.invalidConfiguration(
                    "Endpoint scheme has to be https or http: \(raw)")
            }
            scheme = given
            text = String(text[separator.upperBound...])
        }

        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else {
            throw UploadError.invalidConfiguration("Endpoint has no host: \(raw)")
        }
        guard !text.contains("/") else {
            throw UploadError.invalidConfiguration(
                "Endpoint has to be a host with no path: \(raw)")
        }
        guard text.allSatisfy(Self.isHostCharacter) else {
            throw UploadError.invalidConfiguration(
                "Endpoint has characters that cannot appear in a host: \(raw)")
        }
        // Host names are case-insensitive and SigV4 signs them lower-cased.
        return ParsedEndpoint(scheme: scheme, host: text.lowercased())
    }

    private static func isHostCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber
            || character == "." || character == "-" || character == ":"
    }

    /// The bucket name goes straight into a host name or a path, so anything
    /// that would corrupt the canonical URI has to be refused before a
    /// signature is computed over one path and the request sent to another.
    ///
    /// Deliberately narrow. Length and case are the service's rules to
    /// enforce; rejecting a name some service happens to accept would be worse
    /// than passing it along.
    static func validateBucket(_ bucket: String) throws {
        guard !bucket.isEmpty else {
            throw UploadError.invalidConfiguration("Bucket name is empty.")
        }
        let unsafe: Set<Character> = ["/", "?", "#", "@", ":", "\\"]
        guard !bucket.contains(where: { unsafe.contains($0) || $0.isWhitespace }) else {
            throw UploadError.invalidConfiguration(
                "Bucket name cannot contain whitespace or any of / ? # @ : \\ "
                    + "— got \(bucket)")
        }
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
    private func objectFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).png"
    }

    // MARK: - Image encoding

    private func pngData(from image: CGImage) -> Data? {
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutable, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
    }
}
