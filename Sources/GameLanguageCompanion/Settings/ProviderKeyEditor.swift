import SwiftUI
import AppKit

/// API key entry for one cloud provider: secure field, save, change/remove, "Test Connection"
/// and a "How do I get a key?" help sheet. Keys go to the Keychain; the saved key is never
/// shown again (only masked dots).
struct ProviderKeyEditor: View {
    let provider: APIProvider
    @ObservedObject var settings: AppSettings
    var onChange: () -> Void = {}

    @State private var input = ""
    @State private var stored: Bool
    @State private var changing = false
    @State private var status: StatusMonitor.Item = StatusMonitor.Item(level: .unknown, text: "")
    @State private var testing = false
    @State private var showHelp = false

    init(provider: APIProvider, settings: AppSettings, onChange: @escaping () -> Void = {}) {
        self.provider = provider
        self.settings = settings
        self.onChange = onChange
        let hasKey = KeychainStore.read(account: provider.account)?.isEmpty == false
        _stored = State(initialValue: hasKey)
        _status = State(initialValue: hasKey
            ? StatusMonitor.Item(level: .unknown, text: "")
            : StatusMonitor.Item(level: .warning, text: tr("Not configured")))
    }

    private var showsField: Bool { !stored || changing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if showsField {
                    SecureField(provider.keyFieldTitle, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button(tr("Save key"), action: save)
                        .disabled(trimmedInput.isEmpty)
                    if changing {
                        Button(tr("Cancel")) { changing = false; input = "" }
                    }
                } else {
                    Text(provider.keyFieldTitle).foregroundStyle(.secondary)
                    Text("••••••••••••").font(.system(.body, design: .monospaced))
                    Spacer()
                    Button(tr("Change Key")) { changing = true }
                    Button(tr("Remove key"), role: .destructive, action: remove)
                }
            }

            HStack {
                Button(tr("Test Connection")) { Task { await test() } }
                    .disabled(testing || (!stored && trimmedInput.isEmpty))
                Button(tr("How do I get a key?")) { showHelp = true }
                if testing { ProgressView().controlSize(.small) }
                if !status.text.isEmpty { StatusLabel(item: status).font(.caption) }
            }
        }
        .sheet(isPresented: $showHelp) { ProviderHelpView(provider: provider) }
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedInput.isEmpty else { return }
        if KeychainStore.save(trimmedInput, account: provider.account) {
            input = ""
            stored = true
            changing = false
            status = StatusMonitor.Item(level: .unknown, text: tr("Key saved"))
            onChange()
        } else {
            status = StatusMonitor.Item(level: .failure, text: tr("The key could not be saved to the Keychain."))
        }
    }

    private func remove() {
        KeychainStore.delete(account: provider.account)
        stored = false
        changing = false
        status = StatusMonitor.Item(level: .warning, text: tr("Not configured"))
        onChange()
    }

    private func test() async {
        if !trimmedInput.isEmpty { save() }          // test what the user just typed
        guard let key = KeychainStore.read(account: provider.account), !key.isEmpty else {
            status = StatusMonitor.Item(level: .warning, text: tr("Not configured"))
            return
        }
        testing = true
        status = StatusMonitor.Item(level: .unknown, text: tr("Checking…"))
        let service = provider.service(apiKey: key, openAIModel: settings.openAIModel)
        do {
            try await service.testConnection()
            status = StatusMonitor.Item(level: .ok, text: tr("Connected"))
        } catch {
            status = StatusMonitor.Item(level: .failure, text: error.localizedDescription)
        }
        testing = false
        onChange()
    }
}

/// "How do I get a key?" — steps come from `APIProvider.helpSteps`.
struct ProviderHelpView: View {
    let provider: APIProvider
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("How to get a %@ key", provider.displayName)).font(.title2.bold())
            ForEach(Array(provider.helpSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.accentColor.opacity(0.2)))
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(tr("The key is stored only in the macOS Keychain on this Mac. Never share it."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(tr("Open %@ website", provider.displayName)) { NSWorkspace.shared.open(provider.keyPageURL) }
                Spacer()
                Button(tr("Close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
