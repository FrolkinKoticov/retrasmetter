import Foundation

/// Languages the app's own interface can be shown in (independent of the game language).
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, en, ru, de, es, fr
    case turkish = "tr"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return tr("System default")
        case .en: return "English"
        case .ru: return "Русский"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .fr: return "Français"
        case .turkish: return "Türkçe"
        }
    }
}

/// Tiny in-app localization: the English source string is the key; other languages are
/// plain dictionaries (see `L10n+ru.swift` …). A missing translation falls back to English,
/// so adding a language is just adding one more dictionary file and a case above.
/// Done in code (not .lproj bundles) so the language can be switched live, without relaunch,
/// and so it works the same from Xcode, `swift build` and the .app bundle.
enum L10n {
    static var selection: InterfaceLanguage = .system

    static let supported = ["en", "ru", "de", "tr", "es", "fr"]

    /// Effective language code ("en", "ru", …).
    static var code: String {
        if selection != .system { return selection.rawValue }
        for identifier in Locale.preferredLanguages {
            let base = String(identifier.prefix(2)).lowercased()
            if supported.contains(base) { return base }
        }
        return "en"
    }

    static var locale: Locale { Locale(identifier: code) }

    static let tables: [String: [String: String]] = ["ru": ru, "de": de, "es": es, "fr": fr, "tr": turkish]

    static func lookup(_ key: String) -> String {
        let code = self.code
        if code == "en" { return key }
        return tables[code]?[key] ?? key
    }

    /// Builds a table from pairs; a duplicated key keeps the last value instead of crashing.
    static func make(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }
}

/// Localized string.
func tr(_ key: String) -> String { L10n.lookup(key) }

/// Localized format string (`%@` for strings, `%d` for integers, `%.2f` for decimals).
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L10n.lookup(key), arguments: arguments)
}
