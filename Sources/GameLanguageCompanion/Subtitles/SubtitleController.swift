import AppKit
import SwiftUI
import Combine

/// Live subtitles: translates every new dialogue line on its own and shows it next to the dialogue.
/// The overlay ignores the mouse, so the game is played exactly as before.
@MainActor
final class SubtitleModel: ObservableObject {
    enum Phase { case hidden, loading, text(String), failed(String) }
    @Published var phase: Phase = .hidden
}

@MainActor
final class SubtitleController {
    let model = SubtitleModel()

    private let monitor: DialogueMonitor
    private let settings: AppSettings
    private let profiles: ProfileStore
    private let translationProvider: () -> any TranslationService

    private var panel: ReadingPanel?
    private var hosting: FirstMouseHostingView<SubtitleView>?
    private var cancellables = Set<AnyCancellable>()
    private var task: Task<Void, Never>?

    private var currentKey = ""
    private var anchor: CGRect = .zero
    /// Last distinct lines (oldest first), used as translation context.
    private var recent: [String] = []
    private var cache: [String: String] = [:]
    private var suppressed = false

    init(monitor: DialogueMonitor, settings: AppSettings, profiles: ProfileStore,
         translationProvider: @escaping () -> any TranslationService) {
        self.monitor = monitor
        self.settings = settings
        self.profiles = profiles
        self.translationProvider = translationProvider

        monitor.$dialogue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dialogue in MainActor.assumeIsolated { self?.dialogueChanged(dialogue) } }
            .store(in: &cancellables)

        // Switching the mode (or profile) on/off takes effect immediately.
        profiles.$profiles
            .combineLatest(profiles.$activeProfileID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in MainActor.assumeIsolated { self?.modeChanged() } }
            .store(in: &cancellables)

        settings.$subtitleFontSize.combineLatest(settings.$subtitlesAbove)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.reposition() } } }
            .store(in: &cancellables)

        model.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.reposition() } } }
            .store(in: &cancellables)
    }

    var isEnabled: Bool { profiles.activeProfile?.subtitlesEnabled == true }

    /// Hidden while Reading Mode is on (the word layer sits over the dialogue then).
    func setSuppressed(_ value: Bool) {
        suppressed = value
        if value { hide() } else if isEnabled { dialogueChanged(monitor.dialogue, force: true) }
    }

    // MARK: Flow

    private func modeChanged() {
        if isEnabled { dialogueChanged(monitor.dialogue, force: true) } else { hide(); task?.cancel() }
    }

    private func dialogueChanged(_ dialogue: CurrentDialogue?, force: Bool = false) {
        guard isEnabled, !suppressed else { return }
        guard let dialogue else {            // dialogue box closed → subtitles go too
            task?.cancel(); currentKey = ""; hide(); return
        }
        let key = DialogueBuilder.comparisonKey(dialogue.fullText)
        guard force || key != currentKey else { return }
        currentKey = key
        anchor = dialogue.regionFrame
        task?.cancel()

        if let cached = cache[key] {
            model.phase = .text(cached)
            show()
            remember(dialogue.fullText)
            return
        }

        model.phase = .loading
        show()
        let text = dialogue.fullText
        let previous = recent
        let source = settings.sourceLanguage, target = settings.targetLanguage
        let translator = translationProvider()
        task = Task { [weak self] in
            do {
                let result = try await translator.translateDialogue(text, previous: previous, from: source, to: target)
                guard !Task.isCancelled, let self else { return }
                if self.cache.count > 500 { self.cache.removeAll() }
                self.cache[key] = result.translatedText
                self.model.phase = .text(result.translatedText)
                self.remember(text)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.model.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func remember(_ line: String) {
        if recent.last != line { recent.append(line) }
        if recent.count > 4 { recent.removeFirst(recent.count - 4) }
    }

    // MARK: Panel

    private func show() {
        if panel == nil {
            let panel = ReadingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 60),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true            // never gets in the way of the game
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let hosting = FirstMouseHostingView(rootView: SubtitleView(model: model, settings: settings))
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
        }
        panel?.orderFrontRegardless()
        reposition()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.phase = .hidden
    }

    /// Below the dialogue (or above, per setting); flips when there is no room on screen.
    private func reposition() {
        guard let panel, let hosting, panel.isVisible, anchor != .zero else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let width = min(max(anchor.width, 480), 1100)
        let height = max(size.height, 36)

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var y = settings.subtitlesAbove ? anchor.maxY + 6 : anchor.minY - height - 6
        if settings.subtitlesAbove, y + height > visible.maxY { y = anchor.minY - height - 6 }
        if !settings.subtitlesAbove, y < visible.minY { y = anchor.maxY + 6 }
        y = min(max(y, visible.minY), visible.maxY - height)
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX), visible.maxX - width)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

struct SubtitleView: View {
    @ObservedObject var model: SubtitleModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            switch model.phase {
            case .hidden:
                EmptyView()
            case .loading:
                Text("…").foregroundStyle(.white.opacity(0.6))
            case .text(let text):
                Text(text).foregroundStyle(.white)
            case .failed(let message):
                Text(message).foregroundStyle(.red.opacity(0.9)).font(.system(size: 12))
            }
        }
        .font(.system(size: settings.subtitleFontSize, weight: .medium))
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.8), radius: 2)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}
