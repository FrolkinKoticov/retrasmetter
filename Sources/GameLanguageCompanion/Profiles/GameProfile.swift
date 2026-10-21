import Foundation
import AppKit
import ScreenCaptureKit

/// Dialogue area relative to the game window's top-left corner, so it follows the window.
struct RelativeRegion: Codable, Equatable, Sendable {
    var dx: Double
    var dy: Double
    var width: Double
    var height: Double
}

/// Per-game settings: which window, where the dialogue is, languages, monitoring.
struct GameProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var windowOwner: String?
    var windowBundleID: String?
    var windowTitle: String?
    var windowID: UInt32?
    /// Absolute area (display-local points); used when the window cannot be found.
    var region: CaptureRegion?
    /// Area relative to the window; preferred whenever the window is found.
    var relativeRegion: RelativeRegion?
    var sourceLanguageCode: String
    var targetLanguageCode: String
    var monitoringEnabled = true

    var windowDescription: String? {
        guard let owner = windowOwner else { return nil }
        if let title = windowTitle, !title.isEmpty, title != owner { return "\(owner) — \(title)" }
        return owner
    }
}

/// Capture the game window itself; `rect` is the dialogue area in window-local points (top-left origin).
struct WindowCaptureTarget: Equatable, Sendable {
    let windowID: UInt32
    let rect: CGRect
}

/// A visible window the user can pick as "the game".
struct GameWindowInfo: Identifiable, Hashable, Sendable {
    let id: UInt32
    let appName: String
    let bundleID: String?
    let title: String
    /// Quartz global coordinates (top-left origin).
    let frame: CGRect

    var displayName: String { title.isEmpty || title == appName ? appName : "\(appName) — \(title)" }
}

enum WindowCatalog {
    /// Normal, reasonably large, on-screen windows of other apps.
    static func visibleWindows() async throws -> [GameWindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { window -> GameWindowInfo? in
            guard window.windowLayer == 0, window.frame.width >= 240, window.frame.height >= 160,
                  let app = window.owningApplication, app.processID != ownPID,
                  !app.applicationName.isEmpty else { return nil }
            return GameWindowInfo(id: window.windowID, appName: app.applicationName,
                                  bundleID: app.bundleIdentifier, title: window.title ?? "", frame: window.frame)
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    /// Finds the profile's window: same window id first, then same app (and title when possible).
    static func find(for profile: GameProfile, in windows: [GameWindowInfo]) -> GameWindowInfo? {
        if let id = profile.windowID, let exact = windows.first(where: { $0.id == id }) { return exact }
        let sameApp = windows.filter {
            (profile.windowBundleID != nil && $0.bundleID == profile.windowBundleID)
            || (profile.windowOwner != nil && $0.appName == profile.windowOwner)
        }
        if let title = profile.windowTitle, let match = sameApp.first(where: { $0.title == title }) { return match }
        return sameApp.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// The display (CoreGraphics id) containing a point given in Quartz global coordinates.
    @MainActor
    static func display(containing point: CGPoint) -> (id: UInt32, bounds: CGRect)? {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let bounds = CGDisplayBounds(id)
            if bounds.contains(point) { return (id, bounds) }
        }
        return nil
    }
}
