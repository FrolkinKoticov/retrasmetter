import Foundation

/// OPTIONAL cloud provider (never the default). Only the recognized text is sent.
/// API usage is billed by OpenAI separately from any ChatGPT subscription.
struct OpenAITranslationService: TranslationService, ExplanationProviding {
    let name = "OpenAI"
    let apiKey: String?
    let model: String

    private static let base = "https://api.openai.com/v1"

    func translate(_ text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }

        var request = try makeRequest(path: "/chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let english = Locale(identifier: "en")
        let from = english.localizedString(forLanguageCode: sourceLanguage.code) ?? sourceLanguage.code
        let to = english.localizedString(forLanguageCode: targetLanguage.code) ?? targetLanguage.code
        let system = "You translate video game dialogue from \(from) to \(to). "
            + "Keep the tone, slang and personality of the speaker. Reply with the translation only, no notes or quotes."
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": trimmed]
            ]
        ] as [String: Any])

        let data = try await send(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranslationError.providerFailed(tr("Unexpected response from OpenAI."))
        }
        return TranslationResult(sourceText: trimmed, translatedText: content,
                                 sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: name)
    }

    /// Context-aware translation of a word or phrase. Asks for a small JSON object so the popup
    /// can show the normalized expression and part of speech too.
    func translateSelection(selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }

        var request = try makeRequest(path: "/chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let english = Locale(identifier: "en")
        let from = english.localizedString(forLanguageCode: sourceLanguage.code) ?? sourceLanguage.code
        let to = english.localizedString(forLanguageCode: targetLanguage.code) ?? targetLanguage.code
        let system = "You are a dictionary for a language learner reading \(from) video game dialogue. "
            + "Translate ONLY the selected text into \(to), choosing the meaning that fits the dialogue. "
            + "Reply with a JSON object: {\"translation\": short translation (up to 3 variants separated by ' / '), "
            + "\"normalized\": dictionary form of the selected expression, "
            + "\"pos\": part of speech or 'phrasal verb' / 'idiom' when relevant, "
            + "\"note\": one short sentence of explanation in \(to), or an empty string}."
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "Dialogue: \(context)\nSelected: \(trimmed)"]
            ]
        ] as [String: Any])

        let data = try await send(request)
        guard let content = try Self.messageContent(data) else {
            throw TranslationError.providerFailed(tr("Unexpected response from OpenAI."))
        }
        let object = content.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let translation = (object?["translation"] as? String) ?? content
        func clean(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        return TranslationResult(
            sourceText: trimmed, translatedText: translation,
            sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: name,
            normalizedExpression: clean(object?["normalized"]),
            partOfSpeech: clean(object?["pos"]),
            shortExplanation: clean(object?["note"]))
    }

    /// Longer explanation for the "More" button: meaning, structure, typical pattern.
    func explain(selection: String, context: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> String {
        var request = try makeRequest(path: "/chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let english = Locale(identifier: "en")
        let from = english.localizedString(forLanguageCode: sourceLanguage.code) ?? sourceLanguage.code
        let to = english.localizedString(forLanguageCode: targetLanguage.code) ?? targetLanguage.code
        let system = "You explain \(from) language to a learner whose language is \(to). "
            + "Explain the selected text as used in the dialogue in at most 70 words, in \(to): "
            + "meaning here, grammar or structure, and a common pattern if there is one. No preamble."
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "Dialogue: \(context)\nSelected: \(selection)"]
            ]
        ] as [String: Any])
        let data = try await send(request)
        guard let content = try Self.messageContent(data), !content.isEmpty else {
            throw TranslationError.providerFailed(tr("Unexpected response from OpenAI."))
        }
        return content
    }

    private static func messageContent(_ data: Data) throws -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return content
    }

    /// Listing models needs a valid key but costs nothing.
    func testConnection() async throws {
        var request = try makeRequest(path: "/models")
        request.httpMethod = "GET"
        _ = try await send(request)
    }

    // MARK: Helpers

    private func makeRequest(path: String) throws -> URLRequest {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw TranslationError.unavailable(tr("No OpenAI API key is set. Add one in Settings → Translation."))
        }
        guard let url = URL(string: Self.base + path) else {
            throw TranslationError.unavailable(tr("The OpenAI address is invalid."))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.providerFailed(tr("OpenAI is not reachable. Check your internet connection."))
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.providerFailed(tr("Unexpected response from OpenAI."))
        }
        switch http.statusCode {
        case 200: return data
        case 401: throw TranslationError.providerFailed(tr("OpenAI rejected the API key. Check it in Settings → Translation."))
        case 404: throw TranslationError.providerFailed(tr("OpenAI model “%@” was not found. Check it in Settings → Advanced.", model))
        case 429: throw TranslationError.providerFailed(tr("OpenAI: rate limit reached or no credit left. API billing is separate from a ChatGPT subscription."))
        case 500...599: throw TranslationError.providerFailed(tr("OpenAI is having problems right now (HTTP %d). Try again later.", http.statusCode))
        default: throw TranslationError.providerFailed(tr("OpenAI error (HTTP %d).", http.statusCode))
        }
    }
}
