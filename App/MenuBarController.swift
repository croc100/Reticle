import SwiftUI

/// SwiftUI content for the MenuBarExtra dropdown.
struct MenuBarMenuView: View {
    @EnvironmentObject var coordinator: CaptureCoordinator

    var body: some View {
        Button("Capture Region       ⌘⇧4") { coordinator.captureWithOverlay() }
        Button("Capture Full Screen  ⌘⇧3") { coordinator.captureFullScreen() }

        Divider()

        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Centree") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
