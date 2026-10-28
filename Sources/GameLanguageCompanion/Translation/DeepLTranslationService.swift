import Foundation

extension Language {
    /// DeepL source-language code ("EN", "RU", …).
    var deepLSource: String { code.uppercased() }
    /// DeepL target-language code; English targets need a regional variant.
    var deepLTarget: String { code == "en" ? "EN-US" : code.uppercased() }
}

/// OPTIONAL cloud provider. Never required and never part of the default setup.
/// Only the recognized text is sent — never a screenshot. The API key lives in the Keychain.
struct DeepLTranslationService: TranslationService {
    let name = "DeepL"
    let apiKey: String?

    func translate(_ text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        try await translate(text, context: nil, from: sourceLanguage, to: targetLanguage)
    }

    /// DeepL's `context` parameter is not translated, but it steers the meaning of `selection`.
    func translateSelection(selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        try await translate(selection, context: context, from: sourceLanguage, to: targetLanguage)
    }

    /// The previous lines go into DeepL's `context` parameter (not billed, not translated).
    func translateDialogue(_ text: String, previous: [String], from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let context = previous.suffix(3).joined(separator: " ")
        return try await translate(text, context: context.isEmpty ? nil : context, from: sourceLanguage, to: targetLanguage)
    }

    private func translate(_ text: String, context: String?, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }

        var request = try makeRequest(path: "/v2/translate")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "text": [trimmed],
            "source_lang": sourceLanguage.deepLSource,
            "target_lang": targetLanguage.deepLTarget
        ]
        if let context, !context.isEmpty, context != trimmed { body["context"] = context }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = object["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw TranslationError.providerFailed(tr("Unexpected response from DeepL."))
        }
        return TranslationResult(sourceText: trimmed, translatedText: translated,
                                 sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: name)
    }

    /// Asks DeepL for the account's usage: succeeds only with a valid key, costs no characters.
    func testConnection() async throws {
        var request = try makeRequest(path: "/v2/usage")
        request.httpMethod = "GET"
        _ = try await send(request)
    }

    // MARK: Helpers

    private func makeRequest(path: String) throws -> URLRequest {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw TranslationError.unavailable(tr("No DeepL API key is set. Add one in Settings → Translation."))
        }
        // Free-plan keys end in ":fx" and use a different host.
        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw TranslationError.unavailable(tr("The DeepL address is invalid."))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.providerFailed(tr("DeepL is not reachable. Check your internet connection."))
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.providerFailed(tr("Unexpected response from DeepL."))
        }
        switch http.statusCode {
        case 200: return data
        case 400: throw TranslationError.providerFailed(tr("DeepL does not support this language pair or request."))
        case 403: throw TranslationError.providerFailed(tr("DeepL rejected the API key. Check it in Settings → Translation."))
        case 456: throw TranslationError.providerFailed(tr("The DeepL monthly character quota is used up."))
        case 429: throw TranslationError.providerFailed(tr("DeepL: too many requests. Try again in a moment."))
        case 500...599: throw TranslationError.providerFailed(tr("DeepL is having problems right now (HTTP %d). Try again later.", http.statusCode))
        default: throw TranslationError.providerFailed(tr("DeepL error (HTTP %d).", http.statusCode))
        }
    }
}
