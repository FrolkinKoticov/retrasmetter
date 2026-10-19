import Foundation
import SwiftData

/// Thin SwiftData wrapper. Everything stays in a local store on this Mac.
@MainActor
final class VocabularyRepository {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func allItems() -> [VocabularyItem] {
        (try? context.fetch(FetchDescriptor<VocabularyItem>())) ?? []
    }

    func item(forKey key: String) -> VocabularyItem? {
        var descriptor = FetchDescriptor<VocabularyItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func insert(_ item: VocabularyItem) {
        context.insert(item)
        save()
    }

    func delete(_ item: VocabularyItem) {
        context.delete(item)
        save()
    }

    func save() {
        do { try context.save() } catch { NSLog("VocabularyRepository save failed: \(error)") }
    }
}
