import Foundation

enum VocabularyStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Saved but not started yet.
    case unknown
    /// Actively being learned; keeps being surfaced when it shows up again.
    case learning
    /// Already known; never suggested again.
    case known
    /// Not interesting (names, slang, noise); never suggested again.
    case ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: return tr("New")
        case .learning: return tr("Learning")
        case .known: return tr("Known")
        case .ignored: return tr("Ignored")
        }
    }
}
