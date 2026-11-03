import AppKit
import CoreGraphics
import Foundation

/// Uploads an encoded screenshot to Imgur (anonymous upload, no OAuth required).
///
/// Requires a valid Imgur Client ID from https://api.imgur.com/oauth2/addclient
/// Use your own Client ID — the bundled default is for development only.
public struct ImgurUploader: Uploader, Sendable {
    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID
    }

    // MARK: - Uploader

    // swiftlint:disable:next force_unwrapping
    private static let endpoint = URL(string: "https://api.imgur.com/3/image")!

    public func upload(_ image: EncodedImage) async throws -> URL {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            data: image.data, contentType: image.contentType,
            fileExtension: image.fileExtension, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.networkError(underlying: URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.serverError(statusCode: http.statusCode, body: body)
        }

        // Parse: { "data": { "link": "https://i.imgur.com/xxxxx.png" }, "success": true }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let link = dataDict["link"] as? String,
              let url = URL(string: link) else {
            throw UploadError.encodingFailed
        }
        return url
    }

    // MARK: - Helpers

    private func multipartBody(
        data: Data, contentType: String, fileExtension: String, boundary: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"
        let contentDisposition =
            "Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.\(fileExtension)\""
        let contentTypeHeader = "Content-Type: \(contentType)"

        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("\(contentDisposition)\(crlf)".utf8))
        body.append(Data("\(contentTypeHeader)\(crlf)\(crlf)".utf8))
        body.append(data)
        body.append(Data("\(crlf)--\(boundary)--\(crlf)".utf8))
        return body
    }
}
