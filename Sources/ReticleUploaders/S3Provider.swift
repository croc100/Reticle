import Foundation

/// The S3-compatible services worth offering as a starting point.
///
/// Only presentation and defaults live here: every one of these speaks the
/// same signed-PUT protocol ``S3Uploader`` already implements, so the choice
/// changes what Settings pre-fills and nothing about how a request is built.
///
/// Regions are left empty wherever the value depends on the account rather
/// than on the service, so the user supplies it instead of inheriting a wrong
/// guess that fails as an unreadable 403.
public enum S3Provider: String, CaseIterable, Sendable, Codable {
    case aws
    case cloudflareR2
    case backblazeB2
    case wasabi
    case digitalOceanSpaces
    case minio
    case custom

    public var displayName: String {
        switch self {
        case .aws:                return "Amazon S3"
        case .cloudflareR2:       return "Cloudflare R2"
        case .backblazeB2:        return "Backblaze B2"
        case .wasabi:             return "Wasabi"
        case .digitalOceanSpaces: return "DigitalOcean Spaces"
        case .minio:              return "MinIO"
        case .custom:             return "Other S3-compatible"
        }
    }

    /// Whether the endpoint field applies.  Amazon's endpoint follows from the
    /// region, so there is nothing to type.
    public var usesEndpoint: Bool { self != .aws }

    /// Placeholder for the endpoint field — the shape of the host, not a value
    /// that would work for anyone.
    public var endpointPlaceholder: String {
        switch self {
        case .aws:                return ""
        case .cloudflareR2:       return "<account-id>.r2.cloudflarestorage.com"
        case .backblazeB2:        return "s3.us-west-004.backblazeb2.com"
        case .wasabi:             return "s3.us-east-1.wasabisys.com"
        case .digitalOceanSpaces: return "nyc3.digitaloceanspaces.com"
        case .minio:              return "http://localhost:9000"
        case .custom:             return "s3.example.com"
        }
    }

    /// Region to pre-fill.  Empty means the account decides and the user has to
    /// say.
    public var defaultRegion: String {
        switch self {
        // R2 has no regions in the S3 sense and rejects a signature scoped to
        // anything but "auto".
        case .cloudflareR2: return "auto"
        case .aws:          return "us-east-1"
        // MinIO ignores the region but still wants the signature to agree with
        // whatever it was started with, and this is its own default.
        case .minio:        return "us-east-1"
        case .backblazeB2, .wasabi, .digitalOceanSpaces, .custom: return ""
        }
    }

    /// Whether the service is happier addressed as `host/bucket/key` than as
    /// `bucket.host/key`.
    public var prefersPathStyle: Bool {
        switch self {
        // Both work for R2, and path style avoids needing a wildcard
        // certificate for the bucket subdomain.
        case .cloudflareR2, .minio, .custom: return true
        case .aws, .backblazeB2, .wasabi, .digitalOceanSpaces: return false
        }
    }

    /// One line of guidance for the Settings panel.
    public var note: String {
        switch self {
        case .aws:
            return "The endpoint follows from the region."
        case .cloudflareR2:
            return "Region must be \"auto\". The account ID is in the R2 dashboard."
        case .backblazeB2:
            return "The region is part of the endpoint — they have to match."
        case .wasabi:
            return "The region is part of the endpoint — they have to match."
        case .digitalOceanSpaces:
            return "Use the Spaces region, e.g. nyc3, as both endpoint and region."
        case .minio:
            return "Self-hosted. Keep http:// for a local instance."
        case .custom:
            return "Anything that speaks S3 with Signature Version 4."
        }
    }
}
