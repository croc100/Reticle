import SwiftUI

@main
struct CentreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = CaptureCoordinator()

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
