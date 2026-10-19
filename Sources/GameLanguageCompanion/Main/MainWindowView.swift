import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, games, vocabulary, history, anki, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return tr("Home")
        case .games: return tr("Games")
        case .vocabulary: return tr("Vocabulary")
        case .history: return tr("History")
        case .anki: return "Anki"
        case .settings: return tr("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .games: return "gamecontroller"
        case .vocabulary: return "character.book.closed"
        case .history: return "clock.arrow.circlepath"
        case .anki: return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

/// Which page the main window shows; lives outside the window so menus can navigate it.
@MainActor
final class NavigationModel: ObservableObject {
    @Published var selection: SidebarItem? = .home
}

/// The real application window: sidebar + detail.
struct MainWindowView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: NavigationModel

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detail
                .navigationTitle((navigation.selection ?? .home).title)
        }
        .environmentObject(appState.vocabulary)
        .modelContainer(appState.container)
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .home {
        case .home:
            HomeView(appState: appState, settings: settings, status: appState.status, permissions: appState.permissions,
                     monitor: appState.monitor, reading: appState.reading)
        case .games:
            GamesView(appState: appState, settings: settings, profiles: appState.profiles, monitor: appState.monitor)
        case .vocabulary:
            VocabularyListView(settings: settings, onAddToAnki: { await appState.addToAnki($0) })
        case .history:
            HistoryView(history: appState.history, settings: settings)
        case .anki:
            AnkiPageView(appState: appState, settings: settings, status: appState.status)
        case .settings:
            SettingsView(appState: appState)
        }
    }
}
