import CoreGraphics
import Foundation
import ImageIO

/// Uploads a CGImage to any HTTP endpoint.
///
/// Supports multipart/form-data (when ``fileFormField`` is set) or a raw
/// binary PUT body.  After a successful response the URL is extracted from
/// the JSON body via a dot-notation path (e.g. `"data.url"` or `"link"`),
/// or from a URL template that interpolates the raw response text.
///
/// This covers a huge range of destinations:
///  - Discord webhooks  (field: "file", path: "attachments.0.proxy_url")
///  - Cloudinary        (field: "file", path: "secure_url")
///  - GitHub Gist / raw upload services
///  - Custom self-hosted upload servers
public struct CustomHTTPUploader: Uploader, Sendable {

    // MARK: - Configuration

    public struct Config: Sendable {
        /// HTTP method ("POST" or "PUT").  Defaults to POST.
        public var method: String
        /// Full endpoint URL, e.g. "https://example.com/upload"
        public var url: String
        /// Form field name for the image in a multipart request.
        /// Leave empty for a raw binary body (Content-Type: image/png).
        public var fileFormField: String
        /// Optional filename override in the multipart Content-Disposition.
        /// Defaults to "screenshot.png".
        public var filename: String
        /// Dot-path into the JSON response body to extract the public URL.
        /// E.g. "data.url" extracts `response["data"]["url"]`.
        /// Leave empty if the entire response body is the URL.
        public var responseURLPath: String
        /// Additional HTTP headers (e.g. Authorization: Bearer …).
        public var headers: [String: String]

        public init(
            method: String = "POST",
            url: String,
            fileFormField: String = "file",
            filename: String = "screenshot.png",
            responseURLPath: String = "",
            headers: [String: String] = [:]
        ) {
            self.method = method
            self.url = url
            self.fileFormField = fileFormField
            self.filename = filename
            self.responseURLPath = responseURLPath
            self.headers = headers
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

        guard let endpointURL = URL(string: config.url), !config.url.isEmpty else {
            throw UploadError.encodingFailed
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = config.method.uppercased()

        // Set custom headers
        for (name, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if config.fileFormField.isEmpty {
            // Raw binary body
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
            request.httpBody = pngData
        } else {
            // Multipart/form-data
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(data: pngData,
                                             field: config.fileFormField,
                                             filename: config.filename,
                                             boundary: boundary)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.networkError(underlying: URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.serverError(statusCode: http.statusCode, body: body)
        }

        // Extract URL from response
        return try extractURL(from: data, path: config.responseURLPath)
    }

    // MARK: - Response parsing

    /// Extracts a URL string from `data` using a dot-notation `path`.
    ///
    /// If `path` is empty the entire response body (trimmed) is used.
    /// The path supports integer indices for arrays: `"attachments.0.proxy_url"`.
    private func extractURL(from data: Data, path: String) throws -> URL {
        if path.isEmpty {
            // Treat the whole body as the URL
            let raw = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), url.scheme != nil else {
                throw UploadError.serverError(statusCode: 0, body: "Response is not a URL: \(raw)")
            }
            return url
        }

        // Parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.serverError(statusCode: 0, body: "JSON parse failed: \(body)")
        }

        // Traverse dot path
        let components = path.components(separatedBy: ".")
        var current: Any = json
        for component in components {
            if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else if let array = current as? [Any], let idx = Int(component), idx < array.count {
                current = array[idx]
            } else {
                throw UploadError.serverError(statusCode: 0,
                    body: "JSON path '\(path)' not found at '\(component)'")
            }
        }

        guard let urlString = current as? String, let url = URL(string: urlString) else {
            throw UploadError.serverError(statusCode: 0,
                body: "Value at path '\(path)' is not a URL string")
        }
        return url
    }

    // MARK: - Multipart body

    private func multipartBody(data: Data, field: String, filename: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: image/png\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
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
