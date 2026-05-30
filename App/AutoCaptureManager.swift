import AppKit
import Defaults
import ReticleCore

/// Timer-based repeated capture. Fires `captureAction` every `autoCaptureInterval` seconds.
@MainActor
final class AutoCaptureManager: ObservableObject {
    static let shared = AutoCaptureManager()
    private init() {}

    @Published private(set) var isRunning = false
    var captureAction: ((AutoCaptureMode) -> Void)?

    private var timer: Timer?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Defaults[.autoCaptureEnabled] = true
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        Defaults[.autoCaptureEnabled] = false
    }

    func toggle() { isRunning ? stop() : start() }

    // MARK: -

    private func schedule() {
        let interval = max(1.0, Double(Defaults[.autoCaptureInterval]))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { [weak self] in await self?.fire() }
        }
    }

    private func fire() {
        guard isRunning else { return }
        captureAction?(Defaults[.autoCaptureMode])
        if isRunning { schedule() }
    }
}
