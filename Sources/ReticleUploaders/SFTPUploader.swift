import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Uploads a screenshot to a remote server via SFTP using the system curl binary.
///
/// Credentials are passed through a temporary `.netrc` file (never on the command line)
/// so they cannot be captured by other processes via `ps`. The temp file is always
/// deleted — even if the transfer fails.
///
/// Authentication precedence:
/// 1. Private key file (if `config.privateKeyPath` is non-empty)
/// 2. Password via `.netrc` (if `config.password` is non-empty)
public struct SFTPUploader: Uploader, Sendable {

    public struct Config: Sendable {
        /// Hostname or IP of the SFTP server.
        public var host: String
        /// SSH port. Default: 22.
        public var port: Int
        /// SSH username.
        public var username: String
        /// SSH password. Leave empty when using key authentication.
        public var password: String
        /// Absolute path to the PEM-encoded private key on the local machine.
        /// Leave empty to use password authentication.
        public var privateKeyPath: String
        /// Remote directory path, e.g. "/var/www/screenshots/". Must end with "/".
        public var remotePath: String
        /// Base URL prepended to the filename to form the public link,
        /// e.g. "https://cdn.example.com/screenshots/".
        public var publicBaseURL: String

        public init(host: String, port: Int = 22, username: String, password: String = "",
                    privateKeyPath: String = "", remotePath: String = "/",
                    publicBaseURL: String = "") {
            self.host = host; self.port = port; self.username = username
            self.password = password; self.privateKeyPath = privateKeyPath
            self.remotePath = remotePath.hasSuffix("/") ? remotePath : remotePath + "/"
            self.publicBaseURL = publicBaseURL.hasSuffix("/") ? publicBaseURL : publicBaseURL + "/"
        }
    }

    public let config: Config

    public init(config: Config) { self.config = config }

    // MARK: - Upload

    public func upload(_ image: CGImage) async throws -> URL {
        let filename = "reticle_\(Int(Date().timeIntervalSince1970)).png"

        // 1. Write image to a temp PNG file.
        let tmpImage = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try encodePNG(image, to: tmpImage)
        defer { try? FileManager.default.removeItem(at: tmpImage) }

        // 2. Write a temp .netrc for password auth.
        let netrcURL = try config.password.isEmpty || !config.privateKeyPath.isEmpty
            ? nil : makeNetrcFile()
        defer { if let u = netrcURL { try? FileManager.default.removeItem(at: u) } }

        // 3. Build curl arguments.
        let remoteURL = "sftp://\(config.username)@\(config.host):\(config.port)\(config.remotePath)\(filename)"
        var args = [
            "--upload-file", tmpImage.path,
            "--insecure",      // accept unknown host keys; the user should manage known_hosts separately
            "--silent",
            "--show-error",
            remoteURL,
        ]
        appendAuthArgs(to: &args, netrcURL: netrcURL)

        // 4. Run curl.
        let output = try await runProcess("/usr/bin/curl", arguments: args)
        if !output.errorOutput.isEmpty {
            throw SFTPError.transferFailed(output.errorOutput)
        }

        // 5. Return the public URL.
        let base = config.publicBaseURL.isEmpty
            ? "sftp://\(config.host)\(config.remotePath)"
            : config.publicBaseURL
        guard let url = URL(string: base + filename) else {
            throw SFTPError.invalidPublicURL(base + filename)
        }
        return url
    }

    /// Verifies that a directory listing of `remotePath` succeeds.
    public func testConnection() async throws {
        let netrcURL = try config.password.isEmpty || !config.privateKeyPath.isEmpty
            ? nil : makeNetrcFile()
        defer { if let u = netrcURL { try? FileManager.default.removeItem(at: u) } }

        let remote = "sftp://\(config.username)@\(config.host):\(config.port)\(config.remotePath)"
        var args = ["--list-only", "--insecure", "--silent", "--show-error", remote]
        appendAuthArgs(to: &args, netrcURL: netrcURL)

        let output = try await runProcess("/usr/bin/curl", arguments: args)
        if !output.errorOutput.isEmpty {
            throw SFTPError.transferFailed(output.errorOutput)
        }
    }

    // MARK: - Helpers

    /// Creates a temp .netrc with 0o600 permissions atomically (file appears with correct permissions from the start).
    private func makeNetrcFile() throws -> URL {
        let content = "machine \(config.host)\nlogin \(config.username)\npassword \(config.password)\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reticle_netrc_\(UUID().uuidString)")
        guard let data = content.data(using: .utf8),
              FileManager.default.createFile(
                atPath: url.path, contents: data,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
        else { throw SFTPError.transferFailed("Failed to write credentials file") }
        return url
    }

    private func appendAuthArgs(to args: inout [String], netrcURL: URL?) {
        if let nc = netrcURL {
            args += ["--netrc-file", nc.path]
        } else if !config.privateKeyPath.isEmpty {
            args += ["--key", config.privateKeyPath]
        }
    }

    private func encodePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SFTPError.imageEncodingFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest)
        else { throw SFTPError.imageEncodingFailed }
    }

    private func runProcess(_ executable: String,
                            arguments: [String]) async throws -> (output: String, errorOutput: String) {
        return try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError  = stderrPipe

            proc.terminationHandler = { _ in
                let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                continuation.resume(returning: (out, err))
            }
            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Errors

public enum SFTPError: Error, LocalizedError {
    case imageEncodingFailed
    case transferFailed(String)
    case invalidPublicURL(String)

    public var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:      return "Failed to encode image as PNG for SFTP upload."
        case .transferFailed(let msg):  return "SFTP transfer failed: \(msg)"
        case .invalidPublicURL(let u):  return "Could not form a valid URL from: \(u)"
        }
    }
}
