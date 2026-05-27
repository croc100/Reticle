import AppKit
import CentreeCore
import Foundation

// MARK: - RevealInFinderTask

/// Opens a Finder window and selects the saved file.
public struct RevealInFinderTask: AfterOutputTask {
    public init() {}
    public func execute(context: CaptureContext) async throws {
        guard let url = context.outputURLs.first else { return }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - CopyFilePathTask

/// Copies the saved file's absolute path to the clipboard as plain text.
public struct CopyFilePathTask: AfterOutputTask {
    public init() {}
    public func execute(context: CaptureContext) async throws {
        guard let url = context.outputURLs.first else { return }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
        }
    }
}

// MARK: - OpenInViewerTask

/// Opens the saved file in the system default image viewer (usually Preview.app).
public struct OpenInViewerTask: AfterOutputTask {
    public init() {}
    public func execute(context: CaptureContext) async throws {
        guard let url = context.outputURLs.first else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}
