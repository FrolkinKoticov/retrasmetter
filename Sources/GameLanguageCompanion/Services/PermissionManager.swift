import AppKit
import CoreGraphics

/// Tracks the Screen Recording permission that ScreenCaptureKit requires.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasScreenRecordingAccess: Bool = CGPreflightScreenCaptureAccess()
    private var observer: NSObjectProtocol?

    init() {
        // The user usually grants access in System Settings and then switches back to us.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        hasScreenRecordingAccess = CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt (only shows the first time; afterwards use System Settings).
    @discardableResult
    func requestAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecordingAccess = granted
        return granted
    }

    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    var explanation: String {
        tr("Screen Recording permission is missing. Retrasmetter only captures the subtitle area you selected, only when you press the hotkey, and never saves screenshots. Open System Settings → Privacy & Security → Screen & System Audio Recording, enable this app, then quit and reopen it (macOS applies the change after a relaunch).")
    }
}
