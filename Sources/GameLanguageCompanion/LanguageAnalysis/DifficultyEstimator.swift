import Foundation

protocol DifficultyEstimating: Sendable {
    /// 0 = trivial … 1 = very hard.
    func difficulty(forLemma lemma: String, partOfSpeech: String?) -> Double
}

/// Free heuristic: anything outside a built-in list of very common English words is a
/// candidate, longer words score higher. Not CEFR — that would need a frequency/level list.
/// To improve it, drop a plain-text file with one word per line at
/// `~/Library/Application Support/GameLanguageCompanion/common-words.txt`; its words are
/// treated as "easy" in addition to the built-in list. A CEFR-based estimator can replace
/// this type without changing anything else.
struct HeuristicDifficultyEstimator: DifficultyEstimating {
    func difficulty(forLemma lemma: String, partOfSpeech: String?) -> Double {
        if CommonWords.set.contains(lemma) { return 0 }
        var score = 0.5
        if lemma.count >= 9 { score += 0.2 }
        else if lemma.count >= 7 { score += 0.1 }
        else if lemma.count <= 4 { score -= 0.1 }
        return min(max(score, 0), 1)
    }
}

enum CommonWords {
    static let set: Set<String> = {
        var words = Set(builtIn.split(whereSeparator: { $0.isWhitespace }).map { String($0) })
        if let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false) {
            let file = dir.appendingPathComponent("GameLanguageCompanion/common-words.txt")
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                for line in text.split(whereSeparator: { $0.isNewline }) {
                    let word = line.trimmingCharacters(in: .whitespaces).lowercased()
                    if !word.isEmpty { words.insert(word) }
                }
            }
        }
        return words
    }()

    private static let builtIn = """
    say get make go know take see come think look want give use find tell ask work seem feel try leave call \
    need become mean put keep let begin help talk turn start show hear play run move like live believe hold \
    bring happen write sit stand lose pay meet include continue set learn change lead understand watch follow \
    stop create speak read allow add spend grow open walk win offer remember love consider appear buy wait \
    serve die send expect build stay fall cut reach kill remain suggest raise pass sell require decide pull \
    break eat drink sleep wake fight save check care miss hurt hope wish pick forget decide agree enjoy visit \
    ask answer listen laugh smile cry sing dance catch throw carry drive ride fly sleep dream plan hit shoot \
    time year people way day man thing woman life child world school state family student group country \
    problem hand part place case week company system program question government number night point home \
    water room mother father area money story fact month lot right study book eye job word business issue \
    side kind head house service friend power hour game line end member law car city community name \
    president team minute idea kid body information back parent face others level office door health person \
    art war history party result morning reason research girl guy moment air teacher force education boy \
    brother sister mom dad school class student town street food dinner lunch breakfast phone picture music \
    movie money luck trouble secret truth lie chance plan choice mind heart thought voice sound light dark \
    good new first last long great little own old big high different small large next early young important \
    few public bad same able sure real best better free true whole hard easy strong special clear recent late \
    general nice happy sorry ready afraid wrong sad tired angry careful dead alive cold hot fine bright quiet \
    cool crazy weird funny scary lucky busy rich poor full empty safe dangerous serious simple perfect \
    not so up out just now how then more also here well only very even back there down still too really never \
    always again often maybe already almost enough once actually probably together away far quite later \
    today tomorrow yesterday sometimes someone something anything everything nothing anyone everyone \
    please thanks sorry hello okay yeah right alright anyway
    """
}
