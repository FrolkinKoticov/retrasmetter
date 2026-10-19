import AppKit
import SwiftUI

/// Borderless window that can become key (so Esc works) and sits above everything.
final class SelectionWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// Shows one dimming window per screen; the first completed drag wins.
@MainActor
final class RegionSelectionController {
    private var windows: [SelectionWindow] = []
    private var completion: ((CaptureRegion?) -> Void)?

    var isSelecting: Bool { !windows.isEmpty }

    func beginSelection(completion: @escaping (CaptureRegion?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let window = SelectionWindow(
                contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.setFrame(screen.frame, display: true)   // explicit: init(screen:) treats the rect as screen-relative
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.onEscape = { [weak self] in self?.finish(nil) }
            window.contentView = NSHostingView(rootView: RegionSelectionView(
                onSelect: { [weak self] rect in self?.finish(CaptureRegion(displayID: displayID, rect: rect)) },
                onCancel: { [weak self] in self?.finish(nil) }
            ))
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ region: CaptureRegion?) {
        guard !windows.isEmpty else { return }
        NSCursor.pop()
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        let completion = self.completion
        self.completion = nil
        completion?(region)
    }
}
