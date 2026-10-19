import Foundation
import NaturalLanguage

enum CandidateKind: String, Codable, Sendable {
    case word
    case phrase
}

extension VocabularyCandidate {
    /// A candidate for something the user selected by hand in Reading Mode.
    static func fromSelection(
        _ selection: String, normalized: String?, partOfSpeech: String?, sentence: String
    ) -> VocabularyCandidate {
        let expression = (normalized?.isEmpty == false ? normalized! : selection)
        let key = expression.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let range = sentence.range(of: selection, options: [.caseInsensitive, .diacriticInsensitive])
            ?? sentence.startIndex..<sentence.startIndex
        return VocabularyCandidate(
            key: key, surface: selection, lemma: key, displayForm: expression,
            kind: key.contains(" ") ? .phrase : .word, partOfSpeech: partOfSpeech,
            difficulty: 1, range: range, builtInGloss: nil)
    }
}

/// One thing in a sentence the learner might want to look at: a single word or a
/// multi-word expression ("count on somebody").
struct VocabularyCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    /// Stable identity used for persistence and known-word lookups
    /// (the lemma for words, the dictionary form for phrases), lowercased.
    var key: String
    /// Exactly as it appears in the sentence (for phrases: the whole span).
    var surface: String
    var lemma: String
    /// What the learner should memorize, e.g. "reluctant" or "count on somebody".
    var displayForm: String
    var kind: CandidateKind
    var partOfSpeech: String?
    /// 0 (trivial) … 1 (hard). See `DifficultyEstimating`.
    var difficulty: Double
    /// Location inside the analyzed sentence.
    var range: Range<String.Index>
    /// Bundled translation for known expressions (free, offline). Optional.
    var builtInGloss: String?
}
