import SwiftUI
import Defaults
import HotKey
import ReticleCore

/// SwiftUI content for the MenuBarExtra dropdown.
struct MenuBarMenuView: View {
    @EnvironmentObject var coordinator: CaptureCoordinator
    @Default(.savedRegions)    var savedRegions
    @Default(.lastCaptureRect) var lastCaptureRect
    @Default(.workflowProfiles) var workflowProfiles
    @Default(.regionHotkeyKeyCode)    var regionCode
    @Default(.regionHotkeyMods)       var regionMods
    @Default(.fullscreenHotkeyKeyCode) var fullCode
    @Default(.fullscreenHotkeyMods)   var fullMods
    @ObservedObject private var autoCapture = AutoCaptureManager.shared

    var body: some View {
        Button(hotkeyLabel("Capture Region", keyCode: regionCode, mods: regionMods)) {
            coordinator.captureWithOverlay()
        }
        Button(hotkeyLabel("Capture Full Screen", keyCode: fullCode, mods: fullMods)) {
            coordinator.captureFullScreen()
        }

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
            // Activate first, then show settings — the menu needs to dismiss before
            // the window can reliably come to front in an accessory-policy app.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Reticle") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    // MARK: - Helpers

    /// Builds a menu label like "Capture Region      ⌃⌘4" using live Defaults values.
    private func hotkeyLabel(_ title: String, keyCode: UInt32, mods: UInt32) -> String {
        guard keyCode > 0, let key = Key(carbonKeyCode: keyCode) else { return title }
        let shortcut = CarbonModifiers.symbol(mods) + key.description.uppercased()
        // Pad with spaces so shortcut aligns roughly to the right
        return title.padding(toLength: max(title.count, 24), withPad: " ", startingAt: 0) + shortcut
    }

    private func workflowLabel(_ profile: StoredWorkflowProfile) -> String {
        guard profile.keyCode > 0, let key = Key(carbonKeyCode: profile.keyCode) else {
            return profile.name
        }
        let mods = CarbonModifiers.symbol(profile.modifiers)
        return "\(profile.name)  \(mods)\(key.description.uppercased())"
    }
}
