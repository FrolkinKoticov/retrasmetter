import AppKit
import SwiftUI
import Combine

/// What the subtitle layer shows and how it looks.
@MainActor
final class SubtitleModel: ObservableObject {
    enum Phase { case hidden, loading, text(String), failed(String) }
    @Published var phase: Phase = .hidden
    /// true: sits exactly over the original text, in the game's colors. false: a separate bar.
    @Published var inPlace = true
    @Published var background = Color.black.opacity(0.75)
    @Published var foreground = Color.white
    /// Font size matched to the original text (in-place mode).
    @Published var fontSize: CGFloat = 22
    @Published var width: CGFloat = 600
    @Published var height: CGFloat = 60
}

/// Live subtitles: translates every new dialogue line on its own and shows it over the original
/// (matching the game's look) or in a bar. The layer ignores the mouse, so the game plays as usual.
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
    private var anchor: CGRect = .zero          // where the original text is (global AppKit coords)
    private var dialogueRegion: CGRect = .zero
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

        // A new line is being typed → get out of the way so the player sees the original appear.
        monitor.activity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.lineIsChanging() } }
            .store(in: &cancellables)

        // OCR finished without a different text (e.g. a blinking icon): bring the translation back.
        monitor.$ocrRunCount
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.restoreIfSame() } } }
            .store(in: &cancellables)

        profiles.$profiles
            .combineLatest(profiles.$activeProfileID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in MainActor.assumeIsolated { self?.modeChanged() } }
            .store(in: &cancellables)

        settings.$subtitleFontSize.combineLatest(settings.$subtitlesAbove, settings.$subtitleReplaceInPlace)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshLook() } } }
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
        if isEnabled { dialogueChanged(monitor.dialogue, force: true) } else { task?.cancel(); hide() }
    }

    private func lineIsChanging() {
        guard isEnabled, !suppressed, settings.subtitleReplaceInPlace else { return }
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }

    private func restoreIfSame() {
        guard isEnabled, !suppressed, let dialogue = monitor.dialogue,
              DialogueBuilder.comparisonKey(dialogue.fullText) == currentKey,
              cache[currentKey] != nil, panel?.isVisible != true else { return }
        show()
    }

    private func dialogueChanged(_ dialogue: CurrentDialogue?, force: Bool = false) {
        guard isEnabled, !suppressed else { return }
        guard let dialogue else {            // dialogue box closed → subtitles go too
            task?.cancel(); currentKey = ""; hide(); return
        }
        let key = DialogueBuilder.comparisonKey(dialogue.fullText)
        guard force || key != currentKey || panel?.isVisible != true else { return }
        let isNewLine = key != currentKey
        currentKey = key
        updateGeometry(for: dialogue)
        task?.cancel()

        if let cached = cache[key] {
            model.phase = .text(cached)
            show()
            remember(dialogue.fullText)
            return
        }

        // In-place mode keeps the original visible until the translation is ready.
        if settings.subtitleReplaceInPlace {
            if isNewLine { panel?.orderOut(nil) }
        } else {
            model.phase = .loading
            show()
        }
        let text = dialogue.fullText
        let previous = recent
        let source = settings.sourceLanguage, target = settings.targetLanguage
        let translator = translationProvider()
        task = Task { [weak self] in
            do {
                let result = try await translator.translateDialogue(text, previous: previous, from: source, to: target)
                guard !Task.isCancelled, let self, self.currentKey == key else { return }
                if self.cache.count > 500 { self.cache.removeAll() }
                self.cache[key] = result.translatedText
                self.model.phase = .text(result.translatedText)
                self.remember(text)
                self.show()
            } catch {
                guard !Task.isCancelled, let self, self.currentKey == key else { return }
                self.model.phase = .failed(error.localizedDescription)
                self.show()
            }
        }
    }

    private func remember(_ line: String) {
        if recent.last != line { recent.append(line) }
        if recent.count > 4 { recent.removeFirst(recent.count - 4) }
    }

    // MARK: Look

    private func updateGeometry(for dialogue: CurrentDialogue) {
        dialogueRegion = dialogue.regionFrame
        model.inPlace = settings.subtitleReplaceInPlace
        if settings.subtitleReplaceInPlace, !dialogue.words.isEmpty {
            // Cover exactly the text rows (the speaker's name above stays visible), across the area's width.
            let union = dialogue.frame(of: 0...(dialogue.words.count - 1))
            anchor = CGRect(x: dialogue.regionFrame.minX, y: union.minY - 6,
                            width: dialogue.regionFrame.width, height: union.height + 12)
            let height = dialogue.words.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(dialogue.words.count)
            model.fontSize = min(max(height * 0.8, 12), 44)
            if let frame = monitor.lastFrame, let palette = RegionColors.sample(from: frame) {
                model.background = palette.background
                model.foreground = palette.foreground
            }
        } else {
            anchor = dialogue.regionFrame
            model.background = Color.black.opacity(0.75)
            model.foreground = .white
            model.fontSize = settings.subtitleFontSize
        }
    }

    private func refreshLook() {
        if let dialogue = monitor.dialogue, isEnabled { updateGeometry(for: dialogue) }
        reposition()
    }

    // MARK: Panel

    private func show() {
        guard isEnabled, !suppressed else { return }
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

    private func reposition() {
        guard let panel, panel.isVisible, anchor != .zero else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if model.inPlace {
            // Exactly over the original text; the text shrinks to fit rather than growing out of the box.
            model.width = anchor.width
            model.height = anchor.height
            panel.setFrame(anchor, display: true)
            return
        }

        let width = min(max(anchor.width, 480), 1100)
        model.width = width
        hosting?.layoutSubtreeIfNeeded()
        let height = max(hosting?.fittingSize.height ?? 40, 36)
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
        content
            .frame(width: model.width, height: model.inPlace ? model.height : nil, alignment: model.inPlace ? .topLeading : .center)
            .fixedSize(horizontal: false, vertical: !model.inPlace)
    }

    @ViewBuilder
    private var content: some View {
        if model.inPlace {
            label
                .font(.system(size: model.fontSize, weight: .medium))
                .foregroundStyle(model.foreground)
                .lineLimit(6)
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(model.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            label
                .font(.system(size: model.fontSize, weight: .medium))
                .foregroundStyle(model.foreground)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(model.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var label: some View {
        switch model.phase {
        case .hidden: EmptyView()
        case .loading: Text("…")
        case .text(let text): Text(text).fixedSize(horizontal: false, vertical: !model.inPlace)
        case .failed(let message): Text(message).font(.system(size: 12)).foregroundStyle(.red)
        }
    }
}
