import Foundation

enum AnkiError: LocalizedError {
    case notRunning
    case duplicate
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return tr("Anki is not reachable. Open Anki and make sure the AnkiConnect add-on (code 2055492159) is installed.")
        case .duplicate:
            return tr("This note already exists in Anki.")
        case .rejected(let message):
            return tr("Anki refused the note: %@", message)
        }
    }
}

protocol AnkiService: Sendable {
    func isAvailable() async -> Bool
    func availableDecks() async throws -> [String]
    func availableModels() async throws -> [String]
    /// Returns the new note's id. `allowDuplicate` lets a second card for the same expression through.
    func add(card: AnkiCard, allowDuplicate: Bool) async throws -> Int64
    /// True if a card for this expression key (see `AnkiCardBuilder.expressionTag`) already exists.
    func cardExists(for key: String) async throws -> Bool
}

extension AnkiService {
    func add(card: AnkiCard) async throws -> Int64 { try await add(card: card, allowDuplicate: false) }
    func cardExists(for key: String) async throws -> Bool { false }
}
