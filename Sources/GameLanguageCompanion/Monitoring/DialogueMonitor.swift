import Foundation
import AppKit
import Combine
import ScreenCaptureKit

/// Passive monitoring: watches only the dialogue area, runs OCR when the text has settled,
/// and keeps `dialogue` (the current dialogue with word positions) up to date.
/// Nothing is written to disk; at most one frame is kept for the debug preview.
@MainActor
final class DialogueMonitor: ObservableObject {
    enum State: Equatable {
        case stopped, starting, active, paused
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var dialogue: CurrentDialogue?
    @Published private(set) var lastOCRDate: Date?
    @Published private(set) var ocrRunCount = 0
    /// The most recent frame that was sent to OCR (debug preview only; replaced each time).
    @Published private(set) var lastFrame: CGImage?

    private let settings: AppSettings
    private let permissions: PermissionManager
    private let profiles: ProfileStore
    private let gameContext: GameContextManager
    private let history: HistoryRepository

    private var stream: SCStream?
    private var processor: FrameProcessor?
    private var streamRegion: CaptureRegion?
    private var userPaused = false
    private var generation = 0
    private var watchTask: Task<Void, Never>?

    init(settings: AppSettings, permissions: PermissionManager, profiles: ProfileStore,
         gameContext: GameContextManager, history: HistoryRepository) {
        self.settings = settings
        self.permissions = permissions
        self.profiles = profiles
        self.gameContext = gameContext
        self.history = history
    }

    var isMonitoring: Bool { state == .active || state == .starting }

    var statusText: String {
        switch state {
        case .stopped: return tr("Stopped")
        case .starting: return tr("Starting…")
        case .active: return tr("Active")
        case .paused: return tr("Paused")
        case .failed(let message): return message
        }
    }

    // MARK: Control

    func start() async {
        userPaused = false
        await restart()
    }

    /// (Re)starts the stream with the current settings and dialogue area.
    func restart() async {
        guard !userPaused else { return }
        generation += 1
        let token = generation
        await teardown()

        guard settings.monitoringEnabled else { state = .stopped; return }
        permissions.refresh()
        guard permissions.hasScreenRecordingAccess else {
            state = .failed(tr("Screen Recording permission missing"))
            return
        }
        guard let region = await profiles.resolvedRegion() ?? settings.captureRegion else {
            state = .failed(tr("No capture area selected"))
            return
        }
        guard token == generation else { return }

        state = .starting
        do {
            try await beginStream(region: region, window: await profiles.windowTarget())
            guard token == generation else { await teardown(); return }
            state = .active
            startWatchingWindow()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func pause() async {
        userPaused = true
        generation += 1
        await teardown()
        state = .paused
    }

    func resume() async { await start() }

    func stop() async {
        generation += 1
        await teardown()
        state = .stopped
    }

    // MARK: One-shot refresh (Reading Mode without running monitor)

    /// Captures and recognizes the dialogue area right now.
    func refreshNow() async {
        permissions.refresh()
        guard permissions.hasScreenRecordingAccess,
              let region = await profiles.resolvedRegion() ?? settings.captureRegion,
              let frame = region.screenFrame else { return }
        do {
            let image = try await ScreenCaptureManager().capture(region: region, window: await profiles.windowTarget())
            let result = try await VisionWordOCR(language: settings.ocrLanguage).recognizeWords(in: image)
            lastFrame = image
            apply(result, frame: frame, force: true)
        } catch {
            // Reading Mode shows its own "nothing found" hint.
        }
    }

    // MARK: Stream

    private func beginStream(region: CaptureRegion, window target: WindowCaptureTarget?) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Our own windows (Reading Mode, popups) must never end up in the OCR input.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        var filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        var bounds = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        var wanted = region.rect
        // Capture the game window itself when we know it: what is covering or behind it does not matter.
        if let target, let window = content.windows.first(where: { $0.windowID == target.windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            bounds = CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)
            wanted = target.rect
        }
        let rect = wanted.intersection(bounds)
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { throw CaptureError.invalidRegion }

        let displayID = display.displayID
        let scale = NSScreen.screens.first(where: { $0.displayID == displayID })?.backingScaleFactor ?? 2.0

        let frequency = min(max(settings.monitoringFrequency, 1), 4)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = max(1, Int((rect.width * scale).rounded()))
        configuration.height = max(1, Int((rect.height * scale).rounded()))
        configuration.minimumFrameInterval = CMTime(seconds: 1.0 / frequency, preferredTimescale: 600)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let processor = FrameProcessor(
            timing: .init(stabilityDelay: settings.stabilityDelay, cooldown: settings.ocrCooldown),
            detector: LuminanceFrameChangeDetector())
        let language = settings.ocrLanguage
        let frameRegion = region
        processor.onStableFrame = { [weak self] image, done in
            Task { @MainActor in
                await self?.process(image: image, region: frameRegion, language: language)
                done()
            }
        }
        processor.onStop = { [weak self] error in
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                self.state = .failed(CaptureError.failed(error.localizedDescription).localizedDescription)
            }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: processor)
        try stream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: processor.sampleQueue)
        try await stream.startCapture()
        processor.startTicking()

        self.stream = stream
        self.processor = processor
        self.streamRegion = region
    }

    private func teardown() async {
        watchTask?.cancel()
        watchTask = nil
        processor?.stopTicking()
        processor?.onStableFrame = nil
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        processor = nil
        streamRegion = nil
        lastFrame = nil
    }

    /// If the game window moves or resizes, the window-relative dialogue area moves with it.
    private func startWatchingWindow() {
        guard profiles.activeProfile?.relativeRegion != nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if let region = await self.profiles.resolvedRegion(), region != self.streamRegion {
                    await self.restart()
                    return
                }
            }
        }
    }

    // MARK: Recognition

    private func process(image: CGImage, region: CaptureRegion, language: Language) async {
        guard isMonitoring, let frame = region.screenFrame else { return }
        do {
            let result = try await VisionWordOCR(language: language).recognizeWords(in: image)
            lastFrame = image
            apply(result, frame: frame, force: false)
        } catch {
            // A failed pass is not fatal; the next change will try again.
        }
    }

    private func apply(_ result: WordOCRResult, frame: CGRect, force: Bool) {
        lastOCRDate = Date()
        ocrRunCount += 1

        let built = DialogueBuilder.build(from: result, frame: frame, game: gameContext.currentGameName(),
                                          detectSpeaker: settings.detectSpeakerLabel)
        guard let built else {
            if dialogue != nil { dialogue = nil }
            return
        }
        // Do not rewrite the dialogue for harmless OCR differences.
        if !force, let current = dialogue, DialogueBuilder.effectivelySame(current.fullText, built.fullText) {
            return
        }
        let isNewText = dialogue.map { !DialogueBuilder.effectivelySame($0.fullText, built.fullText) } ?? true
        dialogue = built
        if isNewText, settings.saveHistory {
            history.record(original: built.fullText, speaker: built.speaker, translation: nil,
                           game: built.sourceGame, provider: nil)
        }
    }
}
