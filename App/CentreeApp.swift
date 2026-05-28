import SwiftUI

@main
struct CentreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = CaptureCoordinator()

    /// Holds global hotkey registrations for the app lifetime.
    private let hotkeyManager = HotkeyManager()

    init() {
        hotkeyManager.onCaptureRegion       = { [self] in coordinator.captureWithOverlay()   }
        hotkeyManager.onCaptureFullScreen   = { [self] in coordinator.captureFullScreen()    }
        hotkeyManager.onClipboardHistory    = { ClipboardHistoryPanel.shared.toggle()        }
        hotkeyManager.onCaptureLastRegion   = { [self] in coordinator.captureLastRegion()    }
        hotkeyManager.onCaptureWindowPicker = { [self] in coordinator.captureWindowPicker()  }
        hotkeyManager.onWorkflow            = { [self] id in coordinator.runWorkflow(profileID: id) }

        AutoCaptureManager.shared.captureAction = { [self] mode in
            switch mode {
            case .activeScreen, .fullScreen: coordinator.captureFullScreen()
            case .lastRegion:               coordinator.captureLastRegion()
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
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
