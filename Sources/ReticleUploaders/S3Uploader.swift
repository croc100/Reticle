import CoreGraphics
import CryptoKit
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
        /// AWS region identifier, e.g. "us-east-1"
        public var region: String
        /// IAM access key ID
        public var accessKeyID: String
        /// IAM secret access key
        public var secretAccessKey: String
        /// Optional key prefix (folder), e.g. "screenshots/".  No leading slash.
        public var keyPrefix: String
        /// If non-empty, the public link is formed as "\(publicURLTemplate){key}".
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

    public func upload(_ image: CGImage) async throws -> URL {
        guard let pngData = pngData(from: image) else {
            throw UploadError.encodingFailed
        }

        // Generate a date-sortable filename
        let filename = objectFilename()
        let key = config.keyPrefix + filename

        let request = try buildSignedRequest(key: key, body: pngData)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.networkError(underlying: URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.serverError(statusCode: http.statusCode, body: "S3 PUT failed")
        }

        return publicURL(for: key)
    }

    // MARK: - URL helpers

    private func endpointURL(key: String) -> URL {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        if config.pathStyle {
            return URL(string: "https://s3.\(config.region).amazonaws.com/\(config.bucket)/\(encodedKey)")!
        } else {
            return URL(string: "https://\(config.bucket).s3.\(config.region).amazonaws.com/\(encodedKey)")!
        }
    }

    private func publicURL(for key: String) -> URL {
        if !config.publicURLTemplate.isEmpty {
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            return URL(string: config.publicURLTemplate + encodedKey)!
        }
        return endpointURL(key: key)
    }

    private func objectFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return "\(fmt.string(from: Date()))-\(UUID().uuidString.prefix(8)).png"
    }

    // MARK: - AWS Signature V4

    private func buildSignedRequest(key: String, body: Data) throws -> URLRequest {
        let url = endpointURL(key: key)
        let now = Date()

        // Timestamps
        let datetimeString = iso8601DateTime(now)
        let dateString     = String(datetimeString.prefix(8))

        // Payload hash (hex-encoded SHA-256 of body)
        let payloadHash = SHA256.hash(data: body).hexString

        // Build headers (must be in lowercase, sorted for canonical form)
        let host = url.host!
        var headers: [(String, String)] = [
            ("content-type",        "image/png"),
            ("host",                host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date",          datetimeString),
        ]
        headers.sort { $0.0 < $1.0 }

        // Canonical request
        let canonicalHeaders  = headers.map { "\($0.0):\($0.1)" }.joined(separator: "\n") + "\n"
        let signedHeadersList = headers.map { $0.0 }.joined(separator: ";")
        let canonicalURI      = url.path.isEmpty ? "/" : url.path
        let canonicalQuery    = ""   // no query params on PUT

        let canonicalRequest = [
            "PUT",
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeadersList,
            payloadHash,
        ].joined(separator: "\n")

        // String to sign
        let credentialScope = "\(dateString)/\(config.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            datetimeString,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString,
        ].joined(separator: "\n")

        // Derive signing key: HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), "s3"), "aws4_request")
        let signingKey = deriveSigningKey(secret: config.secretAccessKey, date: dateString,
                                         region: config.region, service: "s3")

        // Signature
        let signature = hexString(HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: signingKey)
        ))

        // Authorization header
        let authorization =
            "AWS4-HMAC-SHA256 " +
            "Credential=\(config.accessKeyID)/\(credentialScope), " +
            "SignedHeaders=\(signedHeadersList), " +
            "Signature=\(signature)"

        // Assemble URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody   = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private func deriveSigningKey(secret: String, date: String, region: String, service: String) -> Data {
        func hmac(_ key: Data, _ message: String) -> Data {
            Data(HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: SymmetricKey(data: key)
            ))
        }
        let kDate    = hmac(Data(("AWS4" + secret).utf8), date)
        let kRegion  = hmac(kDate,    region)
        let kService = hmac(kRegion,  service)
        let kSigning = hmac(kService, "aws4_request")
        return kSigning
    }

    // MARK: - Date helpers

    private func iso8601DateTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat  = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone    = TimeZone(identifier: "UTC")
        fmt.locale      = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
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

// MARK: - Hex-string helpers

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

// HashedAuthenticationCode (HMAC result) is not a Digest, but is Sequence<UInt8>
private func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
}
