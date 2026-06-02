import SwiftUI
import AppKit
import ReticleCapture

// MARK: - Window controller

/// Shows the onboarding window exactly once — on first launch after install.
/// Controlled via a single Defaults flag so it never reappears.
@MainActor
final class OnboardingWindowController: NSWindowController {

    static let shared = OnboardingWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Reticle"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView {
            window.close()
        })
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Show only if this is the first launch (no screenshots directory created yet).
    func showIfNeeded() {
        let key = "onboardingCompleted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}

// MARK: - SwiftUI content

private struct OnboardingView: View {
    let onDone: () -> Void
    @State private var step = 0
    @State private var screenRecordingGranted = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accent : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 28)

            Spacer()

            // Page content
            Group {
                switch step {
                case 0: WelcomePage()
                case 1: PermissionPage(granted: $screenRecordingGranted)
                default: ShortcutPage()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.25), value: step)

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(step < 2 ? "Continue" : "Get Started") {
                    if step < 2 { step += 1 } else { onDone() }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(step == 1 && !screenRecordingGranted)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Poll permission state so the button enables automatically
            // when the user grants access in System Settings.
            checkTask = Task {
                while !Task.isCancelled {
                    screenRecordingGranted = await PermissionChecker.hasPermission()
                    if screenRecordingGranted { break }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        .onDisappear { checkTask?.cancel() }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 20) {
            // Spider logo
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.067, green: 0.067, blue: 0.078))
                    .frame(width: 88, height: 88)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

            VStack(spacing: 8) {
                Text("Welcome to Reticle")
                    .font(.title).bold()
                Text("The free, open-source screenshot tool for macOS.\nLives in your menu bar — always one shortcut away.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Quick feature list
            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "rectangle.dashed", text: "Region capture with freeze & annotate")
                FeatureRow(icon: "pencil.tip",        text: "21 annotation tools, ShareX-style")
                FeatureRow(icon: "arrow.up.to.line",  text: "Upload to Imgur, S3, SFTP & more")
                FeatureRow(icon: "video",             text: "Screen recording — MP4 & GIF")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 48)
    }
}

private struct PermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: granted ? "checkmark.shield.fill" : "shield")
                .font(.system(size: 52))
                .foregroundStyle(granted ? .green : Color.accent)
                .animation(.easeInOut, value: granted)

            VStack(spacing: 8) {
                Text("Screen Recording")
                    .font(.title2).bold()
                Text(granted
                     ? "Permission granted. You're all set."
                     : "Reticle needs Screen Recording access to capture your screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !granted {
                VStack(spacing: 10) {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(AccentButtonStyle())

                    Text("After granting access, come back here — this page updates automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 48)
    }
}

private struct ShortcutPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundStyle(Color.accent)

            VStack(spacing: 8) {
                Text("Your shortcut")
                    .font(.title2).bold()
                Text("Press this from any app to start a region capture.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Keyboard shortcut display
            HStack(spacing: 6) {
                ForEach(["⌘", "⇧", "2"], id: \.self) { key in
                    Text(key)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .frame(width: 46, height: 46)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
            }

            Text("You can change this anytime in Settings → Hotkeys.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Helpers

private struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .cornerRadius(8)
    }
}

private extension Color {
    static let accent = Color(red: 0.91, green: 0.267, blue: 0.165)
}
