import Foundation

/// Provider-independent translation interface. Implementations must only ever receive
/// recognized *text* — never screenshots.
protocol TranslationService: Sendable {
    var name: String { get }
    func translate(
        _ text: String,
        from sourceLanguage: Language,
        to targetLanguage: Language
    ) async throws -> TranslationResult

    /// Translates only `selection`, using the whole dialogue (`context`) to pick the right meaning.
    /// Providers without context support translate the selection alone.
    func translateSelection(
        selection: String,
        context: String,
        from sourceLanguage: Language,
        to targetLanguage: Language
    ) async throws -> TranslationResult

    /// Translates one dialogue line for live subtitles. `previous` are the lines before it, so providers
    /// that understand context can keep names, tone and pronouns consistent.
    func translateDialogue(
        _ text: String,
        previous: [String],
        from sourceLanguage: Language,
        to targetLanguage: Language
    ) async throws -> TranslationResult

    /// Verifies that the provider is usable (for cloud providers: that the API key works).
    /// Free/local providers have nothing to verify, so the default does nothing.
    func testConnection() async throws
}

extension TranslationService {
    func testConnection() async throws {}

    func translateSelection(
        selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language
    ) async throws -> TranslationResult {
        try await translate(selection, from: sourceLanguage, to: targetLanguage)
    }

    func translateDialogue(
        _ text: String, previous: [String], from sourceLanguage: Language, to targetLanguage: Language
    ) async throws -> TranslationResult {
        try await translate(text, from: sourceLanguage, to: targetLanguage)
    }
}

/// Optional capability: a short grammar/meaning explanation (needs an AI provider).
protocol ExplanationProviding: Sendable {
    func explain(selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> String
}

/// Tries providers in order and returns the first success.
struct FallbackTranslationService: TranslationService {
    let providers: [any TranslationService]
    var name: String { providers.map(\.name).joined(separator: " → ") }

    func translate(_ text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        var failures: [String] = []
        for provider in providers {
            do {
                return try await provider.translate(text, from: sourceLanguage, to: targetLanguage)
            } catch {
                failures.append("\(provider.name): \(error.localizedDescription)")
            }
        }
        throw TranslationError.allFailed(failures)
    }

    func translateDialogue(_ text: String, previous: [String], from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        var failures: [String] = []
        for provider in providers {
            do {
                return try await provider.translateDialogue(text, previous: previous, from: sourceLanguage, to: targetLanguage)
            } catch {
                failures.append("\(provider.name): \(error.localizedDescription)")
            }
        }
        throw TranslationError.allFailed(failures)
    }

    func translateSelection(selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        var failures: [String] = []
        for provider in providers {
            do {
                return try await provider.translateSelection(selection: selection, context: context,
                                                             from: sourceLanguage, to: targetLanguage)
            } catch {
                failures.append("\(provider.name): \(error.localizedDescription)")
            }
        }
        throw TranslationError.allFailed(failures)
    }
}

/// Builds the provider chain for the current settings. The default chain is free and local;
/// DeepL / OpenAI are opt-in and always fall back to the free providers.
@MainActor
enum TranslationServiceFactory {
    static func make(settings: AppSettings) -> any TranslationService {
        let apple = AppleTranslationService()
        let local = LocalTranslationService(baseURL: URL(string: settings.libreTranslateURL))
        switch settings.translationProvider {
        case .apple:
            return apple
        case .libreTranslate:
            return local
        case .automatic:
            return FallbackTranslationService(providers: [apple, local])
        case .deepl, .openai:
            // Cloud providers are opt-in and always fall back to the free ones.
            guard let cloud = settings.translationProvider.apiProvider else { return apple }
            let key = KeychainStore.read(account: cloud.account)
            return FallbackTranslationService(
                providers: [cloud.service(apiKey: key, openAIModel: settings.openAIModel), apple, local])
        }
    }
}
