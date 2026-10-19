import AppKit
import SwiftUI

/// Opens regular windows (main window, onboarding) from a menu-bar app.
/// Plain AppKit windows are used instead of SwiftUI `Window` scenes because scenes may open
/// automatically at launch, and this app should start silently in the menu bar.
@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]

    func close(id: String) {
        windows[id]?.close()
    }

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            existing.title = title                      // the interface language may have changed
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
