import AppKit
import SwiftUI
import SwiftData
import Combine

/// Composition root: owns every service and wires them together.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings: AppSettings
    let permissions: PermissionManager
    let container: ModelContainer
    let vocabulary: VocabularyManager
    let history: HistoryRepository
    let overlay: OverlayWindowController
    let coordinator: DialogueProcessingCoordinator
    let hotkeys = HotkeyManager()
    let regionSelector = RegionSelectionController()
    let windows = WindowManager()
    let navigation = NavigationModel()
    let status = StatusMonitor()
    let gameContext: GameContextManager
    let profiles: ProfileStore
    let monitor: DialogueMonitor
    let reading: ReadingModeController
    let subtitles: SubtitleController

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {
        let settings = AppSettings()
        let permissions = PermissionManager()
        let container = Self.makeContainer()
        let vocabulary = VocabularyManager(container: container)
        let history = HistoryRepository(container: container)
        let gameContext = GameContextManager(settings: settings)

        // Providers are closures so changed settings take effect immediately.
        let translationProvider: () -> any TranslationService = { TranslationServiceFactory.make(settings: settings) }
        let glossService = WordGlossService(settings: settings, translationProvider: translationProvider)
        let viewModel = OverlayViewModel(
            settings: settings, vocabulary: vocabulary, history: history, glossService: glossService,
            ankiProvider: { AnkiConnectService(urlString: settings.ankiURL) },
            translationProvider: translationProvider)
        let overlay = OverlayWindowController(settings: settings, viewModel: viewModel)

        let profiles = ProfileStore(settings: settings)
        let monitor = DialogueMonitor(settings: settings, permissions: permissions, profiles: profiles,
                                      gameContext: gameContext, history: history)
        let popupModel = SelectionPopupModel(
            settings: settings, vocabulary: vocabulary, translationProvider: translationProvider,
            ankiProvider: { AnkiConnectService(urlString: settings.ankiURL) })
        self.profiles = profiles
        self.monitor = monitor
        self.subtitles = SubtitleController(monitor: monitor, settings: settings, profiles: profiles,
                                            translationProvider: translationProvider)
        self.reading = ReadingModeController(monitor: monitor, settings: settings, overlay: overlay, popupModel: popupModel)
        self.gameContext = gameContext
        self.settings = settings
        self.permissions = permissions
        self.container = container
        self.vocabulary = vocabulary
        self.history = history
        self.overlay = overlay
        self.coordinator = DialogueProcessingCoordinator(
            settings: settings, permissions: permissions, capture: ScreenCaptureManager(),
            ocrProvider: { VisionOCRService(language: settings.ocrLanguage) },
            translationProvider: translationProvider,
            analyzerProvider: {
                NaturalLanguageAnalyzer(
                    language: settings.sourceLanguage,
                    phraseDetector: EnglishPhraseDetector(detectGenericPhrasalVerbs: settings.detectGenericPhrasalVerbs))
            },
            vocabulary: vocabulary, history: history, overlay: overlay, gameContext: gameContext)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        permissions.refresh()

        #if canImport(Translation)
        if #available(macOS 15.0, *) { AppleTranslationBridge.shared.installHostIfNeeded() }
        #endif

        reading.$isActive
            .sink { [weak self] active in self?.subtitles.setSuppressed(active) }
            .store(in: &cancellables)
        coordinator.windowTargetProvider = { [profiles] in await profiles.windowTarget() }
        profiles.migrateIfNeeded(gameName: gameContext.currentGameName())
        hotkeys.onTrigger = { [weak self] in self?.reading.toggle() }
        hotkeys.onEscape = { [weak self] in self?.reading.escapePressed() }
        reading.setEscapeHotkey = { [weak self] enabled in self?.hotkeys.setEscapeEnabled(enabled) }
        hotkeys.onSubtitles = { [weak self] in self?.toggleSubtitles(announce: true) }
        registerHotkey(key: settings.hotkeyKey, modifiers: settings.hotkeyModifiers)
        registerSubtitleHotkey()
        showStartupWindow()
        Publishers.CombineLatest(settings.$subtitleHotkeyKey, settings.$hotkeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in self?.registerSubtitleHotkey() }
            .store(in: &cancellables)
        // Live subtitles use faster timing: restart the stream when the mode flips.
        profiles.$profiles
            .map { [profiles] list in list.first(where: { $0.id == profiles.activeProfileID })?.subtitlesEnabled == true }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.restartMonitoring() } }
            .store(in: &cancellables)
        Publishers.CombineLatest(settings.$hotkeyKey, settings.$hotkeyModifiers)
            .dropFirst()
            .sink { [weak self] key, modifiers in self?.registerHotkey(key: key, modifiers: modifiers) }
            .store(in: &cancellables)

        // Passive monitoring: starts at launch, restarts when the area or its settings change.
        Task { await startMonitoringIfEnabled() }
        Publishers.MergeMany([
            settings.$captureRegion.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$monitoringEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$monitoringFrequency.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$stabilityDelay.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$ocrCooldown.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$ocrLanguageCode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            profiles.$activeProfileID.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
        .debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            Task { await self.restartMonitoring() }
        }
        .store(in: &cancellables)
    }

    private func startMonitoringIfEnabled() async {
        guard settings.monitoringEnabled, settings.hasCompletedOnboarding || settings.captureRegion != nil else { return }
        await monitor.start()
    }

    private func restartMonitoring() async {
        if !settings.monitoringEnabled { await monitor.stop(); return }
        if monitor.state == .paused { return }
        await monitor.restart()
    }

    /// Live subtitles on/off for the active game profile (creates a profile if there is none yet).
    func toggleSubtitles(announce: Bool = false) {
        if profiles.activeProfile == nil { profiles.createProfile(name: gameContext.currentGameName() ?? "My Game") }
        guard var profile = profiles.activeProfile else { return }
        profile.subtitlesEnabled = !(profile.subtitlesEnabled ?? false)
        profiles.update(profile)
        if announce {
            let on = profile.subtitlesEnabled == true
            overlay.present(.info(on ? tr("Live subtitles: on") : tr("Live subtitles: off")),
                            near: settings.captureRegion, autoHide: 1.5)
        }
    }

    func toggleMonitoring() {
        Task {
            if monitor.state == .paused { await monitor.resume() }
            else if monitor.isMonitoring { await monitor.pause() }
            else { await monitor.start() }
        }
    }

    private func registerSubtitleHotkey() {
        let key = settings.subtitleHotkeyKey, modifiers = settings.hotkeyModifiers
        guard key != settings.hotkeyKey else { return }       // would collide with Reading Mode
        if !hotkeys.registerSubtitles(key: key, modifiers: modifiers) {
            overlay.present(.error(tr("The hotkey %@ could not be registered — another app or macOS may be using it. Pick a different one in Settings.", modifiers.symbols + key)), near: nil)
        }
    }

    private func registerHotkey(key: String, modifiers: HotkeyModifiers) {
        if !hotkeys.register(key: key, modifiers: modifiers) {
            overlay.present(.error(tr("The hotkey %@ could not be registered — another app or macOS may be using it. Pick a different one in Settings.", modifiers.symbols + key)), near: nil)
        }
    }

    // MARK: Actions (menu bar + hotkey)

    func translateCurrentDialogue(fromMenu: Bool) {
        Task {
            // Give the menu a moment to close so it is not in front of the game.
            if fromMenu { try? await Task.sleep(nanoseconds: 350_000_000) }
            await coordinator.processCurrentDialogue()
        }
    }

    func selectCaptureArea() {
        regionSelector.beginSelection { [weak self] region in
            guard let self, let region else { return }
            Task {
                let windows = (try? await WindowCatalog.visibleWindows()) ?? []
                self.profiles.saveRegion(region, windows: windows, fallbackName: self.gameContext.currentGameName())
                self.overlay.present(.info(tr("Dialogue area saved (%@)", region.summary)), near: region)
            }
        }
    }

    /// First launch → onboarding wizard; otherwise the main window.
    func showStartupWindow() {
        if settings.hasCompletedOnboarding { showMain(.home) } else { showOnboarding() }
    }

    func showMain(_ page: SidebarItem? = nil) {
        if let page { navigation.selection = page }
        windows.show(id: "main", title: "Retrasmetter", size: NSSize(width: 1000, height: 680)) {
            MainWindowView(appState: self, settings: self.settings, navigation: self.navigation)
        }
    }

    func showOnboarding() {
        windows.show(id: "onboarding", title: "Retrasmetter", size: NSSize(width: 720, height: 600)) {
            OnboardingView(appState: self, settings: self.settings, permissions: self.permissions) { [weak self] in
                guard let self else { return }
                self.windows.close(id: "onboarding")
                self.showMain(.home)
            }
        }
    }

    // Kept for call sites that still use the old names.
    func showVocabulary() { showMain(.vocabulary) }
    func showHistory() { showMain(.history) }
    func showSettings() { showMain(.settings) }

    /// Closes the menu bar popover (a `MenuBarExtra` window) after one of its buttons is pressed.
    func dismissMenuWindow() {
        if let window = NSApp.keyWindow, String(describing: type(of: window)).contains("MenuBarExtra") {
            window.orderOut(nil)
        }
    }

    /// "Add to Anki" for a saved vocabulary item (from the Vocabulary table). Returns a message.
    func addToAnki(_ item: VocabularyItem) async -> String {
        guard let anki = AnkiConnectService(urlString: settings.ankiURL) else {
            return tr("The AnkiConnect URL in Settings is invalid.")
        }
        let builder = AnkiCardBuilder(
            deck: settings.ankiDeck, style: settings.ankiCardStyle,
            basicModel: settings.ankiBasicModel, clozeModel: settings.ankiClozeModel)
        do {
            _ = try await anki.add(card: builder.build(item: item))
            vocabulary.markAddedToAnki(key: item.key)
            if item.status == .unknown { vocabulary.update(item, status: .learning) }
            return tr("Added “%@” to Anki", item.expression)
        } catch AnkiError.duplicate {
            vocabulary.markAddedToAnki(key: item.key)
            return tr("Already in Anki")
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Storage

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([VocabularyItem.self, DialogueRecord.self])
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("GameLanguageCompanion", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Library.store"))
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("Persistent store unavailable (\(error)); using an in-memory store for this session.")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // An in-memory container only fails if SwiftData itself is broken.
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }
}
