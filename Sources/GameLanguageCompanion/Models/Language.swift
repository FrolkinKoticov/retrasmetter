import Foundation
import NaturalLanguage

/// A language the app can read (OCR), analyze and translate. Kept deliberately tiny so
/// that adding a language is a one-liner; provider-specific mappings live here.
struct Language: Hashable, Codable, Identifiable, Sendable {
    let code: String
    var id: String { code }

    static let english = Language(code: "en")
    static let russian = Language(code: "ru")
    static let german = Language(code: "de")
    static let french = Language(code: "fr")
    static let spanish = Language(code: "es")
    static let turkish = Language(code: "tr")

    static let all: [Language] = [.english, .russian, .german, .turkish, .french, .spanish]

    var displayName: String {
        L10n.locale.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: code) }
    var nlLanguage: NLLanguage { NLLanguage(rawValue: code) }

    /// Voice language for pronunciation (AVSpeechSynthesizer).
    var speechCode: String {
        switch code {
        case "en": return "en-US"
        case "ru": return "ru-RU"
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "tr": return "tr-TR"
        default: return code
        }
    }

    /// BCP-47 identifier understood by Vision's `recognitionLanguages`.
    var visionCode: String {
        switch code {
        case "en": return "en-US"
        case "ru": return "ru-RU"
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "tr": return "tr-TR"
        default: return code
        }
    }
}
