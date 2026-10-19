import SwiftUI
import SwiftData

/// Details of one saved expression: all contexts, games, counters and quick actions.
struct VocabularyDetailView: View {
    let item: VocabularyItem
    @ObservedObject var settings: AppSettings
    let onAddToAnki: (VocabularyItem) async -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var vocabulary: VocabularyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.expression).font(.title2.bold())
                    Button { Pronouncer.shared.speak(item.expression, language: settings.sourceLanguage) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless).help(tr("Pronounce"))
                    Spacer()
                    Text(item.status.title).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
                if let translation = item.translation {
                    Text(translation).font(.title3)
                }

                Text(tr("Contexts")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(Array(item.contexts.enumerated()), id: \.offset) { index, sentence in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(index + 1). \(sentence)").textSelection(.enabled)
                        if index == 0, let translation = item.exampleTranslation {
                            Text(translation).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                if item.contexts.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if let game = item.sourceGame { Label(game, systemImage: "gamecontroller") }
                    Label(tr("Times Seen") + ": \(item.timesSeen)", systemImage: "eye")
                }
                .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button(tr("Mark as Learning")) { vocabulary.update(item, status: .learning) }
                    Button(tr("Mark as Known")) { vocabulary.update(item, status: .known) }
                    Button(tr("Add to Anki")) { Task { await onAddToAnki(item) } }
                        .disabled(!settings.ankiEnabled)
                    Spacer()
                    Button(tr("Delete"), role: .destructive, action: onDelete)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
