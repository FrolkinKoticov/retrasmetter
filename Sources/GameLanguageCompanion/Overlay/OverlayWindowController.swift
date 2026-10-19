import AppKit
import SwiftUI
import Combine

/// A floating panel that can be clicked without ever activating the app, so the game
/// keeps keyboard focus. It only becomes key if a clicked control needs it (none do).
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Makes the very first click on the non-key panel act on the control instead of being swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayWindowController {
    let viewModel: OverlayViewModel
    private let settings: AppSettings

    private var panel: OverlayPanel?
    private var hosting: FirstMouseHostingView<OverlayRootView>?
    private var hideTask: Task<Void, Never>?
    private var moveObserver: NSObjectProtocol?
    /// true → panel's bottom edge is the anchor (it grows upward); false → its top edge is.
    private var anchoredAbove = true
    /// Set while the app itself moves the panel, so only *user drags* are remembered.
    private var isApplyingFrame = false
    private var cancellables = Set<AnyCancellable>()

    private enum ScreenSlot { case top, center, bottom }

    init(settings: AppSettings, viewModel: OverlayViewModel) {
        self.settings = settings
        self.viewModel = viewModel
        viewModel.onClose = { [weak self] in self?.hide() }
        // The content height changes with state/selection; re-fit after SwiftUI has laid out.
        viewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.resizePanel() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Presenting

    /// `autoHide` overrides the normal auto-hide delay (used by the position preview).
    func present(_ state: OverlayViewModel.State, near region: CaptureRegion?, autoHide: Double? = nil) {
        viewModel.setState(state)
        ensurePanel()
        guard let panel else { return }

        applyPlacement(region: region)
        panel.orderFrontRegardless()      // never makeKey / activate
        resizePanel()
        scheduleAutoHide(for: state, override: autoHide)
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
        viewModel.setState(.hidden)
    }

    // MARK: Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: settings.overlayWidth, height: 140),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true     // drag the overlay anywhere
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = FirstMouseHostingView(rootView: OverlayRootView(viewModel: viewModel, settings: settings))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidMove() }
        }
    }

    private func fittingSize() -> NSSize {
        guard let hosting else { return NSSize(width: settings.overlayWidth, height: 140) }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        return NSSize(width: max(size.width, 200), height: max(size.height, 60))
    }

    private func setFrame(_ frame: NSRect) {
        isApplyingFrame = true
        panel?.setFrame(frame, display: true)
        isApplyingFrame = false
    }

    /// Dragging the overlay by hand switches to "Where I last dragged it" and remembers the spot.
    private func panelDidMove() {
        guard !isApplyingFrame, let panel, panel.isVisible,
              NSEvent.pressedMouseButtons & 1 != 0,          // only while the user is dragging
              let screen = panel.screen, let displayID = screen.displayID else { return }
        let position = OverlayCustomPosition(
            displayID: displayID,
            x: panel.frame.minX - screen.frame.minX,
            top: screen.frame.maxY - panel.frame.maxY)
        if settings.overlayCustomPosition != position { settings.overlayCustomPosition = position }
        if settings.overlayPlacement != .custom { settings.overlayPlacement = .custom }
        anchoredAbove = false
    }

    // MARK: Placement

    private func screen(for region: CaptureRegion?) -> NSScreen {
        if let region, let match = NSScreen.screens.first(where: { $0.displayID == region.displayID }) { return match }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func applyPlacement(region: CaptureRegion?) {
        let size = fittingSize()
        switch settings.overlayPlacement {
        case .custom:
            if let position = settings.overlayCustomPosition, placeCustom(position, size: size) { return }
            placeNearRegion(region, size: size, preferAbove: true)
        case .aboveRegion:
            placeNearRegion(region, size: size, preferAbove: true)
        case .belowRegion:
            placeNearRegion(region, size: size, preferAbove: false)
        case .screenTop:
            placeOnScreen(screen(for: region), slot: .top, size: size)
        case .screenCenter:
            placeOnScreen(screen(for: region), slot: .center, size: size)
        case .screenBottom:
            placeOnScreen(screen(for: region), slot: .bottom, size: size)
        }
    }

    private func placeNearRegion(_ region: CaptureRegion?, size: NSSize, preferAbove: Bool) {
        guard let region else {
            placeOnScreen(screen(for: nil), slot: .bottom, size: size)
            return
        }
        let frame = screen(for: region).frame
        // Region is display-local with a top-left origin; convert to Cocoa's bottom-left global space.
        let regionRect = CGRect(x: frame.minX + region.x, y: frame.maxY - region.y - region.height,
                                width: region.width, height: region.height)
        let gap: CGFloat = 12
        let x = min(max(regionRect.midX - size.width / 2, frame.minX + 12), frame.maxX - size.width - 12)

        let aboveY = regionRect.maxY + gap
        let belowY = regionRect.minY - gap - size.height
        let fitsAbove = aboveY + size.height <= frame.maxY - 12
        let fitsBelow = belowY >= frame.minY + 12
        let useAbove = preferAbove ? (fitsAbove || !fitsBelow) : !fitsBelow

        anchoredAbove = useAbove
        setFrame(NSRect(x: x, y: useAbove ? aboveY : belowY, width: size.width, height: size.height))
    }

    private func placeOnScreen(_ screen: NSScreen, slot: ScreenSlot, size: NSSize) {
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y: CGFloat
        switch slot {
        case .top:
            y = visible.maxY - size.height - 40
            anchoredAbove = false
        case .center:
            y = visible.midY - size.height / 2
            anchoredAbove = false
        case .bottom:
            y = visible.minY + 60
            anchoredAbove = true
        }
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height))
    }

    private func placeCustom(_ position: OverlayCustomPosition, size: NSSize) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == position.displayID }) else { return false }
        let frame = screen.frame
        let x = min(max(frame.minX + position.x, frame.minX), frame.maxX - size.width)
        let top = min(max(frame.maxY - position.top, frame.minY + size.height), frame.maxY)
        anchoredAbove = false                      // top-left stays fixed; the panel grows downward
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height))
        return true
    }

    private func resizePanel() {
        guard let panel, panel.isVisible else { return }
        let size = fittingSize()
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        let deltaHeight = size.height - frame.height
        frame.size = size
        if !anchoredAbove { frame.origin.y -= deltaHeight }     // keep the top edge fixed
        setFrame(frame)
    }

    // MARK: Auto-hide

    private func scheduleAutoHide(for state: OverlayViewModel.State, override: Double?) {
        hideTask?.cancel()
        let seconds: Double
        switch state {
        case .hidden, .working: return
        case .info: seconds = override ?? 2.5
        case .error: seconds = override ?? 8
        case .result: seconds = override ?? settings.overlayAutoHideSeconds
        }
        guard seconds > 0 else { return }

        hideTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                // Don't vanish while the user is hovering over it or reading a word card.
                if self.viewModel.isHovering || self.viewModel.selectedKey != nil { remaining = seconds; continue }
                remaining -= 0.5
            }
            self?.hide()
        }
    }
}
