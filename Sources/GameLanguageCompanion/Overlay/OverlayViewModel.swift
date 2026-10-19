import Foundation
import Combine

/// Everything the overlay shows for one processed dialogue line.
struct DialogueResult: Identifiable {
    let id = UUID()
    var speaker: String?
    var original: String
    var translation: String?
    var translationError: String?
    var provider: String?
    var analysis: LanguageAnalysis
    var game: String?
    var recordID: UUID
}

@MainActor
final class OverlayViewModel: ObservableObject {
    enum State {
        case hidden
        case working(String)
        case info(String)
        case error(String)
        case result(DialogueResult)
    }

    @Published private(set) var state: State = .hidden
    @Published var selectedKey: String?
    @Published var translationRevealed = false
    @Published var showVocabulary = true
    @Published var feedback: String?
    @Published private(set) var glosses: [String: WordGloss] = [:]
    @Published private(set) var sentenceSaved = false
    @Published private(set) var isTranslating = false

    /// Updated by the view's hover tracking; used to postpone auto-hide.
    var isHovering = false
    var onClose: () -> Void = {}

    let settings: AppSettings
    let vocabulary: VocabularyManager
    private let history: HistoryRepository
    private let glossService: WordGlossService
    private let ankiProvider: () -> (any AnkiService)?
    private let translationProvider: () -> any TranslationService
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings, vocabulary: VocabularyManager, history: HistoryRepository,
        glossService: WordGlossService, ankiProvider: @escaping () -> (any AnkiService)?,
        translationProvider: @escaping () -> any TranslationService
    ) {
        self.settings = settings
        self.vocabulary = vocabulary
        self.history = history
        self.glossService = glossService
        self.ankiProvider = ankiProvider
        self.translationProvider = translationProvider
        // Marking a word known must immediately refresh chips and highlights.
        vocabulary.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: State

    func setState(_ newState: State) {
        state = newState
        if case .result = newState {
            selectedKey = nil
            translationRevealed = settings.mode == .translation
            showVocabulary = true
            feedback = nil
            sentenceSaved = false
        }
    }

    var result: DialogueResult? {
        if case .result(let result) = state { return result }
        return nil
    }

    /// Candidates worth showing, after applying the user's known/learning/ignored words.
    var visibleCandidates: [VocabularyCandidate] {
        guard let result else { return [] }
        return vocabulary.suggestions(from: result.analysis.candidates,
                                      minimumDifficulty: settings.minimumDifficulty,
                                      limit: settings.maxCandidates)
    }

    var selectedCandidate: VocabularyCandidate? {
        guard let key = selectedKey else { return nil }
        return result?.analysis.candidates.first { $0.key == key }
    }

    // MARK: Actions

    func select(key: String) {
        selectedKey = (selectedKey == key) ? nil : key
        feedback = nil
        guard selectedKey != nil, glosses[key] == nil,
              let candidate = result?.analysis.candidates.first(where: { $0.key == key }) else { return }
        Task {
            let gloss = await glossService.gloss(for: candidate)
            glosses[key] = gloss
        }
    }

    func mark(_ status: VocabularyStatus) {
        guard let candidate = selectedCandidate, let result else { return }
        vocabulary.setStatus(status, for: candidate, sentence: result.original,
                             sentenceTranslation: result.translation,
                             wordTranslation: glosses[candidate.key]?.translation, game: result.game)
        feedback = tr("“%@” → %@", candidate.displayForm, status.title.lowercased())
        if status == .known || status == .ignored { selectedKey = nil }
    }

    func addToAnki() {
        guard let candidate = selectedCandidate, let result else { return }
        guard let anki = ankiProvider() else {
            feedback = tr("The AnkiConnect URL in Settings is invalid.")
            return
        }
        feedback = tr("Adding to Anki…")
        let builder = AnkiCardBuilder(
            deck: settings.ankiDeck, style: settings.ankiCardStyle,
            basicModel: settings.ankiBasicModel, clozeModel: settings.ankiClozeModel)
        Task {
            var gloss = glosses[candidate.key]
            if gloss == nil {
                gloss = await glossService.gloss(for: candidate)
                glosses[candidate.key] = gloss
            }
            let card = builder.build(candidate: candidate, sentence: result.original,
                                     sentenceTranslation: result.translation,
                                     wordTranslation: gloss?.translation, game: result.game)
            do {
                _ = try await anki.add(card: card)
                vocabulary.setStatus(.learning, for: candidate, sentence: result.original,
                                     sentenceTranslation: result.translation,
                                     wordTranslation: gloss?.translation, game: result.game)
                vocabulary.markAddedToAnki(key: candidate.key)
                feedback = tr("Added “%@” to Anki", candidate.displayForm)
            } catch AnkiError.duplicate {
                vocabulary.setStatus(.learning, for: candidate, sentence: result.original,
                                     sentenceTranslation: result.translation,
                                     wordTranslation: gloss?.translation, game: result.game)
                vocabulary.markAddedToAnki(key: candidate.key)
                feedback = tr("Already in Anki")
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    func saveSentence() {
        guard let result else { return }
        history.setSaved(result.recordID, saved: true)
        sentenceSaved = true
        feedback = tr("Sentence saved to History")
    }

    /// For Immersion mode (and as a retry): translate on demand.
    func requestTranslation() {
        guard var current = result, !isTranslating else { return }
        isTranslating = true
        let translator = translationProvider()
        let source = settings.sourceLanguage, target = settings.targetLanguage
        Task {
            defer { isTranslating = false }
            do {
                let translation = try await translator.translate(current.original, from: source, to: target)
                current.translation = translation.translatedText
                current.translationError = nil
                current.provider = translation.provider
                history.updateTranslation(current.recordID, translation: translation.translatedText,
                                          provider: translation.provider)
                state = .result(current)
                translationRevealed = true
            } catch {
                current.translationError = error.localizedDescription
                state = .result(current)
            }
        }
    }

    func close() { onClose() }
}
