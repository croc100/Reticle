import ScreenCaptureKit
import Foundation

/// Checks and triggers the macOS Screen Recording permission dialog.
public enum PermissionChecker {
    /// Returns true if the user has granted screen recording permission.
    ///
    /// The first call to `SCShareableContent.current` presents the system permission
    /// dialog. Subsequent calls return the cached decision until the app is restarted
    /// after the user changes the setting in System Settings → Privacy → Screen Recording.
    public static func hasPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
}
