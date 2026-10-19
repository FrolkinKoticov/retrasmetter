import SwiftUI
import SwiftData

struct AnkiPageView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: StatusMonitor
    @Query private var items: [VocabularyItem]

    var body: some View {
        Form {
            Section(tr("Anki (via AnkiConnect, localhost)")) {
                AnkiSettingsSection(settings: settings, status: status)
            }
            if settings.ankiEnabled {
                Section(tr("Cards")) {
                    LabeledContent(tr("Cards added to Anki"), value: "\(items.filter(\.addedToAnki).count)")
                }
            }
        }
        .formStyle(.grouped)
        .task { await status.refresh(settings: settings) }
    }
}
