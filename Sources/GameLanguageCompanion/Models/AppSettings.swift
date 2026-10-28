import Foundation
import Combine

enum LearningMode: String, CaseIterable, Identifiable {
    case translation, learning, immersion
    var id: String { rawValue }
    var title: String {
        switch self {
        case .translation: return tr("Translation")
        case .learning: return tr("Learning")
        case .immersion: return tr("Immersion")
        }
    }
    var explanation: String {
        switch self {
        case .translation: return tr("Shows the sentence, its translation and useful words.")
        case .learning: return tr("Translation is hidden until you click “Show full translation”.")
        case .immersion: return tr("No automatic translation; only difficult words are highlighted.")
        }
    }
}

enum TranslationProviderChoice: String, CaseIterable, Identifiable {
    case automatic, apple, libreTranslate, deepl, openai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return tr("Automatic (Apple, then local server)")
        case .apple: return tr("Apple Translation (macOS 15+, offline)")
        case .libreTranslate: return tr("Local LibreTranslate server")
        case .deepl: return tr("DeepL (optional, your own API key)")
        case .openai: return tr("OpenAI (optional, usage may cost money)")
        }
    }
}

extension TranslationProviderChoice {
    /// Set for the providers that need an API key.
    var apiProvider: APIProvider? {
        switch self {
        case .deepl: return .deepl
        case .openai: return .openai
        default: return nil
        }
    }

    /// Short name for status lines.
    var shortName: String {
        switch self {
        case .automatic: return tr("Automatic")
        case .apple: return "Apple Translation"
        case .libreTranslate: return "LibreTranslate"
        case .deepl: return "DeepL"
        case .openai: return "OpenAI"
        }
    }
}

enum AnkiCardStyle: String, CaseIterable, Identifiable {
    case basic, cloze
    var id: String { rawValue }
    var title: String { self == .basic ? tr("Basic (front/back)") : tr("Cloze (fill the blank)") }
}

/// Where the translation overlay appears.
enum OverlayPlacement: String, CaseIterable, Identifiable {
    case aboveRegion, belowRegion, screenTop, screenCenter, screenBottom, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aboveRegion: return tr("Above the capture area")
        case .belowRegion: return tr("Below the capture area")
        case .screenTop: return tr("Top of the screen")
        case .screenCenter: return tr("Center of the screen")
        case .screenBottom: return tr("Bottom of the screen")
        case .custom: return tr("Where I last dragged it")
        }
    }
}

/// A remembered, user-dragged overlay position: offsets of the panel's top-left corner from the
/// top-left corner of its screen, so it survives resolution and display-arrangement changes.
struct OverlayCustomPosition: Codable, Equatable {
    var displayID: UInt32
    var x: Double
    var top: Double
}

/// All user-facing preferences. Persisted in UserDefaults; nothing here is sensitive
/// (the optional DeepL / OpenAI keys live in the Keychain, see `KeychainStore`).
@MainActor
final class AppSettings: ObservableObject {
    // MARK: General
    @Published var interfaceLanguage: InterfaceLanguage {
        didSet { Self.set(interfaceLanguage.rawValue, "interfaceLanguage"); L10n.selection = interfaceLanguage }
    }
    @Published var mode: LearningMode { didSet { Self.set(mode.rawValue, "mode") } }
    @Published var sourceLanguage: Language { didSet { Self.set(sourceLanguage.code, "sourceLanguage") } }
    @Published var targetLanguage: Language { didSet { Self.set(targetLanguage.code, "targetLanguage") } }
    @Published var gameNameOverride: String { didSet { Self.set(gameNameOverride, "gameNameOverride") } }
    /// Language used for text recognition; empty = same as the game language.
    @Published var ocrLanguageCode: String { didSet { Self.set(ocrLanguageCode, "ocrLanguageCode") } }
    @Published var hasCompletedOnboarding: Bool { didSet { Self.set(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    // MARK: Monitoring
    @Published var monitoringEnabled: Bool { didSet { Self.set(monitoringEnabled, "monitoringEnabled") } }
    /// Maximum frames analysed per second (the stream is throttled to this).
    @Published var monitoringFrequency: Double { didSet { Self.set(monitoringFrequency, "monitoringFrequency") } }
    /// How long the dialogue area must stay unchanged before OCR runs (typewriter text).
    @Published var stabilityDelay: Double { didSet { Self.set(stabilityDelay, "stabilityDelay") } }
    /// Minimum time between two OCR runs.
    @Published var ocrCooldown: Double { didSet { Self.set(ocrCooldown, "ocrCooldown") } }
    @Published var saveHistory: Bool { didSet { Self.set(saveHistory, "saveHistory") } }
    @Published var subtitleFontSize: Double { didSet { Self.set(subtitleFontSize, "subtitleFontSize") } }
    /// Subtitles above the dialogue instead of below it.
    /// Replace the original text in place, matching the game's colors (default) instead of a separate bar.
    @Published var subtitleReplaceInPlace: Bool { didSet { Self.set(subtitleReplaceInPlace, "subtitleReplaceInPlace") } }
    @Published var subtitleHotkeyKey: String { didSet { Self.set(subtitleHotkeyKey, "subtitleHotkeyKey") } }
    @Published var subtitlesAbove: Bool { didSet { Self.set(subtitlesAbove, "subtitlesAbove") } }

    // MARK: Capture
    @Published var captureRegion: CaptureRegion? { didSet { Self.store(captureRegion, "captureRegion") } }

    // MARK: Hotkey
    @Published var hotkeyKey: String { didSet { Self.set(hotkeyKey, "hotkeyKey") } }
    @Published var hotkeyModifiers: HotkeyModifiers { didSet { Self.set(hotkeyModifiers.rawValue, "hotkeyModifiers") } }

    // MARK: Translation
    @Published var translationProvider: TranslationProviderChoice { didSet { Self.set(translationProvider.rawValue, "translationProvider") } }
    @Published var libreTranslateURL: String { didSet { Self.set(libreTranslateURL, "libreTranslateURL") } }
    @Published var openAIModel: String { didSet { Self.set(openAIModel, "openAIModel") } }

    // MARK: Overlay
    @Published var overlayAutoHideSeconds: Double { didSet { Self.set(overlayAutoHideSeconds, "overlayAutoHideSeconds") } }
    @Published var overlayFontSize: Double { didSet { Self.set(overlayFontSize, "overlayFontSize") } }
    @Published var overlayWidth: Double { didSet { Self.set(overlayWidth, "overlayWidth") } }
    @Published var overlayPlacement: OverlayPlacement { didSet { Self.set(overlayPlacement.rawValue, "overlayPlacement") } }
    @Published var overlayCustomPosition: OverlayCustomPosition? { didSet { Self.store(overlayCustomPosition, "overlayCustomPosition") } }

    // MARK: Learning
    @Published var minimumDifficulty: Double { didSet { Self.set(minimumDifficulty, "minimumDifficulty") } }
    @Published var maxCandidates: Int { didSet { Self.set(maxCandidates, "maxCandidates") } }
    @Published var detectGenericPhrasalVerbs: Bool { didSet { Self.set(detectGenericPhrasalVerbs, "detectGenericPhrasalVerbs") } }
    @Published var detectSpeakerLabel: Bool { didSet { Self.set(detectSpeakerLabel, "detectSpeakerLabel") } }

    // MARK: Anki
    @Published var ankiEnabled: Bool { didSet { Self.set(ankiEnabled, "ankiEnabled") } }
    @Published var ankiURL: String { didSet { Self.set(ankiURL, "ankiURL") } }
    @Published var ankiDeck: String { didSet { Self.set(ankiDeck, "ankiDeck") } }
    @Published var ankiCardStyle: AnkiCardStyle { didSet { Self.set(ankiCardStyle.rawValue, "ankiCardStyle") } }
    /// Note type names. Anki localizes built-in names (e.g. Russian UI), so they are editable.
    @Published var ankiBasicModel: String { didSet { Self.set(ankiBasicModel, "ankiBasicModel") } }
    @Published var ankiClozeModel: String { didSet { Self.set(ankiClozeModel, "ankiClozeModel") } }

    init() {
        let language = InterfaceLanguage(rawValue: Self.string("interfaceLanguage", "")) ?? .system
        L10n.selection = language            // before anything computes a localized string
        interfaceLanguage = language

        mode = LearningMode(rawValue: Self.string("mode", "")) ?? .translation
        sourceLanguage = Language(code: Self.string("sourceLanguage", "en"))
        targetLanguage = Language(code: Self.string("targetLanguage", "ru"))
        gameNameOverride = Self.string("gameNameOverride", "")
        ocrLanguageCode = Self.string("ocrLanguageCode", "")
        hasCompletedOnboarding = Self.bool("hasCompletedOnboarding", false)
        monitoringEnabled = Self.bool("monitoringEnabled", true)
        monitoringFrequency = Self.double("monitoringFrequency", 3)
        stabilityDelay = Self.double("stabilityDelay", 0.6)
        ocrCooldown = Self.double("ocrCooldown", 0.5)
        saveHistory = Self.bool("saveHistory", true)
        subtitleFontSize = Self.double("subtitleFontSize", 22)
        subtitlesAbove = Self.bool("subtitlesAbove", false)
        subtitleReplaceInPlace = Self.bool("subtitleReplaceInPlace", true)
        subtitleHotkeyKey = Self.string("subtitleHotkeyKey", "W")
        captureRegion = Self.load(CaptureRegion.self, "captureRegion")
        hotkeyKey = Self.string("hotkeyKey", "Q")
        hotkeyModifiers = HotkeyModifiers(rawValue: Self.string("hotkeyModifiers", "")) ?? .option
        translationProvider = TranslationProviderChoice(rawValue: Self.string("translationProvider", "")) ?? .automatic
        libreTranslateURL = Self.string("libreTranslateURL", "http://127.0.0.1:5001")
        openAIModel = Self.string("openAIModel", "gpt-4o-mini")
        overlayAutoHideSeconds = Self.double("overlayAutoHideSeconds", 12)
        overlayFontSize = Self.double("overlayFontSize", 16)
        overlayWidth = Self.double("overlayWidth", 580)
        overlayPlacement = OverlayPlacement(rawValue: Self.string("overlayPlacement", "")) ?? .aboveRegion
        overlayCustomPosition = Self.load(OverlayCustomPosition.self, "overlayCustomPosition")
        minimumDifficulty = Self.double("minimumDifficulty", 0.5)
        maxCandidates = Int(Self.double("maxCandidates", 6))
        detectGenericPhrasalVerbs = Self.bool("detectGenericPhrasalVerbs", true)
        detectSpeakerLabel = Self.bool("detectSpeakerLabel", true)
        ankiEnabled = Self.bool("ankiEnabled", true)
        ankiURL = Self.string("ankiURL", "http://127.0.0.1:8765")
        ankiDeck = Self.string("ankiDeck", "Retrasmetter")
        ankiCardStyle = AnkiCardStyle(rawValue: Self.string("ankiCardStyle", "")) ?? .basic
        ankiBasicModel = Self.string("ankiBasicModel", "Basic")
        ankiClozeModel = Self.string("ankiClozeModel", "Cloze")
    }

    var hotkeyDescription: String { hotkeyModifiers.symbols + hotkeyKey }
    var subtitleHotkeyDescription: String { hotkeyModifiers.symbols + subtitleHotkeyKey }

    /// The language Vision should expect.
    var ocrLanguage: Language { ocrLanguageCode.isEmpty ? sourceLanguage : Language(code: ocrLanguageCode) }

    // MARK: UserDefaults helpers
    private static var defaults: UserDefaults { .standard }
    private static func set(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
    private static func string(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }
    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func store<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
