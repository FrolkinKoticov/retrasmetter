import SwiftUI
import AppKit

@main
struct GameLanguageCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        // Compact popover from the menu bar. The real windows (onboarding, main) are opened by
        // AppState/WindowManager so the app starts predictably and never as an empty menu-bar item.
        MenuBarExtra("Retrasmetter", systemImage: "text.bubble", isInserted: $showMenuBarIcon) {
            MenuPopoverView(appState: appState, settings: appState.settings,
                            status: appState.status, permissions: appState.permissions,
                            monitor: appState.monitor, reading: appState.reading)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon (also set via LSUIElement in Info.plist for the .app build);
        // the menu bar icon and the windows below are the entry points.
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in AppState.shared.start() }
    }

    /// Clicking the app icon in Finder/Launchpad again brings the window back,
    /// which matters when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in AppState.shared.showStartupWindow() }
        return true
    }
}
