import Foundation

/// Free, fully local fallback: a LibreTranslate-compatible server running on your own Mac
/// (for example `pip install libretranslate && libretranslate --load-only en,ru`, or the
/// official Docker image). Only the recognized text is sent, and only to localhost.
struct LocalTranslationService: TranslationService {
    let name = "Local LibreTranslate"
    let baseURL: URL?

    func translate(_ text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard let baseURL else { throw TranslationError.unavailable(tr("The local translation server URL is invalid.")) }

        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "q": trimmed, "source": sourceLanguage.code, "target": targetLanguage.code, "format": "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.providerFailed(
                tr("No local translation server is reachable at %@. Start LibreTranslate or use Apple Translation (macOS 15+).", baseURL.absoluteString)
            )
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            var message = tr("Local translation server answered HTTP %d %@", code, String(body.prefix(120)))
            if baseURL.port == 5000 {
                message += " " + tr("— on macOS port 5000 is used by AirPlay Receiver, so this is probably not LibreTranslate. Run LibreTranslate on another port (e.g. --port 5001) and update the URL in Settings.")
            }
            throw TranslationError.providerFailed(message)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = object["translatedText"] as? String else {
            throw TranslationError.providerFailed(tr("Unexpected response from the local translation server."))
        }
        return TranslationResult(sourceText: trimmed, translatedText: translated,
                                 sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: name)
    }
}
