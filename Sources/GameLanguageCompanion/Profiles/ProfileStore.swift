import Foundation
import AppKit
import CoreGraphics

/// Game profiles (JSON in UserDefaults — nothing sensitive in here) and the active one.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [GameProfile] = []
    @Published private(set) var activeProfileID: UUID?

    private let settings: AppSettings
    private let profilesKey = "gameProfiles"
    private let activeKey = "activeGameProfileID"

    init(settings: AppSettings) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([GameProfile].self, from: data) {
            profiles = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    var activeProfile: GameProfile? { profiles.first { $0.id == activeProfileID } }

    // MARK: Editing

    /// Older versions had one global capture area; turn it into a first profile.
    func migrateIfNeeded(gameName: String?) {
        guard profiles.isEmpty, let region = settings.captureRegion else { return }
        var profile = GameProfile(name: gameName ?? "My Game",
                                  sourceLanguageCode: settings.sourceLanguage.code,
                                  targetLanguageCode: settings.targetLanguage.code)
        profile.region = region
        profiles = [profile]
        activeProfileID = profile.id
        save()
    }

    @discardableResult
    func createProfile(name: String, window: GameWindowInfo? = nil) -> GameProfile {
        var profile = GameProfile(name: name, sourceLanguageCode: settings.sourceLanguage.code,
                                  targetLanguageCode: settings.targetLanguage.code)
        apply(window: window, to: &profile)
        profiles.append(profile)
        activate(profile.id)
        save()
        return profile
    }

    func update(_ profile: GameProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        if profile.id == activeProfileID { applyToSettings(profile) }
        save()
    }

    func attach(window: GameWindowInfo, to id: UUID) {
        guard var profile = profiles.first(where: { $0.id == id }) else { return }
        apply(window: window, to: &profile)
        // The dialogue area was chosen for another window (or none): ask again.
        profile.relativeRegion = nil
        update(profile)
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
            if let profile = activeProfile { applyToSettings(profile) } else { settings.captureRegion = nil }
        }
        save()
    }

    func activate(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        applyToSettings(profile)
        save()
    }

    /// Stores a freshly selected dialogue area in the active profile (creating one if needed).
    func saveRegion(_ region: CaptureRegion, windows: [GameWindowInfo], fallbackName: String?) {
        if activeProfile == nil { createProfile(name: fallbackName ?? "My Game") }
        guard var profile = activeProfile else { return }
        profile.region = region

        // Window-relative copy, so the area follows the window when it moves.
        if let window = WindowCatalog.find(for: profile, in: windows) {
            let display = CGDisplayBounds(region.displayID)
            let globalX = display.minX + region.x
            let globalY = display.minY + region.y
            profile.relativeRegion = RelativeRegion(
                dx: globalX - window.frame.minX, dy: globalY - window.frame.minY,
                width: region.width, height: region.height)
        } else {
            profile.relativeRegion = nil
        }
        settings.captureRegion = region
        update(profile)
    }

    // MARK: Resolving

    /// The dialogue area to monitor right now: window-relative when the window is visible,
    /// otherwise the stored absolute area. Also keeps `settings.captureRegion` in sync.
    func resolvedRegion() async -> CaptureRegion? {
        guard let profile = activeProfile else { return settings.captureRegion }
        var result = profile.region ?? settings.captureRegion

        if let relative = profile.relativeRegion,
           let windows = try? await WindowCatalog.visibleWindows(),
           let window = WindowCatalog.find(for: profile, in: windows) {
            let globalPoint = CGPoint(x: window.frame.minX + relative.dx, y: window.frame.minY + relative.dy)
            if let display = WindowCatalog.display(containing: globalPoint) {
                let rect = CGRect(x: globalPoint.x - display.bounds.minX, y: globalPoint.y - display.bounds.minY,
                                  width: relative.width, height: relative.height)
                result = CaptureRegion(displayID: display.id, rect: rect)
            }
        }
        if let result, settings.captureRegion != result { settings.captureRegion = result }
        return result
    }

    /// When the active profile has a game window and a window-relative area, capture that window
    /// directly: its own pixels are returned even if another window covers it or sits behind it.
    func windowTarget() async -> WindowCaptureTarget? {
        guard let profile = activeProfile, let relative = profile.relativeRegion,
              let windows = try? await WindowCatalog.visibleWindows(),
              let window = WindowCatalog.find(for: profile, in: windows) else { return nil }
        return WindowCaptureTarget(windowID: window.id,
                                   rect: CGRect(x: relative.dx, y: relative.dy, width: relative.width, height: relative.height))
    }

    // MARK: Helpers

    private func apply(window: GameWindowInfo?, to profile: inout GameProfile) {
        guard let window else { return }
        profile.windowOwner = window.appName
        profile.windowBundleID = window.bundleID
        profile.windowTitle = window.title
        profile.windowID = window.id
        if profile.name.isEmpty || profile.name == "New Game" { profile.name = window.appName }
    }

    private func applyToSettings(_ profile: GameProfile) {
        settings.sourceLanguage = Language(code: profile.sourceLanguageCode)
        settings.targetLanguage = Language(code: profile.targetLanguageCode)
        settings.gameNameOverride = profile.name
        settings.captureRegion = profile.region
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: profilesKey) }
        if let id = activeProfileID { UserDefaults.standard.set(id.uuidString, forKey: activeKey) }
        else { UserDefaults.standard.removeObject(forKey: activeKey) }
    }
}
