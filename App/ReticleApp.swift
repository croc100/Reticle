import SwiftUI
import ReticleRecorder

@main
struct ReticleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator       = CaptureCoordinator()
    @StateObject private var recorderController = ScreenRecorderController()

    /// Holds global hotkey registrations for the app lifetime.
    private let hotkeyManager = HotkeyManager()

    init() {
        // Capture the class instances directly so long-lived singletons
        // don't retain the App struct value (which contains @StateObject wrappers).
        let coord = coordinator

        hotkeyManager.onCaptureRegion       = { coord.captureWithOverlay()          }
        hotkeyManager.onCaptureFullScreen   = { coord.captureFullScreen()           }
        hotkeyManager.onClipboardHistory    = { ClipboardHistoryPanel.shared.toggle() }
        hotkeyManager.onCaptureLastRegion   = { coord.captureLastRegion()           }
        hotkeyManager.onCaptureWindowPicker = { coord.captureWindowPicker()         }
        hotkeyManager.onWorkflow            = { id in coord.runWorkflow(profileID: id) }

        AutoCaptureManager.shared.captureAction = { [coord] mode in
            switch mode {
            case .activeScreen, .fullScreen: coord.captureFullScreen()
            case .lastRegion:               coord.captureLastRegion()
            }
        }

        // Start clipboard polling immediately so history is captured from launch
        _ = ClipboardHistoryManager.shared
    }

    var body: some Scene {
        // MenuBarExtra keeps the app alive and puts the icon in the menu bar.
        // Without this scene a Settings-only app terminates immediately.
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(coordinator)
                .environmentObject(recorderController)
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
