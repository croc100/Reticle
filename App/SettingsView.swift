import SwiftUI
import Defaults
import HotKey
import ServiceManagement
import ReticleCore
import ReticleVision
import ReticleUploaders

// MARK: - Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General",   systemImage: "gearshape") }
            HotkeysTab()
                .tabItem { Label("Hotkeys",   systemImage: "keyboard") }
            OutputTab()
                .tabItem { Label("Output",    systemImage: "square.and.arrow.down") }
            PipelineTab()
                .tabItem { Label("Pipeline",  systemImage: "arrow.trianglehead.2.clockwise") }
            RegionsTab()
                .tabItem { Label("Regions",   systemImage: "rectangle.dashed") }
            StaticMaskTab()
                .tabItem { Label("Masks",     systemImage: "eye.slash") }
            WorkflowsTab()
                .tabItem { Label("Workflows", systemImage: "flowchart") }
        }
        .frame(width: 580, height: 440)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Default(.captureSoundEnabled)  var soundEnabled
    @Default(.captureSoundName)     var soundName
    @Default(.captureDelay)         var captureDelay
    @Default(.autoCaptureEnabled)   var autoCaptureEnabled
    @Default(.autoCaptureInterval)  var autoCaptureInterval
    @Default(.autoCaptureMode)      var autoCaptureMode

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let sounds = ["", "Grab", "Glass", "Blow", "Funk", "Pop", "Tink"]

    var body: some View {
        Form {
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        Task {
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try await SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = !enabled
                            }
                        }
                    }
            }

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

            Section("Auto Capture") {
                Toggle("Repeat capture on a timer", isOn: $autoCaptureEnabled)
                    .onChange(of: autoCaptureEnabled) { enabled in
                        if enabled { AutoCaptureManager.shared.start() }
                        else       { AutoCaptureManager.shared.stop()  }
                    }
                if autoCaptureEnabled {
                    Stepper(value: $autoCaptureInterval, in: 1...3600) {
                        Text("Every \(autoCaptureInterval) second\(autoCaptureInterval == 1 ? "" : "s")")
                    }
                    Picker("Mode", selection: $autoCaptureMode) {
                        ForEach(AutoCaptureMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
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
    @Default(.outputFormat)         var outputFormat
    @Default(.jpegQuality)          var jpegQuality

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

            Section("File Format") {
                Picker("Format", selection: $outputFormat) {
                    Text("PNG  (lossless)").tag("png")
                    Text("JPEG (smaller)").tag("jpeg")
                    Text("TIFF (uncompressed)").tag("tiff")
                    Text("WebP (modern)").tag("webp")
                }
                .pickerStyle(.radioGroup)
                if outputFormat == "jpeg" {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $jpegQuality, in: 0.5...1.0, step: 0.05)
                                .frame(width: 150)
                            Text("\(Int(jpegQuality * 100))%")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                TextField("Pattern", text: $pattern).fontDesign(.monospaced)
                Text("Date: %year% %yy% %month% %mon% %day% %hour% %h12% %minute% %second% %ms% %pm% %unix% %weekday% %weeknum%\nCounter: %counter% %ix% %ia%   Random: %rn% %ra% %rx% %guid% %uuid%\nSystem: %un% %cn% %app%   Image: %width% %height%")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The file extension is set automatically from the Format above.")
                    .font(.caption).foregroundStyle(.tertiary)
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
    @Default(.ocrLanguages) var ocrLanguages
    @Default(.imgurClientID) var imgurClientID
    @Default(.s3Bucket)            var s3Bucket
    @Default(.s3Region)            var s3Region
    @Default(.s3AccessKeyID)       var s3AccessKeyID
    @Default(.s3SecretAccessKey)   var s3SecretAccessKey
    @Default(.s3KeyPrefix)         var s3KeyPrefix
    @Default(.s3PublicURLTemplate) var s3PublicURLTemplate
    @Default(.s3PathStyle)         var s3PathStyle
    @Default(.customHTTPMethod)       var customHTTPMethod
    @Default(.customHTTPURL)          var customHTTPURL
    @Default(.customHTTPFileField)    var customHTTPFileField
    @Default(.customHTTPResponsePath) var customHTTPResponsePath

    @State private var sftpTestState: ConnectionTestState = .idle
    @State private var s3TestState:   ConnectionTestState = .idle
    @Default(.customHTTPHeadersRaw)   var customHTTPHeadersRaw
    @Default(.watermarkText)          var watermarkText
    @Default(.watermarkPosition)      var watermarkPosition
    @Default(.watermarkFontSize)      var watermarkFontSize
    @Default(.watermarkOpacity)       var watermarkOpacity
    @Default(.watermarkColorHex)      var watermarkColorHex
    @Default(.watermarkBackground)    var watermarkBackground
    @Default(.borderWidth)            var borderWidth
    @Default(.borderColorHex)         var borderColorHex
    @Default(.borderOpacity)          var borderOpacity
    @Default(.borderShadow)           var borderShadow
    @Default(.borderShadowBlur)       var borderShadowBlur
    @Default(.sftpHost)               var sftpHost
    @Default(.sftpPort)               var sftpPort
    @Default(.sftpUsername)           var sftpUsername
    @Default(.sftpPassword)           var sftpPassword
    @Default(.sftpPrivateKeyPath)     var sftpPrivateKeyPath
    @Default(.sftpRemotePath)         var sftpRemotePath
    @Default(.sftpPublicURL)          var sftpPublicURL
    @Default(.uploadLinkFormat)       var uploadLinkFormat

    private let outputTasks: [AfterCaptureOption]    = [.copyToClipboard, .saveToFile,
                                                        .uploadToImgur, .uploadToS3, .uploadToSFTP,
                                                        .uploadCustomHTTP, .openUploadedURL]
    private let postSaveTasks: [AfterCaptureOption]  = [.revealInFinder, .copyFilePath, .openInViewer]
    private let notifyTasks: [AfterCaptureOption]    = [.showNotification]
    private let imageTasks: [AfterCaptureOption]     = [.ocr, .autoRedactPII, .watermark, .imageBorder, .print, .pinToScreen]

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

            Section("Image Actions") {
                ForEach(imageTasks, id: \.self) { opt in
                    PipelineRow(option: opt, options: $options)
                }
            }

            let hasAnyUpload = options.contains(.uploadToImgur) || options.contains(.uploadToS3)
                            || options.contains(.uploadToSFTP)  || options.contains(.uploadCustomHTTP)
            if hasAnyUpload {
                Section {
                    Picker("Link format", selection: $uploadLinkFormat) {
                        Text("Plain URL").tag("url")
                        Text("HTML  <img src=\"…\">").tag("html")
                        Text("Markdown  ![Screenshot](…)").tag("markdown")
                        Text("BBCode  [img]…[/img]").tag("bbcode")
                    }
                    Text("Controls what is placed on the clipboard after a successful upload.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Upload Link Format") }
            }

            if options.contains(.uploadToImgur) {
                Section {
                    HStack {
                        Text("Client ID")
                        TextField("your-imgur-client-id", text: $imgurClientID)
                            .textFieldStyle(.roundedBorder)
                    }
                    Link("Get a free Client ID →", destination: URL(string: "https://api.imgur.com/oauth2/addclient")!)
                        .font(.caption)
                } header: { Text("Imgur Settings") }
            }

            if options.contains(.uploadToSFTP) {
                Section {
                    LabeledContent("Host") {
                        TextField("sftp.example.com", text: $sftpHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Port") {
                        TextField("22", value: $sftpPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    LabeledContent("Username") {
                        TextField("user", text: $sftpUsername)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("Leave blank for key auth", text: $sftpPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Private key") {
                        HStack {
                            TextField("/Users/you/.ssh/id_rsa  (optional)", text: $sftpPrivateKeyPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
                                if panel.runModal() == .OK, let url = panel.url {
                                    sftpPrivateKeyPath = url.path
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    LabeledContent("Remote path") {
                        TextField("/var/www/screenshots/", text: $sftpRemotePath)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Public URL") {
                        TextField("https://cdn.example.com/screenshots/  (for the clipboard link)", text: $sftpPublicURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button("Test Connection") {
                            sftpTestState = .testing
                            let cfg = SFTPUploader.Config(
                                host: sftpHost, port: sftpPort, username: sftpUsername,
                                password: sftpPassword, privateKeyPath: sftpPrivateKeyPath,
                                remotePath: sftpRemotePath)
                            Task {
                                do {
                                    try await SFTPUploader(config: cfg).testConnection()
                                    sftpTestState = .success("Connected")
                                } catch {
                                    sftpTestState = .failure(error.localizedDescription)
                                }
                            }
                        }
                        .disabled(sftpHost.isEmpty || sftpUsername.isEmpty || sftpTestState == .testing)
                        ConnectionTestBadge(state: sftpTestState)
                    }
                    Text("Uploads via curl (requires the server's host key to be in ~/.ssh/known_hosts). Password or private key must be set.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("SFTP Settings") }
            }

            if options.contains(.uploadToS3) {
                Section {
                    LabeledContent("Bucket") {
                        TextField("my-screenshots", text: $s3Bucket)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Region") {
                        TextField("us-east-1", text: $s3Region)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Access Key ID") {
                        TextField("AKIA…", text: $s3AccessKeyID)
                            .textFieldStyle(.roundedBorder)
                            .fontDesign(.monospaced)
                    }
                    LabeledContent("Secret Access Key") {
                        SecureField("••••••••", text: $s3SecretAccessKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Key Prefix") {
                        TextField("screenshots/  (optional)", text: $s3KeyPrefix)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Public URL") {
                        TextField("https://cdn.example.com/  (optional)", text: $s3PublicURLTemplate)
                            .textFieldStyle(.roundedBorder)
                    }
                    Toggle("Path-style endpoint", isOn: $s3PathStyle)
                    HStack {
                        Button("Test Connection") {
                            s3TestState = .testing
                            let cfg = S3Uploader.Config(
                                bucket: s3Bucket, region: s3Region,
                                accessKeyID: s3AccessKeyID, secretAccessKey: s3SecretAccessKey,
                                keyPrefix: s3KeyPrefix, publicURLTemplate: s3PublicURLTemplate,
                                pathStyle: s3PathStyle)
                            Task {
                                do {
                                    try await S3Uploader(config: cfg).testConnection()
                                    s3TestState = .success("Connected")
                                } catch {
                                    s3TestState = .failure(error.localizedDescription)
                                }
                            }
                        }
                        .disabled(s3Bucket.isEmpty || s3AccessKeyID.isEmpty || s3TestState == .testing)
                        ConnectionTestBadge(state: s3TestState)
                    }
                    Text("Needs s3:PutObject permission. Leave Public URL blank to use the default S3 HTTPS URL.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Amazon S3 Settings") }
            }

            if options.contains(.uploadCustomHTTP) {
                Section {
                    HStack(spacing: 8) {
                        Picker("Method", selection: $customHTTPMethod) {
                            Text("POST").tag("POST")
                            Text("PUT").tag("PUT")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 100)
                        TextField("https://example.com/upload", text: $customHTTPURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("File field") {
                        TextField("file", text: $customHTTPFileField)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Response path") {
                        TextField("data.url  (empty = whole response)", text: $customHTTPResponsePath)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Headers  (one per line: \"Key: Value\")")
                            .font(.subheadline)
                        TextEditor(text: $customHTTPHeadersRaw)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 60, maxHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                    }
                    Text("Leave File field empty to send a raw PNG body instead of multipart form-data.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Custom HTTP Upload") }
            }

            if options.contains(.ocr) {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recognition Language")
                            .font(.subheadline)
                        let langs = OCRProcessor.supportedLanguages
                        Picker("Language", selection: Binding(
                            get: { ocrLanguages.first ?? "" },
                            set: { ocrLanguages = $0.isEmpty ? [] : [$0] }
                        )) {
                            Text("Auto-detect").tag("")
                            ForEach(langs, id: \.self) { lang in
                                Text(Locale.current.localizedString(forIdentifier: lang) ?? lang).tag(lang)
                            }
                        }
                    }
                } header: { Text("OCR Settings") }
            }

            if options.contains(.watermark) {
                Section {
                    LabeledContent("Text") {
                        TextField("%app% · %year%-%month%-%day%", text: $watermarkText)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Supports NameParser tokens: %year%, %month%, %day%, %hour%, %minute%, %app%, %width%, %height%, …")
                        .font(.caption).foregroundStyle(.secondary)

                    LabeledContent("Position") {
                        Picker("", selection: $watermarkPosition) {
                            Text("Top Left").tag("topLeft")
                            Text("Top Center").tag("topCenter")
                            Text("Top Right").tag("topRight")
                            Text("Middle Left").tag("middleLeft")
                            Text("Center").tag("center")
                            Text("Middle Right").tag("middleRight")
                            Text("Bottom Left").tag("bottomLeft")
                            Text("Bottom Center").tag("bottomCenter")
                            Text("Bottom Right").tag("bottomRight")
                        }
                        .labelsHidden()
                    }

                    LabeledContent("Font size") {
                        HStack {
                            Slider(value: $watermarkFontSize, in: 8...48, step: 1)
                                .frame(width: 140)
                            Text("\(Int(watermarkFontSize)) pt")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Opacity") {
                        HStack {
                            Slider(value: $watermarkOpacity, in: 0.1...1.0, step: 0.05)
                                .frame(width: 140)
                            Text("\(Int(watermarkOpacity * 100))%")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Colour") {
                        HStack(spacing: 8) {
                            // Hex text field — keeps the stored value as a plain string.
                            TextField("FFFFFF", text: $watermarkColorHex)
                                .textFieldStyle(.roundedBorder)
                                .fontDesign(.monospaced)
                                .frame(width: 80)
                            // Live preview swatch.
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: watermarkColorHex) ?? .white)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                        }
                    }

                    Toggle("Dark background pill", isOn: $watermarkBackground)
                } header: { Text("Watermark Settings") }
            }

            if options.contains(.imageBorder) {
                Section {
                    LabeledContent("Thickness") {
                        HStack {
                            Slider(value: $borderWidth, in: 1...40, step: 1)
                                .frame(width: 140)
                            Text("\(Int(borderWidth)) pt")
                                .frame(width: 44, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Colour") {
                        HStack(spacing: 8) {
                            TextField("000000", text: $borderColorHex)
                                .textFieldStyle(.roundedBorder)
                                .fontDesign(.monospaced)
                                .frame(width: 80)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: borderColorHex) ?? .black)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                        }
                    }

                    LabeledContent("Opacity") {
                        HStack {
                            Slider(value: $borderOpacity, in: 0.1...1.0, step: 0.05)
                                .frame(width: 140)
                            Text("\(Int(borderOpacity * 100))%")
                                .frame(width: 44, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Drop shadow", isOn: $borderShadow)

                    if borderShadow {
                        LabeledContent("Shadow blur") {
                            HStack {
                                Slider(value: $borderShadowBlur, in: 4...60, step: 2)
                                    .frame(width: 140)
                                Text("\(Int(borderShadowBlur)) px")
                                    .frame(width: 44, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Border / Shadow Settings") }
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
        return CarbonModifiers.symbol(modifiers) + key.displayName.uppercased()
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

// MARK: - Static Mask Tab

private struct StaticMaskTab: View {
    @Default(.staticMasks) var masks
    @State private var showAddSheet = false
    @State private var editingMask: MaskRegion? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Applied automatically to every capture.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("+ Add Rule") { showAddSheet = true }
            }
            .padding(10)

            Divider()

            if masks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No mask rules").foregroundStyle(.secondary)
                    Text("Add a rule to automatically blur or hide areas in every screenshot.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                List {
                    ForEach($masks) { $mask in
                        MaskRuleRow(mask: $mask) { editingMask = mask }
                    }
                    .onDelete { masks.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MaskRuleEditor(mask: nil) { newMask in
                masks.append(newMask)
                showAddSheet = false
            }
        }
        .sheet(item: $editingMask) { mask in
            MaskRuleEditor(mask: mask) { updated in
                if let idx = masks.firstIndex(where: { $0.id == updated.id }) {
                    masks[idx] = updated
                }
                editingMask = nil
            }
        }
    }
}

private struct MaskRuleRow: View {
    @Binding var mask: MaskRegion
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $mask.enabled).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(mask.name.isEmpty ? ruleDescription : mask.name)
                    .font(.callout)
                    .foregroundStyle(mask.enabled ? .primary : .secondary)
                Text(ruleDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(styleLabel).font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
            Button("Edit") { onEdit() }.font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var ruleDescription: String {
        switch mask.rule {
        case .rect(let r):
            return "Region \(Int(r.origin.x)),\(Int(r.origin.y))  \(Int(r.width))×\(Int(r.height))"
        case .appBundle(let id):
            return "App: \(id)"
        case .windowTitle(let s):
            return "Window contains \"\(s)\""
        }
    }

    private var styleLabel: String {
        switch mask.style {
        case .blur:       return "Blur"
        case .pixelate:   return "Pixelate"
        case .solidFill:  return "Fill"
        }
    }
}

private struct MaskRuleEditor: View {
    let mask: MaskRegion?
    let onSave: (MaskRegion) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum RuleType: String, CaseIterable {
        case rect       = "Fixed Region"
        case appBundle  = "App (bundle ID)"
        case windowTitle = "Window Title"
    }
    private enum StyleType: String, CaseIterable {
        case blur = "Blur"
        case pixelate = "Pixelate"
        case blackout = "Black Fill"
    }

    @State private var name: String
    @State private var ruleType: RuleType
    @State private var styleType: StyleType

    @State private var rectX: String
    @State private var rectY: String
    @State private var rectW: String
    @State private var rectH: String
    @State private var bundleID: String
    @State private var windowTitleContains: String
    @State private var blurRadius: Double
    @State private var pixelateSize: Double

    init(mask: MaskRegion?, onSave: @escaping (MaskRegion) -> Void) {
        self.mask = mask
        self.onSave = onSave

        let m = mask
        _name = State(initialValue: m?.name ?? "")
        switch m?.rule {
        case .rect(let r):
            _ruleType = State(initialValue: .rect)
            _rectX = State(initialValue: String(Int(r.minX)))
            _rectY = State(initialValue: String(Int(r.minY)))
            _rectW = State(initialValue: String(Int(r.width)))
            _rectH = State(initialValue: String(Int(r.height)))
            _bundleID = State(initialValue: "")
            _windowTitleContains = State(initialValue: "")
        case .appBundle(let id):
            _ruleType = State(initialValue: .appBundle)
            _rectX = State(initialValue: "0"); _rectY = State(initialValue: "0")
            _rectW = State(initialValue: "400"); _rectH = State(initialValue: "300")
            _bundleID = State(initialValue: id)
            _windowTitleContains = State(initialValue: "")
        case .windowTitle(let s):
            _ruleType = State(initialValue: .windowTitle)
            _rectX = State(initialValue: "0"); _rectY = State(initialValue: "0")
            _rectW = State(initialValue: "400"); _rectH = State(initialValue: "300")
            _bundleID = State(initialValue: "")
            _windowTitleContains = State(initialValue: s)
        case nil:
            _ruleType = State(initialValue: .rect)
            _rectX = State(initialValue: "0"); _rectY = State(initialValue: "0")
            _rectW = State(initialValue: "400"); _rectH = State(initialValue: "300")
            _bundleID = State(initialValue: ""); _windowTitleContains = State(initialValue: "")
        }
        switch m?.style {
        case .blur(let r):    _styleType = State(initialValue: .blur);     _blurRadius = State(initialValue: r); _pixelateSize = State(initialValue: 12)
        case .pixelate(let s): _styleType = State(initialValue: .pixelate); _blurRadius = State(initialValue: 20); _pixelateSize = State(initialValue: s)
        case .solidFill:      _styleType = State(initialValue: .blackout); _blurRadius = State(initialValue: 20); _pixelateSize = State(initialValue: 12)
        case nil:             _styleType = State(initialValue: .blur);     _blurRadius = State(initialValue: 20); _pixelateSize = State(initialValue: 12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mask == nil ? "Add Mask Rule" : "Edit Mask Rule")
                .font(.title3).bold().padding()

            Divider()

            Form {
                Section("Name") {
                    TextField("Optional label", text: $name)
                }

                Section("Match") {
                    Picker("Type", selection: $ruleType) {
                        ForEach(RuleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch ruleType {
                    case .rect:
                        HStack(spacing: 8) {
                            Group {
                                LabeledContent("X") { TextField("0", text: $rectX).frame(width: 60) }
                                LabeledContent("Y") { TextField("0", text: $rectY).frame(width: 60) }
                                LabeledContent("W") { TextField("400", text: $rectW).frame(width: 60) }
                                LabeledContent("H") { TextField("300", text: $rectH).frame(width: 60) }
                            }
                        }
                        Text("Screen coordinates (points, top-left origin). You can capture a region first to see its coordinates.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .appBundle:
                        TextField("com.apple.Terminal", text: $bundleID)
                        Text("Masks every window of this app. Find the bundle ID with: osascript -e 'id of app \"AppName\"'")
                            .font(.caption).foregroundStyle(.secondary)
                    case .windowTitle:
                        TextField("Substring to match (case-insensitive)", text: $windowTitleContains)
                        Text("Masks any on-screen window whose title contains this text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Effect") {
                    Picker("Style", selection: $styleType) {
                        ForEach(StyleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if styleType == .blur {
                        LabeledContent("Radius") {
                            HStack {
                                Slider(value: $blurRadius, in: 5...80, step: 5).frame(width: 120)
                                Text("\(Int(blurRadius)) px").frame(width: 44).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if styleType == .pixelate {
                        LabeledContent("Block size") {
                            HStack {
                                Slider(value: $pixelateSize, in: 4...40, step: 2).frame(width: 120)
                                Text("\(Int(pixelateSize)) px").frame(width: 44).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 480, height: 460)
    }

    private var canSave: Bool {
        switch ruleType {
        case .rect:        return (Double(rectW) ?? 0) > 0 && (Double(rectH) ?? 0) > 0
        case .appBundle:   return !bundleID.trimmingCharacters(in: .whitespaces).isEmpty
        case .windowTitle: return !windowTitleContains.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        let rule: MaskRule
        switch ruleType {
        case .rect:
            let r = CGRect(x: Double(rectX) ?? 0, y: Double(rectY) ?? 0,
                           width: Double(rectW) ?? 400, height: Double(rectH) ?? 300)
            rule = .rect(r)
        case .appBundle:
            rule = .appBundle(bundleID: bundleID.trimmingCharacters(in: .whitespaces))
        case .windowTitle:
            rule = .windowTitle(contains: windowTitleContains.trimmingCharacters(in: .whitespaces))
        }

        let style: MaskStyle
        switch styleType {
        case .blur:     style = .blur(radius: blurRadius)
        case .pixelate: style = .pixelate(blockSize: pixelateSize)
        case .blackout: style = .solidFill(red: 0, green: 0, blue: 0)
        }

        let result = MaskRegion(id: mask?.id ?? UUID(), name: name, rule: rule, style: style)
        onSave(result)
    }
}

// MARK: - Workflows Tab

private struct WorkflowsTab: View {
    @Default(.workflowProfiles) var profiles

    @State private var showAdd = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow profiles bind a hotkey to a complete capture + output sequence.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("+ Add") { showAdd = true }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            if showAdd {
                HStack {
                    TextField("Profile name", text: $newName)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                    Button("Create") {
                        guard !newName.isEmpty else { return }
                        profiles.append(StoredWorkflowProfile(name: newName))
                        newName = ""; showAdd = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty)
                    Button("Cancel") { showAdd = false; newName = "" }
                }
                .padding(.horizontal, 14).padding(.bottom, 6)
                Divider()
            }

            if profiles.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "flowchart").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.tertiary)
                    Text("No workflow profiles").foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(profiles) { profile in
                        WorkflowRow(profile: profile, profiles: $profiles)
                    }
                    .onDelete { idx in profiles.remove(atOffsets: idx) }
                }
                .listStyle(.plain)
            }
        }
        .padding()
    }
}

private struct WorkflowRow: View {
    let profile: StoredWorkflowProfile
    @Binding var profiles: [StoredWorkflowProfile]

    @State private var isRecording = false

    private var idx: Int? { profiles.firstIndex(where: { $0.id == profile.id }) }

    private var hotkeyLabel: String {
        guard profile.keyCode > 0,
              let key = Key(carbonKeyCode: profile.keyCode) else { return "–" }
        return CarbonModifiers.symbol(profile.modifiers) + key.displayName.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Row 1: name  ·  enable  ·  delete ──
            HStack(spacing: 8) {
                if let i = idx {
                    TextField("Profile name", text: Binding(
                        get: { profiles[i].name },
                        set: { profiles[i].name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                Spacer()
                if let i = idx {
                    Toggle("", isOn: Binding(
                        get: { profiles[i].enabled },
                        set: { profiles[i].enabled = $0 }
                    ))
                    .labelsHidden()
                }
                Button(role: .destructive) {
                    profiles.removeAll { $0.id == profile.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            // ── Row 2: capture mode  ·  hotkey recorder ──
            HStack(spacing: 10) {
                Text("Mode:")
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                if let i = idx {
                    Picker("", selection: Binding(
                        get: { profiles[i].captureMode },
                        set: { profiles[i].captureMode = $0 }
                    )) {
                        Text("Region").tag("region")
                        Text("Window").tag("window")
                        Text("Full Screen").tag("fullScreen")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                Text("Hotkey:")
                    .foregroundStyle(.secondary)

                if let i = idx {
                    HotkeyRecorderView(
                        keyCode: Binding(
                            get: { profiles[i].keyCode },
                            set: { profiles[i].keyCode = $0 }
                        ),
                        modifiers: Binding(
                            get: { profiles[i].modifiers },
                            set: { profiles[i].modifiers = $0 }
                        ),
                        isRecording: $isRecording,
                        displayString: hotkeyLabel
                    )
                    .frame(width: 120, height: 24)
                }

                Spacer()
            }

            // ── Row 3: output destinations ──
            if let i = idx {
                HStack(spacing: 10) {
                    Text("Output:")
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)

                    ForEach(WorkflowOutputDestination.allCases, id: \.rawValue) { dest in
                        let selected = profiles[i].outputDestinations.contains(dest.rawValue)
                        Button {
                            if selected {
                                profiles[i].outputDestinations.removeAll { $0 == dest.rawValue }
                            } else {
                                profiles[i].outputDestinations.append(dest.rawValue)
                            }
                        } label: {
                            Label(dest.label, systemImage: dest.icon)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - WorkflowOutputDestination

/// Available per-workflow output destinations.
/// The raw values match StoredWorkflowProfile.outputDestinations strings.
private enum WorkflowOutputDestination: String, CaseIterable {
    case clipboard  = "clipboard"
    case localFile  = "localFile"
    case imgur      = "imgur"
    case s3         = "s3"
    case sftp       = "sftp"
    case customHTTP = "customHTTP"

    var label: String {
        switch self {
        case .clipboard:  return "Clipboard"
        case .localFile:  return "File"
        case .imgur:      return "Imgur"
        case .s3:         return "S3"
        case .sftp:       return "SFTP"
        case .customHTTP: return "HTTP"
        }
    }

    var icon: String {
        switch self {
        case .clipboard:  return "doc.on.clipboard"
        case .localFile:  return "folder"
        case .imgur:      return "photo.on.rectangle"
        case .s3:         return "externaldrive.connected.to.line.below"
        case .sftp:       return "terminal"
        case .customHTTP: return "network"
        }
    }
}

// MARK: - Key description

// MARK: - SwiftUI Color hex helper

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// MARK: - ConnectionTestState

private enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

private struct ConnectionTestBadge: View {
    let state: ConnectionTestState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption).lineLimit(2)
        }
    }
}

// MARK: - Key display label

extension Key {
    /// Human-readable label for display in the hotkey UI.
    /// Uses a dedicated property to avoid conflicting with HotKey's own
    /// `CustomStringConvertible` conformance.
    var displayName: String {
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
