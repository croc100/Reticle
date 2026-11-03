import CryptoKit
import Foundation

/// AWS Signature Version 4 — the subset S3 needs.
///
/// Split out of ``S3Uploader`` so the rules live in one place rather than once
/// per request shape, and so they can be checked against AWS's published test
/// vectors without a bucket, credentials, or a network.
enum SigV4 {

    static let algorithm = "AWS4-HMAC-SHA256"

    // MARK: - Percent-encoding

    /// Percent-encodes an object key for the request line *and* for the string
    /// that gets signed.  Both must use this same output, or S3 computes the
    /// signature over a path that differs from the one it received.
    ///
    /// Only RFC 3986 unreserved characters survive, plus `/`, which stays
    /// literal because S3 keys are hierarchical and the separator is not
    /// encoded.  `CharacterSet.urlPathAllowed` is the obvious choice here and
    /// is wrong: it passes `+ , ; = : @ ! $ & ' ( ) *` through unencoded, and
    /// S3 encodes them before signing.
    static func encodeObjectKey(_ key: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(key.utf8.count)
        for byte in key.utf8 {
            if isUnreserved(byte) || byte == UInt8(ascii: "/") {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }

    // MARK: - Canonical request

    /// Builds the canonical request and the matching `SignedHeaders` list.
    ///
    /// `uri` must already be percent-encoded by ``encodeObjectKey(_:)``.
    static func canonicalRequest(
        method: String,
        uri: String,
        query: String,
        headers: [(name: String, value: String)],
        payloadHash: String
    ) -> (canonical: String, signedHeaders: String) {
        let sorted = headers.sorted { $0.name < $1.name }
        let canonicalHeaders = sorted.map { "\($0.name):\($0.value)\n" }.joined()
        let signedHeaders = sorted.map { $0.name }.joined(separator: ";")
        let canonical = [
            method,
            uri,
            query,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
        return (canonical, signedHeaders)
    }

    // MARK: - Signing

    static func credentialScope(date: String, region: String, service: String) -> String {
        "\(date)/\(region)/\(service)/aws4_request"
    }

    static func stringToSign(datetime: String, scope: String, canonicalRequest: String) -> String {
        [
            algorithm,
            datetime,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
    }

    /// `HMAC(HMAC(HMAC(HMAC("AWS4" + secret, date), region), service), "aws4_request")`
    static func signingKey(secret: String, date: String, region: String, service: String) -> Data {
        var key = Data(("AWS4" + secret).utf8)
        for message in [date, region, service, "aws4_request"] {
            key = Data(HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: SymmetricKey(data: key)
            ))
        }
        return key
    }

    static func signature(stringToSign: String, key: Data) -> String {
        hexString(HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: key)
        ))
    }

    static func authorizationHeader(
        accessKeyID: String,
        scope: String,
        signedHeaders: String,
        signature: String
    ) -> String {
        "\(algorithm) Credential=\(accessKeyID)/\(scope), " +
        "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    // MARK: - Helpers

    static func sha256Hex(_ data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    /// `x-amz-date` format: `20150830T123600Z`, always UTC and always Gregorian.
    static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
