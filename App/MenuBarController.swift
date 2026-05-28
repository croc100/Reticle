import SwiftUI
import Defaults
import HotKey
import CentreeCore

/// SwiftUI content for the MenuBarExtra dropdown.
struct MenuBarMenuView: View {
    @EnvironmentObject var coordinator: CaptureCoordinator
    @Default(.savedRegions)    var savedRegions
    @Default(.lastCaptureRect) var lastCaptureRect
    @Default(.workflowProfiles) var workflowProfiles
    @ObservedObject private var autoCapture = AutoCaptureManager.shared

    var body: some View {
        Button("Capture Region        ⌘⇧4") { coordinator.captureWithOverlay() }
        Button("Capture Full Screen   ⌘⇧3") { coordinator.captureFullScreen() }

        // Per-monitor capture submenu (populated from connected NSScreens)
        Menu("Capture Screen") {
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { idx, screen in
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID ?? CGMainDisplayID()
                let isMain = screen == NSScreen.main
                Button("\(isMain ? "Main Screen" : "Screen \(idx + 1)")  —  \(Int(screen.frame.width))×\(Int(screen.frame.height))") {
                    coordinator.captureDisplay(displayID: displayID)
                }
            }
        }

        Button("Capture Window…")            { coordinator.captureWindowPicker() }
        Button("Scroll Capture…")            { coordinator.captureScroll() }

        Button("Repeat Last Region") { coordinator.captureLastRegion() }
            .disabled(lastCaptureRect == nil)

        if !savedRegions.isEmpty {
            Divider()
            Menu("Saved Regions") {
                ForEach(savedRegions) { region in
                    Button(region.name) { coordinator.captureSavedRegion(id: region.id) }
                }
            }
        }

        let enabledWorkflows = workflowProfiles.filter { $0.enabled }
        if !enabledWorkflows.isEmpty {
            Divider()
            Menu("Workflows") {
                ForEach(enabledWorkflows) { profile in
                    Button(workflowLabel(profile)) {
                        coordinator.runWorkflow(profileID: profile.id)
                    }
                }
            }
        }

        Divider()

        Button("Open for Editing…") { coordinator.openForEditing() }
        Button("Color Picker") { ColorPickerPanel.shared.activate() }

        Button(autoCapture.isRunning ? "Stop Auto Capture" : "Start Auto Capture") {
            autoCapture.toggle()
        }

        Divider()

        Button("Capture History…") { CaptureHistoryPanel.shared.toggle() }
        Button("Clipboard History    ⌘⇧V") { ClipboardHistoryPanel.shared.toggle() }

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

    // MARK: - Helpers

    private func workflowLabel(_ profile: StoredWorkflowProfile) -> String {
        guard profile.keyCode > 0, let key = Key(carbonKeyCode: profile.keyCode) else {
            return profile.name
        }
        let mods = CarbonModifiers.symbol(profile.modifiers)
        return "\(profile.name)  \(mods)\(key.description.uppercased())"
    }
}
