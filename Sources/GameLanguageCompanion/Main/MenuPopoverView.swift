import SwiftUI
import AppKit

/// Compact menu bar popover (MenuBarExtra with `.window` style).
struct MenuPopoverView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: StatusMonitor
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var monitor: DialogueMonitor
    @ObservedObject var reading: ReadingModeController
    @ObservedObject var profiles: ProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Retrasmetter").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Current game")).font(.caption).foregroundStyle(.secondary)
                Text(appState.gameContext.currentGameName() ?? "—").font(.body.weight(.medium))
                Text("\(settings.sourceLanguage.displayName) → \(settings.targetLanguage.displayName)")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Button {
                appState.dismissMenuWindow()
                appState.reading.toggle()
            } label: {
                Label(reading.isActive ? tr("Exit Reading Mode") : tr("Activate Reading Mode"),
                      systemImage: "text.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Toggle(tr("Live subtitles"), isOn: Binding(
                get: { appState.subtitles.isEnabled },
                set: { _ in appState.toggleSubtitles() }))
                .toggleStyle(.switch).controlSize(.small)

            Button {
                appState.toggleMonitoring()
            } label: {
                Label(monitor.isMonitoring ? tr("Pause Monitoring") : tr("Resume Monitoring"),
                      systemImage: monitor.isMonitoring ? "pause.circle" : "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)

            Text(tr("Hotkey: %@", settings.hotkeyDescription)).font(.caption).foregroundStyle(.secondary)

            if !permissions.hasScreenRecordingAccess {
                Button {
                    if !permissions.requestAccess() { permissions.openSystemSettings() }
                } label: {
                    Label(tr("Grant Screen Recording Access…"), systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.link)
            }

            Divider()

            row(tr("Select Dialogue Area"), "viewfinder") { appState.selectCaptureArea() }
            row(tr("Games"), "gamecontroller") { appState.showMain(.games) }
            row(tr("Vocabulary"), "character.book.closed") { appState.showMain(.vocabulary) }
            row(tr("History"), "clock.arrow.circlepath") { appState.showMain(.history) }
            row(tr("Settings"), "gearshape") { appState.showMain(.settings) }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                statusRow(tr("Monitoring"), .init(level: monitor.state == .active ? .ok : .warning, text: monitor.statusText))
                statusRow(tr("OCR"), permissions.hasScreenRecordingAccess
                          ? .init(level: .ok, text: tr("Ready"))
                          : .init(level: .warning, text: tr("Permission required")))
                statusRow(tr("Translation"), .init(level: status.translation.level,
                                                   text: settings.translationProvider.shortName + " · " + status.translation.text))
                statusRow("Anki", status.anki)
            }
            .font(.caption)

            Divider()
            row(tr("Quit"), "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .task { await status.refresh(settings: settings) }
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            appState.dismissMenuWindow()
            action()
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func statusRow(_ title: String, _ item: StatusMonitor.Item) -> some View {
        HStack {
            Text(title + ":").foregroundStyle(.secondary)
            StatusLabel(item: item).lineLimit(1)
        }
    }
}
