import AppKit
import ReticleCapture

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 숨김 — 메뉴바 전용 앱
        NSApp.setActivationPolicy(.accessory)

        // 권한이 없으면 System Settings로 안내
        Task { await checkScreenRecordingPermission() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Private

    private func checkScreenRecordingPermission() async {
        guard !(await PermissionChecker.hasPermission()) else { return }

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
            Reticle needs Screen Recording access to take screenshots.

            Grant access in System Settings → Privacy & Security → Screen Recording, \
            then relaunch the app.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        }
    }
}
