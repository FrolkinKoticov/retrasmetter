import Foundation
import SwiftData

/// The "known word system": remembers what the learner knows, decides which candidates to
/// suggest, and saves vocabulary with its sentence context.
@MainActor
final class VocabularyManager: ObservableObject {
    /// key → status, kept in memory for instant lookups while building overlays.
    @Published private(set) var statuses: [String: VocabularyStatus] = [:]

    private let repository: VocabularyRepository

    init(container: ModelContainer) {
        repository = VocabularyRepository(context: container.mainContext)
        reload()
    }

    func reload() {
        var map: [String: VocabularyStatus] = [:]
        for item in repository.allItems() { map[item.key] = item.status }
        statuses = map
    }

    func status(forKey key: String) -> VocabularyStatus? { statuses[key] }

    // MARK: Suggestions

    /// Which candidates are worth showing right now:
    /// - known / ignored → never again,
    /// - learning / saved → always (spaced re-exposure),
    /// - never seen before → only if difficult enough.
    func suggestions(from candidates: [VocabularyCandidate], minimumDifficulty: Double, limit: Int) -> [VocabularyCandidate] {
        let filtered = candidates.filter { candidate in
            switch statuses[candidate.key] {
            case .known, .ignored: return false
            case .learning, .unknown: return true
            case nil: return candidate.difficulty >= minimumDifficulty
            }
        }
        let ranked = filtered.sorted { a, b in
            if a.kind != b.kind { return a.kind == .phrase }
            let aLearning = statuses[a.key] == .learning
            let bLearning = statuses[b.key] == .learning
            if aLearning != bLearning { return aLearning }
            return a.difficulty > b.difficulty
        }
        return Array(ranked.prefix(max(limit, 0)))
    }

    // MARK: Saving

    /// Creates or updates an item. Context (sentence + translation) is stored once, at first
    /// save, and refreshed only if the item has none — the first meeting is usually the best example.
    func setStatus(
        _ status: VocabularyStatus, for candidate: VocabularyCandidate,
        sentence: String, sentenceTranslation: String?, wordTranslation: String?, game: String?
    ) {
        if let existing = repository.item(forKey: candidate.key) {
            existing.status = status
            existing.dateLastSeen = Date()
            if existing.translation == nil { existing.translation = wordTranslation ?? candidate.builtInGloss }
            if existing.exampleSentence == nil {
                existing.exampleSentence = sentence
                existing.exampleTranslation = sentenceTranslation
            }
            if existing.sourceGame == nil { existing.sourceGame = game }
            repository.save()
        } else {
            repository.insert(VocabularyItem(
                key: candidate.key, expression: candidate.displayForm, lemma: candidate.lemma, kind: candidate.kind,
                translation: wordTranslation ?? candidate.builtInGloss, partOfSpeech: candidate.partOfSpeech,
                exampleSentence: sentence, exampleTranslation: sentenceTranslation,
                status: status, sourceGame: game))
        }
        statuses[candidate.key] = status
    }

    /// Updates counters for items that already exist (nothing new is created automatically).
    func recordSeen(_ candidates: [VocabularyCandidate]) {
        var changed = false
        for candidate in candidates {
            guard let item = repository.item(forKey: candidate.key) else { continue }
            item.timesSeen += 1
            item.dateLastSeen = Date()
            changed = true
        }
        if changed { repository.save() }
    }

    /// Called when the user picks a word or phrase in Reading Mode. Keeps one row per
    /// expression: first time → saved as "new", later times → `timesSeen` goes up.
    /// Selecting something that is already saved counts as meeting it again (and keeps the
    /// new sentence as an extra context). Nothing is created here — saving is an explicit action.
    /// Returns true when the expression is already in the vocabulary.
    @discardableResult
    func recordSelection(
        candidate: VocabularyCandidate, sentence: String, translation: String?, game: String?
    ) -> Bool {
        guard let existing = repository.item(forKey: candidate.key) else { return false }
        existing.timesSeen += 1
        existing.dateLastSeen = Date()
        if existing.translation == nil { existing.translation = translation }
        if existing.sourceGame == nil { existing.sourceGame = game }
        addContext(sentence, to: existing)
        repository.save()
        objectWillChange.send()
        return true
    }

    func isSaved(key: String) -> Bool { repository.item(forKey: key) != nil }

    /// "+ Vocabulary": saves immediately with status New. Existing items only get a new context.
    @discardableResult
    func addToVocabulary(
        candidate: VocabularyCandidate, sentence: String, sentenceTranslation: String?,
        translation: String?, game: String?, speaker: String?
    ) -> Bool {
        if let existing = repository.item(forKey: candidate.key) {
            existing.dateLastSeen = Date()
            if existing.translation == nil { existing.translation = translation }
            if existing.exampleTranslation == nil { existing.exampleTranslation = sentenceTranslation }
            addContext(sentence, to: existing)
            repository.save()
            objectWillChange.send()
            return false
        }
        let item = VocabularyItem(
            key: candidate.key, expression: candidate.displayForm, lemma: candidate.lemma, kind: candidate.kind,
            translation: translation ?? candidate.builtInGloss, partOfSpeech: candidate.partOfSpeech,
            exampleSentence: sentence, exampleTranslation: sentenceTranslation,
            status: .unknown, sourceGame: game)
        item.speaker = speaker
        repository.insert(item)
        statuses[candidate.key] = .unknown
        objectWillChange.send()
        return true
    }

    private func addContext(_ sentence: String, to item: VocabularyItem) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !item.contexts.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        if item.exampleSentence == nil { item.exampleSentence = trimmed } else { item.extraContexts.append(trimmed) }
    }

    // MARK: List management

    func update(_ item: VocabularyItem, status: VocabularyStatus) {
        item.status = status
        repository.save()
        statuses[item.key] = status
    }

    func markAddedToAnki(key: String) {
        guard let item = repository.item(forKey: key) else { return }
        item.addedToAnki = true
        repository.save()
        objectWillChange.send()
    }

    func delete(_ item: VocabularyItem) {
        let key = item.key
        repository.delete(item)
        statuses[key] = nil
    }
}
