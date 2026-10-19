import Foundation
import SwiftData

/// A saved word or expression together with the game context it was met in.
@Model
final class VocabularyItem {
    /// Lemma (words) or dictionary form (phrases), lowercased. One row per key.
    @Attribute(.unique) var key: String
    /// What to memorize: "reluctant", "count on somebody".
    var expression: String
    var lemma: String
    var kindRaw: String
    var translation: String?
    var partOfSpeech: String?
    var exampleSentence: String?
    var exampleTranslation: String?
    var dateFirstSeen: Date
    var dateLastSeen: Date
    var timesSeen: Int
    var statusRaw: String
    var sourceGame: String?
    var notes: String?
    /// Set once a card for this item was sent to Anki.
    var addedToAnki: Bool = false
    /// Further contexts (sentences) the expression was met in; the first one is `exampleSentence`.
    var extraContexts: [String] = []
    var speaker: String?

    /// Every saved context, first one first.
    var contexts: [String] {
        ([exampleSentence].compactMap { $0 } + extraContexts)
    }

    var status: VocabularyStatus {
        get { VocabularyStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    var kind: CandidateKind {
        get { CandidateKind(rawValue: kindRaw) ?? .word }
        set { kindRaw = newValue.rawValue }
    }

    init(
        key: String, expression: String, lemma: String, kind: CandidateKind,
        translation: String? = nil, partOfSpeech: String? = nil,
        exampleSentence: String? = nil, exampleTranslation: String? = nil,
        status: VocabularyStatus = .unknown, sourceGame: String? = nil, notes: String? = nil,
        now: Date = Date()
    ) {
        self.key = key
        self.expression = expression
        self.lemma = lemma
        self.kindRaw = kind.rawValue
        self.translation = translation
        self.partOfSpeech = partOfSpeech
        self.exampleSentence = exampleSentence
        self.exampleTranslation = exampleTranslation
        self.dateFirstSeen = now
        self.dateLastSeen = now
        self.timesSeen = 1
        self.statusRaw = status.rawValue
        self.sourceGame = sourceGame
        self.notes = notes
    }
}
