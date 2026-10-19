import AppKit
import SwiftUI
import Combine

/// Everything behind the small translation popup: translate the selection in context,
/// pronounce it, add it to Anki, explain it, translate the whole sentence.
@MainActor
final class SelectionPopupModel: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case result(TranslationResult)
        case failed(String)
    }

    @Published private(set) var selection = ""
    @Published private(set) var context = ""
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var feedback: String?
    @Published private(set) var duplicatePending = false
    @Published private(set) var sentenceTranslation: String?
    @Published private(set) var sentenceLoading = false
    @Published private(set) var explanation: String?
    @Published private(set) var explaining = false
    @Published private(set) var status: VocabularyStatus?
    /// Already in the local vocabulary (before this popup) / saved by the button just now.
    @Published private(set) var saved = false
    @Published private(set) var justAdded = false

    let settings: AppSettings
    private let vocabulary: VocabularyManager
    private let translationProvider: () -> any TranslationService
    private let ankiProvider: () -> (any AnkiService)?
    private var game: String?
    private var speaker: String?
    private var task: Task<Void, Never>?
    private var cache: [String: TranslationResult] = [:]

    init(settings: AppSettings, vocabulary: VocabularyManager,
         translationProvider: @escaping () -> any TranslationService,
         ankiProvider: @escaping () -> (any AnkiService)?) {
        self.settings = settings
        self.vocabulary = vocabulary
        self.translationProvider = translationProvider
        self.ankiProvider = ankiProvider
    }

    var result: TranslationResult? {
        if case .result(let result) = state { return result }
        return nil
    }

    /// Explanations need an AI provider; offered only when an OpenAI key is stored.
    var canExplain: Bool {
        KeychainStore.read(account: KeychainStore.openAIAccount)?.isEmpty == false
    }

    // MARK: Selection

    func select(text: String, context: String, game: String?, speaker: String? = nil) {
        task?.cancel()
        selection = text
        self.context = context
        self.game = game
        self.speaker = speaker
        saved = false
        justAdded = false
        feedback = nil
        duplicatePending = false
        sentenceTranslation = nil
        explanation = nil
        status = vocabulary.status(forKey: text.lowercased())

        let cacheKey = text + "\u{1}" + context
        if let cached = cache[cacheKey] {
            state = .result(cached)
            record(cached)
            return
        }
        state = .loading
        let source = settings.sourceLanguage, target = settings.targetLanguage
        let translator = translationProvider()
        task = Task {
            do {
                let result = try await translator.translateSelection(
                    selection: text, context: context, from: source, to: target)
                guard !Task.isCancelled else { return }
                cache[cacheKey] = result
                state = .result(result)
                record(result)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        task?.cancel()
        state = .idle
        selection = ""
        feedback = nil
        duplicatePending = false
    }

    /// Selecting never saves by itself; if the expression is already saved it counts as seen again.
    private func record(_ result: TranslationResult) {
        let candidate = VocabularyCandidate.fromSelection(
            selection, normalized: result.normalizedExpression, partOfSpeech: result.partOfSpeech, sentence: context)
        saved = vocabulary.recordSelection(candidate: candidate, sentence: context,
                                           translation: result.translatedText, game: game)
        status = saved ? vocabulary.status(forKey: candidate.key) : nil
    }

    /// "+ Vocabulary": one click, no dialog.
    func addToVocabulary() {
        guard let candidate = currentCandidate(), !saved, !justAdded else { return }
        let added = vocabulary.addToVocabulary(
            candidate: candidate, sentence: context, sentenceTranslation: sentenceTranslation,
            translation: result?.translatedText, game: game, speaker: speaker)
        if added { justAdded = true } else { saved = true }
        status = vocabulary.status(forKey: candidate.key)
    }

    private func currentCandidate() -> VocabularyCandidate? {
        guard !selection.isEmpty else { return nil }
        return VocabularyCandidate.fromSelection(
            selection, normalized: result?.normalizedExpression, partOfSpeech: result?.partOfSpeech, sentence: context)
    }

    // MARK: Actions

    func pronounce() {
        Pronouncer.shared.speak(selection, language: settings.sourceLanguage)
    }

    func mark(_ newStatus: VocabularyStatus) {
        guard let candidate = currentCandidate() else { return }
        vocabulary.setStatus(newStatus, for: candidate, sentence: context, sentenceTranslation: sentenceTranslation,
                             wordTranslation: result?.translatedText, game: game)
        status = newStatus
        feedback = tr("“%@” → %@", candidate.displayForm, newStatus.title.lowercased())
    }

    func addToAnki(allowDuplicate: Bool = false) {
        guard let candidate = currentCandidate() else { return }
        guard let anki = ankiProvider() else {
            feedback = tr("The AnkiConnect URL in Settings is invalid.")
            return
        }
        // The local vocabulary is the primary record: save there first.
        addToVocabulary()
        feedback = tr("Adding to Anki…")
        duplicatePending = false
        let builder = AnkiCardBuilder(
            deck: settings.ankiDeck, style: settings.ankiCardStyle,
            basicModel: settings.ankiBasicModel, clozeModel: settings.ankiClozeModel)
        let sentence = context
        let translation = result?.translatedText
        let source = settings.sourceLanguage, target = settings.targetLanguage
        let translator = translationProvider()
        let known = sentenceTranslation
        let game = self.game

        Task {
            do {
                if !allowDuplicate, try await anki.cardExists(for: candidate.key) {
                    feedback = tr("Already in Anki")
                    duplicatePending = true
                    return
                }
                // The card shows the whole sentence in both languages; fetch it if we do not have it yet.
                var sentenceTranslated = known
                if sentenceTranslated == nil {
                    sentenceTranslated = try? await translator.translate(sentence, from: source, to: target).translatedText
                }
                let card = builder.build(candidate: candidate, sentence: sentence,
                                         sentenceTranslation: sentenceTranslated, wordTranslation: translation, game: game)
                _ = try await anki.add(card: card, allowDuplicate: allowDuplicate)
                vocabulary.setStatus(.learning, for: candidate, sentence: sentence,
                                     sentenceTranslation: sentenceTranslated, wordTranslation: translation, game: game)
                vocabulary.markAddedToAnki(key: candidate.key)
                status = .learning
                feedback = tr("Added “%@” to Anki", candidate.displayForm)
            } catch AnkiError.duplicate {
                feedback = tr("Already in Anki")
                duplicatePending = true
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    func cancelDuplicate() {
        duplicatePending = false
        feedback = nil
    }

    func translateSentence() {
        guard !sentenceLoading else { return }
        sentenceLoading = true
        let sentence = context
        let source = settings.sourceLanguage, target = settings.targetLanguage
        let translator = translationProvider()
        Task {
            defer { sentenceLoading = false }
            do {
                sentenceTranslation = try await translator.translate(sentence, from: source, to: target).translatedText
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    func explain() {
        guard !explaining, let key = KeychainStore.read(account: KeychainStore.openAIAccount), !key.isEmpty else { return }
        explaining = true
        let service = OpenAITranslationService(apiKey: key, model: settings.openAIModel)
        let text = selection, sentence = context
        let source = settings.sourceLanguage, target = settings.targetLanguage
        Task {
            defer { explaining = false }
            do {
                explanation = try await service.explain(selection: text, context: sentence, from: source, to: target)
            } catch {
                feedback = error.localizedDescription
            }
        }
    }
}

// MARK: - View

struct SelectionPopupView: View {
    @ObservedObject var model: SelectionPopupModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.selection).font(.system(size: 16, weight: .bold)).lineLimit(2)
                if let pos = model.result?.partOfSpeech {
                    Text(pos).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let status = model.status, status != .unknown {
                    Text(status.title).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
            }

            switch model.state {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(tr("Looking up…")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            case .result(let result):
                Text(result.translatedText).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                if let note = result.shortExplanation {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sentence = model.sentenceTranslation {
                Divider()
                Text(sentence).font(.system(size: 13)).italic().fixedSize(horizontal: false, vertical: true)
            }
            if let explanation = model.explanation {
                Divider()
                Text(explanation).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if model.sentenceLoading || model.explaining {
                ProgressView().controlSize(.small)
            }

            if let feedback = model.feedback {
                Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.duplicatePending {
                HStack {
                    Button(tr("Add this context")) { model.addToAnki(allowDuplicate: true) }
                    Button(tr("Cancel")) { model.cancelDuplicate() }
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button { model.pronounce() } label: { Image(systemName: "speaker.wave.2.fill") }
                    .help(tr("Pronounce"))
                if model.saved || model.justAdded {
                    Button { AppState.shared.showMain(.vocabulary) } label: {
                        Label(model.justAdded ? tr("Added") : tr("In Vocabulary"), systemImage: "checkmark")
                    }
                    .help(tr("Open Vocabulary"))
                } else {
                    Button { model.addToVocabulary() } label: { Label(tr("Vocabulary"), systemImage: "plus") }
                }
                if settings.ankiEnabled {
                    Button { model.addToAnki() } label: { Label("Anki", systemImage: "plus") }
                }
                Spacer()
                Menu(tr("More")) {
                    Button(tr("Translate Entire Sentence")) { model.translateSentence() }
                    if model.canExplain {
                        Button(tr("Explain")) { model.explain() }
                    }
                    Divider()
                    Button(tr("Learn")) { model.mark(.learning) }
                    Button(tr("Mark as Known")) { model.mark(.known) }
                    Button(tr("Ignore")) { model.mark(.ignored) }
                }
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
    }
}

// MARK: - Panel

/// The small floating panel next to the selected words. Never activates the app.
@MainActor
final class SelectionPopupController {
    let model: SelectionPopupModel
    private let settings: AppSettings
    private var panel: ReadingPanel?
    private var hosting: FirstMouseHostingView<SelectionPopupView>?
    private var anchor: CGRect = .zero
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { panel?.isVisible == true }
    var frame: CGRect? { isVisible ? panel?.frame : nil }

    init(model: SelectionPopupModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.reposition() }
                }
            }
            .store(in: &cancellables)
    }

    func show(near anchor: CGRect) {
        self.anchor = anchor
        if panel == nil {
            let panel = ReadingPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let hosting = FirstMouseHostingView(rootView: SelectionPopupView(model: model, settings: settings))
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
        }
        panel?.orderFrontRegardless()
        reposition()
    }

    func close() {
        panel?.orderOut(nil)
        model.reset()
    }

    /// Fits the panel to its content and puts it above the selection (below if there is no room).
    private func reposition() {
        guard let panel, let hosting, panel.isVisible else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let width = max(size.width, 320), height = max(size.height, 60)

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        var y = anchor.maxY + 8                                    // above
        if y + height > visible.maxY - 8 { y = anchor.minY - height - 8 }   // below
        y = min(max(y, visible.minY + 8), visible.maxY - height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
