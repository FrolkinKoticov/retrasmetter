import SwiftUI

/// Game profiles: window, dialogue area, languages, test and activate.
struct GamesView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var monitor: DialogueMonitor

    @State private var selectedID: UUID?
    @State private var newName = ""
    @State private var testText: String?
    @State private var testing = false
    @State private var showPreview = false
    @State private var pickedWindow: UInt32?

    var body: some View {
        HSplitView {
            list.frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
            detail.frame(minWidth: 400, maxWidth: .infinity)
        }
        .onAppear { selectedID = selectedID ?? profiles.activeProfileID ?? profiles.profiles.first?.id }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(profiles.profiles) { profile in
                    HStack {
                        Image(systemName: profile.id == profiles.activeProfileID ? "checkmark.circle.fill" : "gamecontroller")
                            .foregroundStyle(profile.id == profiles.activeProfileID ? Color.green : Color.secondary)
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text("\(profile.sourceLanguageCode.uppercased()) → \(profile.targetLanguageCode.uppercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(profile.id)
                }
            }
            Divider()
            HStack {
                TextField(tr("New game"), text: $newName).textFieldStyle(.roundedBorder)
                Button {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let profile = profiles.createProfile(name: name)
                    selectedID = profile.id
                    newName = ""
                } label: { Image(systemName: "plus") }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let profile = profiles.profiles.first(where: { $0.id == selectedID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(profile.name).font(.title.bold())
                        if profile.id == profiles.activeProfileID {
                            Text(tr("Active")).font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.25)))
                        }
                    }

                    GroupBox(tr("Game window")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.windowDescription ?? tr("No window selected"))
                                .foregroundStyle(profile.windowDescription == nil ? .secondary : .primary)
                            WindowPickerView(selectedID: $pickedWindow) { window in
                                profiles.attach(window: window, to: profile.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }

                    GroupBox(tr("Dialogue area")) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let region = profile.region {
                                Text(region.summary)
                                Text(profile.relativeRegion != nil
                                     ? tr("The area follows the game window when it moves.")
                                     : tr("Not tied to a window: select a game window, then the area again."))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(tr("Not configured")).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button(tr("Edit Dialogue Area")) {
                                    profiles.activate(profile.id)
                                    appState.selectCaptureArea()
                                }
                                Button(tr("Test OCR")) { runTest(profile) }.disabled(testing)
                                if testing { ProgressView().controlSize(.small) }
                            }
                            if let testText {
                                Text(testText).font(.callout).textSelection(.enabled)
                                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            }
                            DisclosureGroup(tr("Debug preview"), isExpanded: $showPreview) {
                                if let image = monitor.lastFrame {
                                    Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 160)
                                    Text(tr("Kept in memory only, never saved."))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(tr("No frame yet.")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }

                    GroupBox(tr("Languages")) {
                        HStack {
                            Picker(tr("Game language"), selection: binding(profile, \.sourceLanguageCode)) {
                                ForEach(Language.all) { Text($0.displayName).tag($0.code) }
                            }
                            Picker(tr("Translate Into"), selection: binding(profile, \.targetLanguageCode)) {
                                ForEach(Language.all) { Text($0.displayName).tag($0.code) }
                            }
                        }
                        .padding(4)
                    }

                    Toggle(tr("Monitor this game"), isOn: binding(profile, \.monitoringEnabled))

                    HStack {
                        Button(tr("Activate")) { profiles.activate(profile.id) }
                            .buttonStyle(.borderedProminent)
                            .disabled(profile.id == profiles.activeProfileID)
                        Button(tr("Delete"), role: .destructive) {
                            profiles.delete(profile.id)
                            selectedID = profiles.activeProfileID ?? profiles.profiles.first?.id
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller").font(.system(size: 40)).foregroundStyle(.secondary)
                Text(tr("Add a game on the left to set up its dialogue area."))
                    .foregroundStyle(.secondary)
                Button(tr("Select Dialogue Area")) { appState.selectCaptureArea() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func binding<T>(_ profile: GameProfile, _ keyPath: WritableKeyPath<GameProfile, T>) -> Binding<T> {
        Binding(
            get: { profiles.profiles.first(where: { $0.id == profile.id })?[keyPath: keyPath] ?? profile[keyPath: keyPath] },
            set: { value in
                guard var updated = profiles.profiles.first(where: { $0.id == profile.id }) else { return }
                updated[keyPath: keyPath] = value
                profiles.update(updated)
            })
    }

    private func runTest(_ profile: GameProfile) {
        profiles.activate(profile.id)
        testing = true
        testText = nil
        Task {
            await monitor.refreshNow()
            testing = false
            testText = monitor.dialogue?.fullText ?? tr("No text found in the dialogue area.")
        }
    }
}
