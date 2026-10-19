import Foundation

/// Live status of the optional integrations (translation provider, Anki), shown on the Home
/// screen, in the menu bar popover and in Settings. Checks are cached for a short time so
/// opening the popover repeatedly does not hit a cloud API every time.
@MainActor
final class StatusMonitor: ObservableObject {
    enum Level { case ok, warning, failure, unknown }

    struct Item: Equatable {
        var level: Level
        var text: String
        static let unknown = Item(level: .unknown, text: "…")
    }

    @Published private(set) var translation = Item.unknown
    @Published private(set) var anki = Item.unknown

    private var lastRefresh: Date?
    private var lastSignature = ""

    func refresh(settings: AppSettings, force: Bool = false) async {
        let provider = settings.translationProvider
        let keyLength = provider.apiProvider.flatMap { KeychainStore.read(account: $0.account)?.count } ?? 0
        let signature = [provider.rawValue, String(keyLength), settings.openAIModel,
                         String(settings.ankiEnabled), settings.ankiURL].joined(separator: "|")
        if !force, signature == lastSignature, let last = lastRefresh, Date().timeIntervalSince(last) < 120 { return }
        lastSignature = signature
        lastRefresh = Date()

        async let translationItem = checkTranslation(settings: settings)
        async let ankiItem = checkAnki(settings: settings)
        translation = await translationItem
        anki = await ankiItem
    }

    private func checkTranslation(settings: AppSettings) async -> Item {
        guard let api = settings.translationProvider.apiProvider else {
            return Item(level: .ok, text: tr("Ready"))
        }
        guard let key = KeychainStore.read(account: api.account), !key.isEmpty else {
            return Item(level: .warning, text: tr("Not configured"))
        }
        do {
            try await api.service(apiKey: key, openAIModel: settings.openAIModel).testConnection()
            return Item(level: .ok, text: tr("Connected"))
        } catch {
            return Item(level: .failure, text: error.localizedDescription)
        }
    }

    private func checkAnki(settings: AppSettings) async -> Item {
        guard settings.ankiEnabled else { return Item(level: .unknown, text: tr("Off")) }
        guard let service = AnkiConnectService(urlString: settings.ankiURL) else {
            return Item(level: .failure, text: tr("Invalid URL"))
        }
        return await service.isAvailable()
            ? Item(level: .ok, text: tr("Connected"))
            : Item(level: .warning, text: tr("Not detected"))
    }
}
