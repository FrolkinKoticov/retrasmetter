import Foundation

struct TranslationResult: Sendable, Equatable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: Language
    let targetLanguage: Language
    /// Which provider produced it, e.g. "Apple Translation".
    let provider: String
    /// Optional extras (filled by providers that understand context, e.g. OpenAI).
    var normalizedExpression: String? = nil
    var partOfSpeech: String? = nil
    var shortExplanation: String? = nil
}

enum TranslationError: LocalizedError {
    case emptyText
    case unavailable(String)
    case providerFailed(String)
    case timedOut
    case allFailed([String])

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return tr("There is no text to translate.")
        case .unavailable(let reason):
            return reason
        case .providerFailed(let reason):
            return reason
        case .timedOut:
            return tr("Translation timed out. If this is the first use, open Settings → Translation and download the language pack.")
        case .allFailed(let reasons):
            return tr("No translation provider is available.") + "\n" + reasons.map { "• \($0)" }.joined(separator: "\n")
        }
    }
}
