import Foundation

/// The optional cloud translation providers that need a user-supplied API key.
/// Everything provider-specific that the UI needs (where the key lives, help links, steps)
/// is here, so Settings and Onboarding share one implementation.
enum APIProvider: String, CaseIterable, Identifiable, Sendable {
    case deepl, openai
    var id: String { rawValue }

    var displayName: String { self == .deepl ? "DeepL" : "OpenAI" }

    /// Keychain account holding this provider's key.
    var account: String { self == .deepl ? KeychainStore.deepLAccount : KeychainStore.openAIAccount }

    var keyFieldTitle: String { self == .deepl ? tr("DeepL API Key") : tr("OpenAI API Key") }

    /// Where the user creates a key. Opened in the browser; nothing is fetched by the app.
    var keyPageURL: URL {
        switch self {
        case .deepl: return URL(string: "https://www.deepl.com/pro-api")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    /// Help text lives here (not in views) so it can be revised without touching UI code;
    /// no provider limits or prices are hardcoded because those terms change.
    var helpSteps: [String] {
        switch self {
        case .deepl:
            return [
                tr("Create a DeepL account."),
                tr("Select DeepL API Free if it is available for your account."),
                tr("Open the API Keys page of your account and create or copy an authentication key."),
                tr("Paste the key here.")
            ]
        case .openai:
            return [
                tr("Create an OpenAI Platform account."),
                tr("Add billing or credit on the platform. A ChatGPT subscription does not include API usage; they are billed separately."),
                tr("Open the API keys page and create a new key."),
                tr("Paste the key here.")
            ]
        }
    }

    func service(apiKey: String?, openAIModel: String) -> any TranslationService {
        switch self {
        case .deepl: return DeepLTranslationService(apiKey: apiKey)
        case .openai: return OpenAITranslationService(apiKey: apiKey, model: openAIModel)
        }
    }
}
