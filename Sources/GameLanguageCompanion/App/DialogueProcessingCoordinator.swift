import Foundation

/// Runs the whole pipeline:
/// CaptureRegion → ScreenCaptureManager → OCRService → OCRTextCleaner →
/// TranslationService (+ LanguageAnalyzer in parallel mode-wise) → Overlay.
///
/// Every stage is injected, so a different OCR engine, translator or analyzer can be swapped
/// in without touching this class. Screenshots never leave memory; only recognized text is
/// handed to the translation provider.
@MainActor
final class DialogueProcessingCoordinator {
    private let settings: AppSettings
    private let permissions: PermissionManager
    private let capture: ScreenCaptureManager
    private let ocrProvider: () -> any OCRService
    private let translationProvider: () -> any TranslationService
    private let analyzerProvider: () -> any LanguageAnalyzer
    private let vocabulary: VocabularyManager
    private let history: HistoryRepository
    private let overlay: OverlayWindowController
    private let gameContext: GameContextManager

    private var isProcessing = false

    /// Set by AppState: the game window to capture directly, when the profile has one.
    var windowTargetProvider: (() async -> WindowCaptureTarget?)?

    init(
        settings: AppSettings, permissions: PermissionManager, capture: ScreenCaptureManager,
        ocrProvider: @escaping () -> any OCRService,
        translationProvider: @escaping () -> any TranslationService,
        analyzerProvider: @escaping () -> any LanguageAnalyzer,
        vocabulary: VocabularyManager, history: HistoryRepository,
        overlay: OverlayWindowController, gameContext: GameContextManager
    ) {
        self.settings = settings
        self.permissions = permissions
        self.capture = capture
        self.ocrProvider = ocrProvider
        self.translationProvider = translationProvider
        self.analyzerProvider = analyzerProvider
        self.vocabulary = vocabulary
        self.history = history
        self.overlay = overlay
        self.gameContext = gameContext
    }

    /// Diagnostics for "Test OCR": capture → Vision → cleaning, without translating or saving.
    func recognizeCurrentRegion() async throws -> String {
        guard let region = settings.captureRegion else { throw CaptureError.noRegion }
        permissions.refresh()
        guard permissions.hasScreenRecordingAccess else { throw CaptureError.permissionDenied }
        let image = try await capture.capture(region: region, window: await windowTargetProvider?())
        let raw = try await ocrProvider().recognizeText(in: image)
        let cleaned = OCRTextCleaner(detectSpeakerLabel: settings.detectSpeakerLabel).clean(raw)
        return cleaned.text.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned.text
    }

    func processCurrentDialogue() async {
        guard !isProcessing else { return }       // ignore hotkey mashing while a run is active
        isProcessing = true
        defer { isProcessing = false }

        guard let region = settings.captureRegion else {
            overlay.present(.error(tr("No capture area yet. Choose “Select Capture Area” from the menu bar icon and drag over the game’s subtitle box.")), near: nil)
            return
        }

        permissions.refresh()
        guard permissions.hasScreenRecordingAccess else {
            overlay.present(.error(permissions.explanation), near: region)
            permissions.requestAccess()
            return
        }

        let game = gameContext.currentGameName()      // read before anything can change focus
        overlay.present(.working(tr("Reading dialogue…")), near: region)

        do {
            let image = try await capture.capture(region: region, window: await windowTargetProvider?())
            let raw = try await ocrProvider().recognizeText(in: image)
            let cleaned = OCRTextCleaner(detectSpeakerLabel: settings.detectSpeakerLabel).clean(raw)
            guard !cleaned.isEmpty else {
                overlay.present(.error(tr("No text was recognized in the capture area. Re-select the area so it tightly covers the subtitle text.")), near: region)
                return
            }

            let translator = translationProvider()
            let analyzer = analyzerProvider()
            let source = settings.sourceLanguage, target = settings.targetLanguage
            let wantsTranslation = settings.mode != .immersion

            async let analysisTask = analyzer.analyze(sentence: cleaned.text)

            var translation: String?
            var translationError: String?
            var provider: String?
            if wantsTranslation {
                do {
                    let result = try await translator.translate(cleaned.text, from: source, to: target)
                    translation = result.translatedText
                    provider = result.provider
                } catch {
                    // The original sentence and vocabulary are still useful without a translation.
                    translationError = error.localizedDescription
                }
            }
            let analysis = try await analysisTask

            let record = history.record(original: cleaned.text, speaker: cleaned.speaker,
                                        translation: translation, game: game, provider: provider)
            vocabulary.recordSeen(analysis.candidates)

            let result = DialogueResult(
                speaker: cleaned.speaker, original: cleaned.text, translation: translation,
                translationError: translationError, provider: provider, analysis: analysis,
                game: game, recordID: record.id)
            overlay.present(.result(result), near: region)
        } catch {
            overlay.present(.error(error.localizedDescription), near: region)
        }
    }
}
