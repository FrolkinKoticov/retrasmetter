import Foundation

/// Talks to the free AnkiConnect add-on over localhost (default http://127.0.0.1:8765).
struct AnkiConnectService: AnkiService {
    let baseURL: URL

    init?(urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return nil }
        baseURL = url
    }

    func isAvailable() async -> Bool {
        (try? await call("version")) != nil
    }

    func availableDecks() async throws -> [String] {
        (try await call("deckNames") as? [String]) ?? []
    }

    func availableModels() async throws -> [String] {
        (try await call("modelNames") as? [String]) ?? []
    }

    func cardExists(for key: String) async throws -> Bool {
        let tag = AnkiCardBuilder.expressionTag(for: key)
        let result = try await call("findNotes", params: ["query": "tag:\(tag)"])
        return ((result as? [Any])?.isEmpty == false)
    }

    func add(card: AnkiCard, allowDuplicate: Bool) async throws -> Int64 {
        _ = try? await call("createDeck", params: ["deck": card.deck])   // idempotent

        let fieldNames = (try await call("modelFieldNames", params: ["modelName": card.model]) as? [String]) ?? []
        guard !fieldNames.isEmpty else {
            throw AnkiError.rejected(tr("Note type “%@” was not found. Check the name in Settings → Anki.", card.model))
        }

        // Map ordered values onto the note type's real field names (works with localized
        // names too). Extra fields stay empty; surplus values fold into the last field.
        var fields: [String: String] = Dictionary(uniqueKeysWithValues: fieldNames.map { ($0, "") })
        let values = card.fieldValues
        if values.count <= fieldNames.count {
            for (index, value) in values.enumerated() { fields[fieldNames[index]] = value }
        } else {
            for index in 0..<(fieldNames.count - 1) { fields[fieldNames[index]] = values[index] }
            fields[fieldNames[fieldNames.count - 1]] = values[(fieldNames.count - 1)...].joined(separator: "<br>")
        }

        let note: [String: Any] = [
            "deckName": card.deck,
            "modelName": card.model,
            "fields": fields,
            "options": ["allowDuplicate": allowDuplicate],
            "tags": card.tags
        ]
        let result = try await call("addNote", params: ["note": note])
        guard let id = (result as? NSNumber)?.int64Value else {
            throw AnkiError.rejected(tr("Unexpected response from AnkiConnect."))
        }
        return id
    }

    // MARK: Transport

    private func call(_ action: String, params: [String: Any] = [:]) async throws -> Any? {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": action, "version": 6, "params": params
        ] as [String: Any])

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AnkiError.notRunning
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnkiError.rejected(tr("Unexpected response from AnkiConnect."))
        }
        if let message = object["error"] as? String {
            if message.localizedCaseInsensitiveContains("duplicate") { throw AnkiError.duplicate }
            throw AnkiError.rejected(message)
        }
        return object["result"]
    }
}
