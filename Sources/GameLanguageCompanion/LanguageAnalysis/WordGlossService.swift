import Foundation
import CoreServices

struct WordGloss: Sendable, Equatable {
    var translation: String?
    /// Definition from the macOS system dictionary (free, offline), when available.
    var definition: String?
}

/// Offline lookup in the macOS Dictionary app's data.
enum DictionaryLookup {
    static func definition(for term: String) -> String? {
        let text = term as CFString
        guard let unmanaged = DCSCopyTextDefinition(nil, text, CFRangeMake(0, CFStringGetLength(text))) else { return nil }
        let definition = unmanaged.takeRetainedValue() as String
        return definition.count > 320 ? String(definition.prefix(320)) + "…" : definition
    }
}

/// Explains one word or expression: built-in gloss → translation provider → system dictionary.
@MainActor
final class WordGlossService {
    private let settings: AppSettings
    private let translationProvider: () -> any TranslationService

    init(settings: AppSettings, translationProvider: @escaping () -> any TranslationService) {
        self.settings = settings
        self.translationProvider = translationProvider
    }

    func gloss(for candidate: VocabularyCandidate) async -> WordGloss {
        var translation = candidate.builtInGloss
        if translation == nil {
            let result = try? await translationProvider().translate(
                candidate.lemma, from: settings.sourceLanguage, to: settings.targetLanguage)
            translation = result?.translatedText
        }
        let definition = settings.sourceLanguage == .english ? DictionaryLookup.definition(for: candidate.lemma) : nil
        return WordGloss(translation: translation, definition: definition)
    }
}
