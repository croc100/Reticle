import SwiftUI
import Defaults
import HotKey
import CentreeCore

// MARK: - Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General",  systemImage: "gearshape") }
            HotkeysTab()
                .tabItem { Label("Hotkeys",  systemImage: "keyboard") }
            OutputTab()
                .tabItem { Label("Output",   systemImage: "square.and.arrow.down") }
            PipelineTab()
                .tabItem { Label("Pipeline", systemImage: "arrow.trianglehead.2.clockwise") }
            RegionsTab()
                .tabItem { Label("Regions",  systemImage: "rectangle.dashed") }
        }
        .frame(width: 540, height: 420)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Default(.captureSoundEnabled) var soundEnabled
    @Default(.captureSoundName)    var soundName
    @Default(.captureDelay)        var captureDelay

    private let sounds = ["", "Grab", "Glass", "Blow", "Funk", "Pop", "Tink"]

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Play sound after capture", isOn: $soundEnabled)
                if soundEnabled {
                    Picker("Sound", selection: $soundName) {
                        ForEach(sounds, id: \.self) { name in
                            Text(name.isEmpty ? "Default (Grab)" : name).tag(name)
                        }
                    }
                    .onChange(of: soundName) { new in
                        NSSound(named: new.isEmpty ? "Grab" : new)?.play()
                    }
                }
            }

            Section("Capture Delay") {
                Stepper(value: $captureDelay, in: 0...10) {
                    if captureDelay == 0 {
                        Text("No delay")
                    } else {
                        Text("\(captureDelay) second\(captureDelay == 1 ? "" : "s")")
                    }
                }
                Text("Countdown shown before every capture")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkeys Tab

private struct HotkeysTab: View {
    @Default(.regionHotkeyKeyCode)       var regionCode
    @Default(.regionHotkeyMods)          var regionMods
    @Default(.fullscreenHotkeyKeyCode)   var fullCode
    @Default(.fullscreenHotkeyMods)      var fullMods
    @Default(.lastRegionHotkeyKeyCode)   var lastCode
    @Default(.lastRegionHotkeyMods)      var lastMods
    @Default(.windowPickerHotkeyKeyCode) var winCode
    @Default(.windowPickerHotkeyMods)    var winMods

    var body: some View {
        Form {
            Section("Capture") {
                HotkeyRow(label: "Capture Region",       keyCode: $regionCode, modifiers: $regionMods)
                HotkeyRow(label: "Capture Full Screen",  keyCode: $fullCode,   modifiers: $fullMods)
                HotkeyRow(label: "Repeat Last Region",   keyCode: $lastCode,   modifiers: $lastMods)
                HotkeyRow(label: "Capture Window…",      keyCode: $winCode,    modifiers: $winMods)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Output Tab

private struct OutputTab: View {
    @Default(.screenshotsDirectory) var directory
    @Default(.filenamePattern)      var pattern

    var body: some View {
        Form {
            Section("Save Location") {
                HStack {
                    Text(directory.path(percentEncoded: false))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { pickDirectory() }
                }
            }
            Section {
                TextField("Pattern", text: $pattern).fontDesign(.monospaced)
                Text("Tokens: %year% %month% %day% %hour% %minute% %second% %counter% %uuid%")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Filename Pattern") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { directory = url }
    }
}

// MARK: - Pipeline Tab

private struct PipelineTab: View {
    @Default(.afterCaptureOptions) var options

    // Groups for display
    private let outputTasks: [AfterCaptureOption]    = [.copyToClipboard, .saveToFile]
    private let postSaveTasks: [AfterCaptureOption]  = [.revealInFinder, .copyFilePath, .openInViewer]
    private let notifyTasks: [AfterCaptureOption]    = [.showNotification]

    var body: some View {
        Form {
            Section("Output") {
                ForEach(outputTasks, id: \.self) { opt in
                    PipelineRow(option: opt, options: $options)
                }
            }

            Section {
                ForEach(postSaveTasks, id: \.self) { opt in
                    PipelineRow(option: opt, options: $options)
                        .disabled(!options.contains(.saveToFile))
                }
                if !options.contains(.saveToFile) {
                    Text("Enable \"Save image to file\" to use these")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("After Save") }

            Section("Notification") {
                ForEach(notifyTasks, id: \.self) { opt in
                    PipelineRow(option: opt, options: $options)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PipelineRow: View {
    let option: AfterCaptureOption
    @Binding var options: [AfterCaptureOption]

    private var isOn: Binding<Bool> {
        Binding(
            get: { options.contains(option) },
            set: { enabled in
                if enabled { if !options.contains(option) { options.append(option) } }
                else { options.removeAll { $0 == option } }
            }
        )
    }

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(option.title)
                Text(option.description)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Regions Tab

private struct RegionsTab: View {
    @Default(.savedRegions)    var savedRegions
    @Default(.lastCaptureRect) var lastCaptureRect

    @State private var newName: String = ""
    @State private var newX: String = "0"
    @State private var newY: String = "0"
    @State private var newW: String = "800"
    @State private var newH: String = "600"
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if let last = lastCaptureRect {
                    Button("+ Add Last Region") {
                        newName = "Region \(savedRegions.count + 1)"
                        newX = String(Int(last.x)); newY = String(Int(last.y))
                        newW = String(Int(last.width)); newH = String(Int(last.height))
                        showAddForm = true
                    }
                }
                Button("+ Add Manual") { showAddForm = true }
                Spacer()
            }
            .padding(10)

            if showAddForm {
                addForm
                Divider()
            }

            if savedRegions.isEmpty {
                Spacer()
                Text("No saved regions")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(savedRegions) { region in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(region.name).fontWeight(.medium)
                                Text("\(Int(region.rect.x)), \(Int(region.rect.y))  –  \(Int(region.rect.width)) × \(Int(region.rect.height))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { delete(region) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Name:").frame(width: 60, alignment: .trailing)
                TextField("Region name", text: $newName).frame(maxWidth: 160)
            }
            HStack {
                Text("X:").frame(width: 60, alignment: .trailing)
                TextField("0", text: $newX).frame(width: 60)
                Text("Y:").frame(width: 20, alignment: .trailing)
                TextField("0", text: $newY).frame(width: 60)
                Text("W:").frame(width: 20, alignment: .trailing)
                TextField("800", text: $newW).frame(width: 60)
                Text("H:").frame(width: 20, alignment: .trailing)
                TextField("600", text: $newH).frame(width: 60)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddForm = false; resetForm() }
                Button("Save") { saveRegion() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func saveRegion() {
        let rect = CGRect(
            x: Double(newX) ?? 0, y: Double(newY) ?? 0,
            width: Double(newW) ?? 800, height: Double(newH) ?? 600
        )
        savedRegions.append(SavedRegion(name: newName, rect: rect))
        showAddForm = false
        resetForm()
    }

    private func delete(_ region: SavedRegion) {
        savedRegions.removeAll { $0.id == region.id }
    }

    private func resetForm() {
        newName = ""; newX = "0"; newY = "0"; newW = "800"; newH = "600"
    }
}

// MARK: - HotkeyRow

private struct HotkeyRow: View {
    let label: String
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false

    private var displayString: String {
        guard keyCode > 0, let key = Key(carbonKeyCode: keyCode) else { return "–" }
        return CarbonModifiers.symbol(modifiers) + key.description.uppercased()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HotkeyRecorderView(
                keyCode: $keyCode, modifiers: $modifiers,
                isRecording: $isRecording, displayString: displayString
            )
            .frame(width: 130, height: 24)
        }
    }
}

// MARK: - HotkeyRecorderView

private struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var isRecording: Bool
    let displayString: String

    func makeNSView(context: Context) -> RecorderButton {
        let btn = RecorderButton(); btn.coordinator = context.coordinator; return btn
    }
    func updateNSView(_ btn: RecorderButton, context: Context) {
        btn.title = isRecording ? "Press keys…" : displayString
        btn.isRecording = isRecording
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HotkeyRecorderView
        init(_ parent: HotkeyRecorderView) { self.parent = parent }
        func didRecord(keyCode: UInt32, modifiers: UInt32) {
            parent.keyCode = keyCode; parent.modifiers = modifiers; parent.isRecording = false
        }
        func startRecording()  { parent.isRecording = true  }
        func cancelRecording() { parent.isRecording = false }
    }

    final class RecorderButton: NSButton {
        weak var coordinator: Coordinator?
        var isRecording: Bool = false
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame); bezelStyle = .rounded; target = self; action = #selector(toggle)
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func toggle() { isRecording ? stopMonitor() : startMonitor() }

        private func startMonitor() {
            coordinator?.startRecording()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                let carbon = CarbonModifiers.fromNSFlags(event.modifierFlags)
                self.coordinator?.didRecord(keyCode: UInt32(event.keyCode), modifiers: carbon)
                self.stopMonitor()
                return nil
            }
        }
        private func stopMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            coordinator?.cancelRecording()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopMonitor() }
        }
    }
}

// MARK: - Key description

extension Key: CustomStringConvertible {
    public var description: String {
        switch self {
        case .a: return "A"; case .b: return "B"; case .c: return "C"
        case .d: return "D"; case .e: return "E"; case .f: return "F"
        case .g: return "G"; case .h: return "H"; case .i: return "I"
        case .j: return "J"; case .k: return "K"; case .l: return "L"
        case .m: return "M"; case .n: return "N"; case .o: return "O"
        case .p: return "P"; case .q: return "Q"; case .r: return "R"
        case .s: return "S"; case .t: return "T"; case .u: return "U"
        case .v: return "V"; case .w: return "W"; case .x: return "X"
        case .y: return "Y"; case .z: return "Z"
        case .zero: return "0"; case .one: return "1"; case .two: return "2"
        case .three: return "3"; case .four: return "4"; case .five: return "5"
        case .six: return "6"; case .seven: return "7"; case .eight: return "8"
        case .nine: return "9"
        case .space: return "Space"; case .return: return "↩"; case .tab: return "⇥"
        case .delete: return "⌫"; case .escape: return "⎋"
        case .leftArrow: return "←"; case .rightArrow: return "→"
        case .upArrow: return "↑"; case .downArrow: return "↓"
        case .f1: return "F1"; case .f2: return "F2"; case .f3: return "F3"
        case .f4: return "F4"; case .f5: return "F5"; case .f6: return "F6"
        case .f7: return "F7"; case .f8: return "F8"; case .f9: return "F9"
        case .f10: return "F10"; case .f11: return "F11"; case .f12: return "F12"
        default: return "?"
        }
    }
}
