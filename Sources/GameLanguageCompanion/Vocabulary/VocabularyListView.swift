import SwiftUI
import SwiftData

enum VocabularyFilter: String, CaseIterable, Identifiable {
    case all, new, learning, known, anki
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return tr("All")
        case .new: return tr("New")
        case .learning: return tr("Learning")
        case .known: return tr("Known")
        case .anki: return tr("Anki")
        }
    }
}

/// The vocabulary manager: searchable table with status filters and bulk actions.
struct VocabularyListView: View {
    @ObservedObject var settings: AppSettings      // observed so labels re-render on language change
    let onAddToAnki: (VocabularyItem) async -> String
    @EnvironmentObject private var vocabulary: VocabularyManager
    @Query(sort: \VocabularyItem.dateLastSeen, order: .reverse) private var items: [VocabularyItem]

    @State private var filter: VocabularyFilter = .all
    @State private var search = ""
    @State private var selection = Set<VocabularyItem.ID>()
    @State private var feedback = ""

    private var filtered: [VocabularyItem] {
        items.filter { item in
            matches(filter, item) &&
            (search.isEmpty
             || item.expression.localizedCaseInsensitiveContains(search)
             || (item.translation?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private var selectedItems: [VocabularyItem] { items.filter { selection.contains($0.id) } }

    private func matches(_ filter: VocabularyFilter, _ item: VocabularyItem) -> Bool {
        switch filter {
        case .all: return true
        case .new: return item.status == .unknown
        case .learning: return item.status == .learning
        case .known: return item.status == .known
        case .anki: return item.addedToAnki
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $filter) {
                    ForEach(VocabularyFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                TextField(tr("Search"), text: $search).textFieldStyle(.roundedBorder)
            }
            .padding(10)

            actionBar

            Table(filtered, selection: $selection) {
                TableColumn(tr("Expression")) { item in
                    Text(item.expression).font(.headline)
                }
                TableColumn(tr("Translation")) { item in
                    Text(item.translation ?? "").foregroundStyle(.secondary)
                }
                TableColumn(tr("Status")) { item in
                    Text(item.status.title)
                }
                .width(min: 70, ideal: 90)
                TableColumn(tr("Times Seen")) { item in
                    Text("\(item.timesSeen)")
                }
                .width(min: 60, ideal: 80)
                TableColumn(tr("Source Game")) { item in
                    Text(item.sourceGame ?? "")
                }
                TableColumn(tr("Date Added")) { item in
                    Text(item.dateFirstSeen, format: .dateTime.day().month().year().locale(L10n.locale))
                }
                .width(min: 80, ideal: 100)
                TableColumn(tr("Anki")) { item in
                    Text(item.addedToAnki ? tr("Yes") : tr("No"))
                        .foregroundStyle(item.addedToAnki ? Color.green : Color.secondary)
                }
                .width(min: 50, ideal: 60)
            }
            .overlay {
                if filtered.isEmpty {
                    Text(items.isEmpty ? tr("Words you save from the overlay appear here.") : tr("No matches."))
                        .foregroundStyle(.secondary)
                }
            }

            if selectedItems.count == 1, let item = selectedItems.first {
                Divider()
                VocabularyDetailView(item: item, settings: settings,
                                     onAddToAnki: { feedback = await onAddToAnki($0) },
                                     onDelete: { delete() })
                    .frame(maxHeight: 240)
            }

            if !feedback.isEmpty {
                Text(feedback).font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button(tr("Mark as Known")) { setStatus(.known) }
            Button(tr("Learn")) { setStatus(.learning) }
            Button(tr("Ignore")) { setStatus(.ignored) }
            Button(tr("Add to Anki")) { addToAnki() }
                .disabled(!settings.ankiEnabled)
            Spacer()
            Button(tr("Delete"), role: .destructive) { delete() }
        }
        .controlSize(.small)
        .disabled(selection.isEmpty)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func setStatus(_ status: VocabularyStatus) {
        for item in selectedItems { vocabulary.update(item, status: status) }
    }

    private func delete() {
        for item in selectedItems { vocabulary.delete(item) }
        selection.removeAll()
    }

    private func addToAnki() {
        let targets = selectedItems
        Task {
            var last = ""
            for item in targets { last = await onAddToAnki(item) }
            feedback = last
        }
    }
}
