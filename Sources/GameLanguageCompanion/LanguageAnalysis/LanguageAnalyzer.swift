import Foundation
import NaturalLanguage

struct AnalyzedToken: Sendable {
    let surface: String
    /// Lowercased lemma, with auxiliary/contracted "be" forms normalized to "be".
    let lemma: String
    let lexicalClass: NLTag?
    let isName: Bool
    let range: Range<String.Index>
}

struct LanguageAnalysis: Sendable {
    let sentence: String
    let tokens: [AnalyzedToken]
    /// Every content word and expression found, unfiltered. Which ones are actually
    /// *suggested* depends on the user's known words and settings (see `VocabularyManager`).
    let candidates: [VocabularyCandidate]
    /// Lemmas of content words that occur more than once in the sentence.
    let repeatedWords: [String]
}

/// Sentence understanding. The free implementation uses Apple NaturalLanguage plus
/// deterministic rules. LLM-based analyzers (idioms, CEFR, grammar notes) can implement the
/// same protocol later without touching the pipeline.
protocol LanguageAnalyzer: Sendable {
    func analyze(sentence: String) async throws -> LanguageAnalysis
}

struct NaturalLanguageAnalyzer: LanguageAnalyzer {
    var language: Language = .english
    var phraseDetector: any PhraseDetecting = EnglishPhraseDetector()
    var difficulty: any DifficultyEstimating = HeuristicDifficultyEstimator()

    func analyze(sentence: String) async throws -> LanguageAnalysis {
        let language = self.language
        let detector = phraseDetector
        let estimator = difficulty
        return await Task.detached(priority: .userInitiated) {
            Self.run(sentence: sentence, language: language, detector: detector, estimator: estimator)
        }.value
    }

    // MARK: - Implementation

    private static func run(
        sentence: String, language: Language,
        detector: any PhraseDetecting, estimator: any DifficultyEstimating
    ) -> LanguageAnalysis {
        let tokens = tokenize(sentence, language: language)
        var candidates: [VocabularyCandidate] = []

        // 1. Multi-word expressions first: they matter more than their individual words.
        if language == .english {
            var seenPhrases = Set<String>()
            for match in detector.detect(in: tokens) {
                let key = match.display.lowercased()
                guard seenPhrases.insert(key).inserted else { continue }
                let range = tokens[match.firstIndex].range.lowerBound ..< tokens[match.lastIndex].range.upperBound
                candidates.append(VocabularyCandidate(
                    key: key, surface: String(sentence[range]), lemma: match.lemma,
                    displayForm: match.display, kind: .phrase, partOfSpeech: "phrase",
                    difficulty: match.difficulty, range: range, builtInGloss: match.gloss))
            }
        }

        // 2. Single content words.
        var seenWords = Set<String>()
        var counts: [String: Int] = [:]
        for token in tokens where isContentWord(token) {
            counts[token.lemma, default: 0] += 1
            guard seenWords.insert(token.lemma).inserted else { continue }
            let pos = partOfSpeechName(token.lexicalClass)
            candidates.append(VocabularyCandidate(
                key: token.lemma, surface: token.surface, lemma: token.lemma,
                displayForm: token.lemma, kind: .word, partOfSpeech: pos,
                difficulty: estimator.difficulty(forLemma: token.lemma, partOfSpeech: pos),
                range: token.range, builtInGloss: nil))
        }

        let repeated = counts.filter { $0.value > 1 }.map(\.key).sorted()
        return LanguageAnalysis(sentence: sentence, tokens: tokens, candidates: candidates, repeatedWords: repeated)
    }

    private static func tokenize(_ sentence: String, language: Language) -> [AnalyzedToken] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = sentence
        let full = sentence.startIndex..<sentence.endIndex
        tagger.setLanguage(language.nlLanguage, range: full)

        var tokens: [AnalyzedToken] = []
        // Contractions are intentionally *not* joined: "We're" → "We" + "'re" (lemma "be"),
        // which lets phrase patterns like "be supposed to" match.
        tagger.enumerateTags(in: full, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            let surface = String(sentence[range])
            let rawLemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? surface
            let name = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType).0
            let isName = name == .personalName || name == .placeName || name == .organizationName
            tokens.append(AnalyzedToken(
                surface: surface, lemma: normalizeLemma(rawLemma.lowercased()),
                lexicalClass: tag, isName: isName, range: range))
            return true
        }
        return tokens
    }

    private static func normalizeLemma(_ lemma: String) -> String {
        switch lemma {
        case "am", "is", "are", "was", "were", "been", "being", "'m", "'re": return "be"
        case "'ve": return "have"
        default: return lemma
        }
    }

    private static func isContentWord(_ token: AnalyzedToken) -> Bool {
        guard !token.isName, token.lemma.count >= 3 else { return false }
        guard let tag = token.lexicalClass,
              tag == .noun || tag == .verb || tag == .adjective || tag == .adverb else { return false }
        if token.surface.contains(where: { $0.isNumber }) { return false }
        return !stopwords.contains(token.lemma)
    }

    private static func partOfSpeechName(_ tag: NLTag?) -> String? {
        switch tag {
        case .some(.noun): return "noun"
        case .some(.verb): return "verb"
        case .some(.adjective): return "adj."
        case .some(.adverb): return "adv."
        default: return nil
        }
    }

    /// Function words and auxiliaries that are never worth suggesting.
    private static let stopwords: Set<String> = [
        "the", "and", "but", "for", "nor", "yet", "his", "her", "its", "our", "their", "your", "you",
        "she", "him", "they", "them", "who", "whom", "whose", "which", "what", "this", "that", "these",
        "those", "with", "from", "into", "onto", "upon", "about", "over", "under", "than", "then",
        "there", "here", "when", "where", "while", "because", "since", "until", "though", "although",
        "not", "n't", "are", "was", "were", "been", "being", "have", "has", "had", "does", "did", "done",
        "will", "would", "can", "could", "shall", "should", "may", "might", "must", "also", "just",
        "very", "too", "some", "any", "all", "each", "every", "both", "either", "neither", "more",
        "most", "much", "many", "such", "own", "same", "other", "another", "how", "why", "yes", "yeah",
        "okay", "gonna", "wanna", "gotta", "let", "get", "got", "say", "said"
    ]
}
