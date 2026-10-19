import Foundation
import SwiftData

@MainActor
final class HistoryRepository {
    private let context: ModelContext
    private let unsavedLimit = 500

    init(container: ModelContainer) { context = container.mainContext }

    @discardableResult
    func record(original: String, speaker: String?, translation: String?, game: String?, provider: String?) -> DialogueRecord {
        let record = DialogueRecord(original: original, speaker: speaker, translation: translation,
                                    game: game, provider: provider)
        context.insert(record)
        save()
        pruneUnsaved()
        return record
    }

    func setSaved(_ id: UUID, saved: Bool) {
        guard let record = fetch(id) else { return }
        record.isSaved = saved
        save()
    }

    func updateTranslation(_ id: UUID, translation: String, provider: String?) {
        guard let record = fetch(id) else { return }
        record.translation = translation
        record.provider = provider
        save()
    }

    func delete(_ record: DialogueRecord) {
        context.delete(record)
        save()
    }

    private func fetch(_ id: UUID) -> DialogueRecord? {
        var descriptor = FetchDescriptor<DialogueRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Keeps the history from growing forever; sentences you explicitly saved are never pruned.
    private func pruneUnsaved() {
        let descriptor = FetchDescriptor<DialogueRecord>(
            predicate: #Predicate { $0.isSaved == false },
            sortBy: [SortDescriptor(\.date, order: .forward)])
        guard let unsaved = try? context.fetch(descriptor), unsaved.count > unsavedLimit else { return }
        for record in unsaved.prefix(unsaved.count - unsavedLimit) { context.delete(record) }
        save()
    }

    private func save() {
        do { try context.save() } catch { NSLog("HistoryRepository save failed: \(error)") }
    }
}
