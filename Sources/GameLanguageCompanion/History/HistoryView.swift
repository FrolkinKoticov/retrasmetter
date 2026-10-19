import SwiftUI
import SwiftData
import AppKit

struct HistoryView: View {
    let history: HistoryRepository
    @ObservedObject var settings: AppSettings      // observed so labels re-render on language change
    @EnvironmentObject private var vocabulary: VocabularyManager

    @Query(sort: \DialogueRecord.date, order: .reverse) private var records: [DialogueRecord]
    @State private var savedOnly = false
    @State private var search = ""
    @State private var selectedID: UUID?

    private var filtered: [DialogueRecord] {
        records.filter { record in
            (!savedOnly || record.isSaved) &&
            (search.isEmpty
             || record.original.localizedCaseInsensitiveContains(search)
             || (record.translation?.localizedCaseInsensitiveContains(search) ?? false)
             || (record.game?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private var selected: DialogueRecord? { records.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            listPane.frame(minWidth: 280, idealWidth: 340)
            detailPane.frame(minWidth: 320, maxWidth: .infinity)
        }
    }

    // MARK: List

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $savedOnly) {
                    Text(tr("All")).tag(false)
                    Text(tr("Saved")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                TextField(tr("Search"), text: $search).textFieldStyle(.roundedBorder)
            }
            .padding(10)

            List(filtered, selection: $selectedID) { record in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let game = record.game {
                            Text(game).font(.caption.weight(.semibold))
                        }
                        Text(record.date, format: .dateTime.day().month().hour().minute().locale(L10n.locale))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if record.isSaved { Image(systemName: "bookmark.fill").font(.caption) }
                    }
                    Text(record.original).lineLimit(2)
                    if let translation = record.translation {
                        Text(translation).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
                .tag(record.id)
                .contextMenu {
                    Button(tr("Copy original")) { copy(record.original) }
                    if let translation = record.translation { Button(tr("Copy translation")) { copy(translation) } }
                    Divider()
                    Button(tr("Delete"), role: .destructive) { history.delete(record) }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    Text(records.isEmpty ? tr("Translated dialogue will appear here.") : tr("No matches."))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailPane: some View {
        if let record = selected {
            HistoryDetailView(record: record, history: history, settings: settings, vocabulary: vocabulary)
                .id(record.id)
        } else {
            Text(tr("Select a dialogue to see details."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HistoryDetailView: View {
    let record: DialogueRecord
    let history: HistoryRepository
    @ObservedObject var settings: AppSettings
    @ObservedObject var vocabulary: VocabularyManager
    @State private var candidates: [VocabularyCandidate] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let game = record.game { Text(game).font(.headline) }
                        Text(record.date, format: .dateTime.day().month().year().hour().minute().locale(L10n.locale))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        history.setSaved(record.id, saved: !record.isSaved)
                    } label: {
                        Image(systemName: record.isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.borderless)
                }

                block(title: tr("ORIGINAL"), text: record.original, speaker: record.speaker)
                if let translation = record.translation {
                    block(title: tr("TRANSLATION"), text: translation, speaker: nil)
                }

                HStack {
                    Button(tr("Copy original")) { copy(record.original) }
                    if let translation = record.translation {
                        Button(tr("Copy translation")) { copy(translation) }
                    }
                }
                .controlSize(.small)

                if !candidates.isEmpty {
                    Divider()
                    Text(tr("Vocabulary")).font(.headline)
                    ForEach(candidates) { candidate in
                        HStack {
                            Text(candidate.displayForm).font(.body.weight(.medium))
                            if let gloss = candidate.builtInGloss {
                                Text(gloss).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let status = vocabulary.status(forKey: candidate.key) {
                                Text(status.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            let analyzer = NaturalLanguageAnalyzer(
                language: settings.sourceLanguage,
                phraseDetector: EnglishPhraseDetector(detectGenericPhrasalVerbs: settings.detectGenericPhrasalVerbs))
            if let analysis = try? await analyzer.analyze(sentence: record.original) {
                candidates = analysis.candidates
                    .filter { $0.kind == .phrase || $0.difficulty >= settings.minimumDifficulty }
                    .prefix(12).map { $0 }
            }
        }
    }

    private func block(title: String, text: String, speaker: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if let speaker { Text(speaker).font(.caption.weight(.semibold)) }
            Text(text).font(.title3).textSelection(.enabled)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
