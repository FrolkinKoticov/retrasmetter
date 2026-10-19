import SwiftUI
import SwiftData

struct HomeView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: StatusMonitor
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var monitor: DialogueMonitor
    @ObservedObject var reading: ReadingModeController

    @Query private var items: [VocabularyItem]
    @Query private var records: [DialogueRecord]

    private var wordsToday: Int {
        items.filter { Calendar.current.isDateInToday($0.dateFirstSeen) && $0.status != .ignored }.count
    }
    private var cardsAdded: Int { items.filter(\.addedToAnki).count }

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Retrasmetter").font(.largeTitle.bold())

                monitoringCard

                HStack {
                    Button {
                        appState.reading.toggle()
                    } label: {
                        Label(reading.isActive ? tr("Exit Reading Mode") : tr("Activate Reading Mode"),
                              systemImage: "text.viewfinder")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        appState.toggleMonitoring()
                    } label: {
                        Label(monitor.state == .paused || !monitor.isMonitoring ? tr("Resume Monitoring") : tr("Pause Monitoring"),
                              systemImage: monitor.isMonitoring ? "pause.circle" : "play.circle")
                            .padding(.vertical, 8)
                    }
                    .controlSize(.large)
                }
                Text(tr("Hotkey: %@", settings.hotkeyDescription)).font(.caption).foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    card(title: tr("Current game")) {
                        TextField(tr("Game name (optional)"), text: $settings.gameNameOverride,
                                  prompt: Text(appState.gameContext.currentGameName() ?? tr("Defaults to the frontmost app")))
                            .textFieldStyle(.roundedBorder)
                        Text("\(settings.sourceLanguage.displayName) → \(settings.targetLanguage.displayName)")
                            .foregroundStyle(.secondary)
                    }
                    card(title: tr("Translation Provider")) {
                        Text(settings.translationProvider.shortName).font(.title3.weight(.semibold))
                        StatusLabel(item: status.translation).font(.callout)
                    }
                    card(title: tr("Dialogue Area")) {
                        if let region = settings.captureRegion {
                            StatusLabel(item: .init(level: .ok, text: tr("Configured"))).font(.callout)
                            Text(region.summary).font(.caption).foregroundStyle(.secondary)
                        } else {
                            StatusLabel(item: .init(level: .warning, text: tr("Not configured"))).font(.callout)
                        }
                        Button(tr("Select…")) { appState.selectCaptureArea() }.controlSize(.small)
                    }
                    card(title: tr("Screen Recording")) {
                        StatusLabel(item: permissions.hasScreenRecordingAccess
                                    ? .init(level: .ok, text: tr("Permission granted"))
                                    : .init(level: .warning, text: tr("Permission required"))).font(.callout)
                        if !permissions.hasScreenRecordingAccess {
                            Button(tr("Open System Settings")) { permissions.openSystemSettings() }.controlSize(.small)
                        }
                    }
                    card(title: "Anki") {
                        StatusLabel(item: status.anki).font(.callout)
                    }
                }

                Text(tr("Today")).font(.headline).padding(.top, 6)
                HStack(spacing: 14) {
                    stat(value: wordsToday, label: tr("Words learned today"))
                    stat(value: cardsAdded, label: tr("Cards added to Anki"))
                    stat(value: records.count, label: tr("Dialogues translated"))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await status.refresh(settings: settings) }
    }

    private var monitoringCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Monitoring")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                StatusLabel(item: .init(level: monitorLevel, text: monitor.statusText)).font(.callout)
            }
            if let dialogue = monitor.dialogue {
                Label(tr("Dialogue detected"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
                if let speaker = dialogue.speaker {
                    Text(speaker).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(dialogue.fullText).font(.body).lineLimit(4).textSelection(.enabled)
            } else {
                Text(tr("No dialogue detected yet.")).font(.callout).foregroundStyle(.secondary)
            }
            Button(tr("Translate Entire Sentence")) { appState.translateCurrentDialogue(fromMenu: true) }
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var monitorLevel: StatusMonitor.Level {
        switch monitor.state {
        case .active: return .ok
        case .starting, .paused, .stopped: return .warning
        case .failed: return .failure
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
