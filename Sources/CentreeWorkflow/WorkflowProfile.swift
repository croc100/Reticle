import CentreeCore
import Foundation

/// One hotkey → one complete capture workflow.
///
/// Persisted to disk as JSON; loaded at launch and when the user changes settings.
public struct WorkflowProfile: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// Carbon key code + modifier flags, serialized as integers.
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var captureMode: WorkflowCaptureMode
    public var maskProfileID: UUID?
    public var outputDestinations: [OutputDestination]

    public init(
        id: UUID = UUID(),
        name: String,
        keyCode: UInt32,
        modifiers: UInt32,
        captureMode: WorkflowCaptureMode = .region,
        maskProfileID: UUID? = nil,
        outputDestinations: [OutputDestination] = [.clipboard]
    ) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.captureMode = captureMode
        self.maskProfileID = maskProfileID
        self.outputDestinations = outputDestinations
    }
}

public enum WorkflowCaptureMode: String, Codable, Sendable {
    case region
    case window
    case fullScreen
}

public enum OutputDestination: String, Codable, Sendable {
    case clipboard
    case localFile
    case imgur
    case s3
    case sftp
}
