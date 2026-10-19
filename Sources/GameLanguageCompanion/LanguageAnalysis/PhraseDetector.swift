import Foundation
import NaturalLanguage

struct PhraseMatch: Sendable {
    /// Space-joined lemma pattern, e.g. "count on".
    let lemma: String
    /// What to memorize and store, e.g. "count on somebody".
    let display: String
    /// Built-in Russian gloss, if this is a curated expression.
    let gloss: String?
    let difficulty: Double
    /// Inclusive token indices of the span.
    let firstIndex: Int
    let lastIndex: Int
}

protocol PhraseDetecting: Sendable {
    func detect(in tokens: [AnalyzedToken]) -> [PhraseMatch]
}

struct PhraseEntry: Sendable {
    let lemmas: [String]
    let display: String
    let gloss: String
    /// How many unrelated words may sit between the parts ("give *it* up", "figure *this* out").
    var maxGap: Int = 0
    var difficulty: Double = 0.7
}

/// Deterministic English expression detector: a curated table matched on lemmas (so
/// "counting on", "counted on" and "count on" all hit), plus a conservative heuristic for
/// unknown phrasal verbs. Extend `table` freely, or load more entries from a file later.
struct EnglishPhraseDetector: PhraseDetecting {
    var detectGenericPhrasalVerbs = true

    func detect(in tokens: [AnalyzedToken]) -> [PhraseMatch] {
        var matches: [PhraseMatch] = []
        var covered = Set<Int>()

        for entry in Self.table {
            guard let head = entry.lemmas.first else { continue }
            for start in tokens.indices where tokens[start].lemma == head {
                var last = start
                var matched = true
                for part in entry.lemmas.dropFirst() {
                    var found = false
                    var j = last + 1
                    while j < tokens.count, j - last - 1 <= entry.maxGap {
                        if tokens[j].lemma == part { last = j; found = true; break }
                        j += 1
                    }
                    if !found { matched = false; break }
                }
                if matched {
                    matches.append(PhraseMatch(
                        lemma: entry.lemmas.joined(separator: " "), display: entry.display, gloss: entry.gloss,
                        difficulty: entry.difficulty, firstIndex: start, lastIndex: last))
                    covered.formUnion(start...last)
                }
            }
        }

        if detectGenericPhrasalVerbs, tokens.count >= 2 {
            for i in 0..<(tokens.count - 1) {
                let verb = tokens[i], particle = tokens[i + 1]
                guard verb.lexicalClass == .verb, !verb.isName,
                      Self.particles.contains(particle.lemma),
                      !covered.contains(i), !covered.contains(i + 1),
                      !CommonWords.set.contains(verb.lemma) else { continue }
                let phrase = "\(verb.lemma) \(particle.lemma)"
                matches.append(PhraseMatch(lemma: phrase, display: phrase, gloss: nil,
                                           difficulty: 0.6, firstIndex: i, lastIndex: i + 1))
            }
        }
        return matches
    }

    private static let particles: Set<String> = ["up", "out", "off", "away", "over", "back", "down", "through", "along"]

    // Starter table. Russian glosses are short and general; context-specific meaning comes
    // from the sentence translation shown next to them.
    private static let table: [PhraseEntry] = [
        PhraseEntry(lemmas: ["count", "on"], display: "count on somebody", gloss: "рассчитывать на кого-либо"),
        PhraseEntry(lemmas: ["give", "up"], display: "give up", gloss: "сдаваться; бросать (что-либо)", maxGap: 2),
        PhraseEntry(lemmas: ["end", "up"], display: "end up", gloss: "в итоге оказаться; кончить тем, что…"),
        PhraseEntry(lemmas: ["be", "suppose", "to"], display: "be supposed to", gloss: "должен (по плану или правилам); предполагается"),
        PhraseEntry(lemmas: ["be", "reluctant", "to"], display: "be reluctant to do something", gloss: "неохотно делать что-либо"),
        PhraseEntry(lemmas: ["might", "as", "well"], display: "might as well", gloss: "можно и…; почему бы и нет"),
        PhraseEntry(lemmas: ["figure", "out"], display: "figure out", gloss: "разобраться; понять; выяснить", maxGap: 2),
        PhraseEntry(lemmas: ["get", "away", "with"], display: "get away with", gloss: "уйти от наказания; сойти с рук"),
        PhraseEntry(lemmas: ["show", "up"], display: "show up", gloss: "появиться; прийти"),
        PhraseEntry(lemmas: ["look", "forward", "to"], display: "look forward to", gloss: "с нетерпением ждать"),
        PhraseEntry(lemmas: ["come", "up", "with"], display: "come up with", gloss: "придумать; предложить"),
        PhraseEntry(lemmas: ["put", "up", "with"], display: "put up with", gloss: "мириться с; терпеть"),
        PhraseEntry(lemmas: ["run", "out", "of"], display: "run out of", gloss: "исчерпать запас; у кого-то закончилось"),
        PhraseEntry(lemmas: ["take", "care", "of"], display: "take care of", gloss: "позаботиться о; заняться"),
        PhraseEntry(lemmas: ["find", "out"], display: "find out", gloss: "выяснить; узнать", maxGap: 2),
        PhraseEntry(lemmas: ["turn", "out"], display: "turn out", gloss: "оказаться; выясниться"),
        PhraseEntry(lemmas: ["make", "sure"], display: "make sure", gloss: "убедиться; удостовериться", difficulty: 0.55),
        PhraseEntry(lemmas: ["hang", "out"], display: "hang out", gloss: "проводить время; тусоваться"),
        PhraseEntry(lemmas: ["bring", "up"], display: "bring up", gloss: "затронуть тему; воспитывать", maxGap: 2),
        PhraseEntry(lemmas: ["pick", "up"], display: "pick up", gloss: "подобрать; поднять; подцепить", maxGap: 2),
        PhraseEntry(lemmas: ["give", "in"], display: "give in", gloss: "уступить; сдаться"),
        PhraseEntry(lemmas: ["look", "into"], display: "look into", gloss: "изучить; разобраться (в вопросе)"),
        PhraseEntry(lemmas: ["deal", "with"], display: "deal with", gloss: "иметь дело с; справляться с"),
        PhraseEntry(lemmas: ["make", "up", "for"], display: "make up for", gloss: "компенсировать; загладить"),
        PhraseEntry(lemmas: ["get", "over"], display: "get over", gloss: "пережить; оправиться от"),
        PhraseEntry(lemmas: ["go", "through"], display: "go through", gloss: "пройти через; пережить"),
        PhraseEntry(lemmas: ["set", "up"], display: "set up", gloss: "организовать; настроить; подставить", maxGap: 2),
        PhraseEntry(lemmas: ["stand", "up", "for"], display: "stand up for", gloss: "отстаивать; заступиться за"),
        PhraseEntry(lemmas: ["back", "off"], display: "back off", gloss: "отступить; отстать"),
        PhraseEntry(lemmas: ["keep", "up", "with"], display: "keep up with", gloss: "не отставать от"),
        PhraseEntry(lemmas: ["fall", "for"], display: "fall for", gloss: "влюбиться в; попасться на (обман)"),
        PhraseEntry(lemmas: ["back", "out"], display: "back out", gloss: "дать задний ход; отказаться от договорённости"),
        PhraseEntry(lemmas: ["cut", "out"], display: "cut out", gloss: "вырезать; прекратить («cut it out!»)", maxGap: 1),
        PhraseEntry(lemmas: ["take", "advantage", "of"], display: "take advantage of", gloss: "воспользоваться; использовать в своих интересах"),
        PhraseEntry(lemmas: ["look", "out", "for"], display: "look out for", gloss: "присматривать за; остерегаться"),
        PhraseEntry(lemmas: ["be", "about", "to"], display: "be about to do something", gloss: "вот-вот собираться сделать", difficulty: 0.55),
        PhraseEntry(lemmas: ["be", "willing", "to"], display: "be willing to do something", gloss: "быть готовым сделать что-либо"),
        PhraseEntry(lemmas: ["be", "into"], display: "be into something", gloss: "увлекаться чем-либо"),
        PhraseEntry(lemmas: ["work", "out"], display: "work out", gloss: "получиться; решиться; тренироваться", maxGap: 2),
        PhraseEntry(lemmas: ["sort", "out"], display: "sort out", gloss: "разобраться; уладить", maxGap: 2),
        PhraseEntry(lemmas: ["calm", "down"], display: "calm down", gloss: "успокоиться; успокоить", maxGap: 1),
        PhraseEntry(lemmas: ["pull", "off"], display: "pull off", gloss: "провернуть; справиться с трудным", maxGap: 2),
        PhraseEntry(lemmas: ["screw", "up"], display: "screw up", gloss: "облажаться; испортить", maxGap: 2)
    ]
}
