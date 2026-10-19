import AppKit

/// Figures out which game the dialogue belongs to, so vocabulary can be tagged with its source.
@MainActor
final class GameContextManager {
    private let settings: AppSettings
    private var lastForeignApp: String?
    private var observer: NSObjectProtocol?

    init(settings: AppSettings) {
        self.settings = settings
        lastForeignApp = NSWorkspace.shared.frontmostApplication.flatMap { Self.name(of: $0) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                if let name = Self.name(of: app) { self?.lastForeignApp = name }
            }
        }
    }

    /// Manual override wins; otherwise the last non-self frontmost app (the hotkey does not
    /// activate us, so this is normally the game).
    func currentGameName() -> String? {
        let override = settings.gameNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return lastForeignApp
    }

    private static func name(of app: NSRunningApplication) -> String? {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.localizedName
    }
}
