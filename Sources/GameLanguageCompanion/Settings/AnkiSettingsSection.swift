import SwiftUI

/// Anki options shared by Settings and the Anki page. Rows only; wrap in a Form/Section.
struct AnkiSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: StatusMonitor

    @State private var message = ""
    @State private var models: [String] = []
    @State private var decks: [String] = []
    @State private var testing = false

    var body: some View {
        Group {
            Toggle(tr("Enable Anki integration"), isOn: $settings.ankiEnabled)
            if settings.ankiEnabled {
                HStack {
                    Text(tr("Connection status")).foregroundStyle(.secondary)
                    Spacer()
                    StatusLabel(item: status.anki)
                }
                TextField(tr("AnkiConnect URL"), text: $settings.ankiURL)
                HStack {
                    TextField(tr("Deck"), text: $settings.ankiDeck)
                    menu(items: decks, binding: $settings.ankiDeck)
                }
                Picker(tr("Card style"), selection: $settings.ankiCardStyle) {
                    ForEach(AnkiCardStyle.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    TextField(tr("Basic note type"), text: $settings.ankiBasicModel)
                    menu(items: models, binding: $settings.ankiBasicModel)
                }
                HStack {
                    TextField(tr("Cloze note type"), text: $settings.ankiClozeModel)
                    menu(items: models, binding: $settings.ankiClozeModel)
                }
                HStack {
                    Button(tr("Test Connection")) { Task { await test() } }.disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text(tr("Anki must be running with the AnkiConnect add-on. If your Anki is localized, use “Test Connection” and pick the note types from the menus."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: settings.ankiEnabled) {
            if settings.ankiEnabled { await load(silent: true) }
        }
    }

    @ViewBuilder
    private func menu(items: [String], binding: Binding<String>) -> some View {
        if !items.isEmpty {
            Menu(tr("Choose")) {
                ForEach(items, id: \.self) { item in
                    Button(item) { binding.wrappedValue = item }
                }
            }
            .fixedSize()
        }
    }

    private func test() async {
        testing = true
        await load(silent: false)
        await status.refresh(settings: settings, force: true)
        testing = false
    }

    private func load(silent: Bool) async {
        guard let service = AnkiConnectService(urlString: settings.ankiURL) else {
            if !silent { message = tr("Invalid URL") }
            return
        }
        if !silent { message = tr("Connecting…") }
        do {
            models = try await service.availableModels()
            decks = try await service.availableDecks()
            if !silent { message = tr("Connected — %d decks, %d note types", decks.count, models.count) }
        } catch {
            models = []
            decks = []
            if !silent { message = error.localizedDescription }
        }
    }
}
