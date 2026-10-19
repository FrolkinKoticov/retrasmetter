import AppKit
import SwiftUI
import Combine

/// Reading Mode: a transparent layer over the dialogue area where words can be clicked.
/// Toggled with the hotkey (default ⌥Q); a second press or Esc leaves it.
@MainActor
final class ReadingModeController: ObservableObject {
    @Published private(set) var isActive = false

    /// Enables/disables the Escape hotkey (installed by AppState).
    var setEscapeHotkey: ((Bool) -> Void)?

    private let monitor: DialogueMonitor
    private let settings: AppSettings
    private let overlay: OverlayWindowController
    private let model = ReadingModel()
    private let popup: SelectionPopupController
    private var panel: ReadingPanel?
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitor: Any?

    init(monitor: DialogueMonitor, settings: AppSettings, overlay: OverlayWindowController,
         popupModel: SelectionPopupModel) {
        self.monitor = monitor
        self.settings = settings
        self.overlay = overlay
        self.popup = SelectionPopupController(model: popupModel, settings: settings)
    }

    func toggle() {
        if isActive { exit() } else { Task { await activate() } }
    }

    func activate() async {
        guard !isActive else { return }
        if monitor.dialogue == nil { await monitor.refreshNow() }
        guard let dialogue = monitor.dialogue, !dialogue.words.isEmpty else {
            overlay.present(.info(tr("No dialogue found. Check the dialogue area in Games.")),
                            near: settings.captureRegion, autoHide: 4)
            return
        }
        isActive = true
        model.dialogue = dialogue
        model.selection = nil
        model.hoveredIndex = nil
        showPanel(for: dialogue.regionFrame)
        setEscapeHotkey?(true)
        installMouseMonitor()

        // New dialogue while reading → refresh words and drop the old selection.
        monitor.$dialogue
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in
                MainActor.assumeIsolated {
                    guard let self, self.isActive else { return }
                    self.popup.close()
                    self.model.selection = nil
                    self.model.dialogue = new
                    if let new { self.showPanel(for: new.regionFrame) }
                }
            }
            .store(in: &cancellables)
    }

    func exit() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        popup.close()
        panel?.orderOut(nil)
        model.dialogue = nil
        model.selection = nil
        setEscapeHotkey?(false)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    /// Esc: first closes the popup if it is open, then leaves Reading Mode.
    func escapePressed() {
        if popup.isVisible {
            popup.close()
            model.selection = nil
        } else {
            exit()
        }
    }

    // MARK: Panel

    private func showPanel(for frame: CGRect) {
        let rect = frame.insetBy(dx: -6, dy: -6)
        if panel == nil {
            let panel = ReadingPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = ReadingOverlayView(model: model) { [weak self] range in self?.didSelect(range) }
            panel.contentView = FirstMouseHostingView(rootView: view)
            self.panel = panel
        }
        panel?.setFrame(rect, display: true)
        model.panelFrame = rect
        panel?.orderFrontRegardless()
    }

    private func didSelect(_ range: ClosedRange<Int>) {
        guard let dialogue = model.dialogue else { return }
        let text = dialogue.text(in: range)
        guard !text.isEmpty else { model.selection = nil; return }
        popup.model.select(text: text, context: dialogue.fullText, game: dialogue.sourceGame, speaker: dialogue.speaker)
        popup.show(near: dialogue.frame(of: range))
    }

    /// Clicks outside our windows (global monitors never see clicks inside them) close the popup.
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if self.popup.isVisible { self.popup.close(); self.model.selection = nil }
            }
        }
    }
}
