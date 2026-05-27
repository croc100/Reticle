import SwiftUI

/// Minimal settings UI — expanded in Phase 6 (hotkeys, output path, format).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section {
                Text("Hotkeys, output path, and format options coming in a later phase.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
