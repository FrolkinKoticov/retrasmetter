import Foundation

/// Builds contextual cards: the sentence from the game is always the centre of the card.
struct AnkiCardBuilder {
    var deck: String
    var style: AnkiCardStyle
    var basicModel: String
    var clozeModel: String

    /// Tag that identifies cards made for one expression; used to detect duplicates.
    static func expressionTag(for key: String) -> String {
        let cleaned = key.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return "glc_" + cleaned
    }

    func build(
        candidate: VocabularyCandidate, sentence: String,
        sentenceTranslation: String?, wordTranslation: String?, game: String?
    ) -> AnkiCard {
        let before = String(sentence[..<candidate.range.lowerBound])
        let span = String(sentence[candidate.range])
        let after = String(sentence[candidate.range.upperBound...])
        let hasSpan = !span.isEmpty
        return make(key: candidate.key, expression: candidate.displayForm, kindIsPhrase: candidate.kind == .phrase,
                    sentence: sentence, before: hasSpan ? before : sentence, span: hasSpan ? span : nil,
                    after: hasSpan ? after : "", translation: wordTranslation ?? candidate.builtInGloss,
                    sentenceTranslation: sentenceTranslation, game: game)
    }

    /// Card for an item saved in the vocabulary (no live sentence analysis needed).
    func build(item: VocabularyItem) -> AnkiCard {
        let sentence = item.exampleSentence ?? item.expression
        let range = sentence.range(of: item.expression, options: [.caseInsensitive, .diacriticInsensitive])
            ?? sentence.range(of: item.lemma, options: [.caseInsensitive, .diacriticInsensitive])
        return make(key: item.key, expression: item.expression, kindIsPhrase: item.kind == .phrase,
                    sentence: sentence,
                    before: range.map { String(sentence[..<$0.lowerBound]) } ?? sentence,
                    span: range.map { String(sentence[$0]) },
                    after: range.map { String(sentence[$0.upperBound...]) } ?? "",
                    translation: item.translation, sentenceTranslation: item.exampleTranslation, game: item.sourceGame)
    }

    // MARK: Layout

    private func make(
        key: String, expression: String, kindIsPhrase: Bool, sentence: String,
        before: String, span: String?, after: String,
        translation: String?, sentenceTranslation: String?, game: String?
    ) -> AnkiCard {
        // Back: expression, its translation, the full sentence and its translation, the source.
        var back = "<b>\(escape(expression))</b>"
        if let translation, !translation.isEmpty { back += "<br>\(escape(translation))" }
        if let span {
            back += "<br><br>\(escape(before))<b>\(escape(span))</b>\(escape(after))"
        } else {
            back += "<br><br>\(escape(sentence))"
        }
        if let sentenceTranslation, !sentenceTranslation.isEmpty {
            back += "<br><i>\(escape(sentenceTranslation))</i>"
        }
        if let game, !game.isEmpty { back += "<br><br><small>\(escape(game))</small>" }

        var tags = ["GameLanguageCompanion", Self.expressionTag(for: key)]
        if let game, !game.isEmpty { tags.append(game.replacingOccurrences(of: " ", with: "_")) }

        switch style {
        case .basic:
            // Front: the sentence with a blank, plus the expression that fills it.
            let front: String
            if span != nil {
                front = "\(escape(before))______\(escape(after))<br><br><b>\(escape(expression))</b>"
            } else {
                front = "\(escape(sentence))<br><br><b>\(escape(expression))</b>"
            }
            return AnkiCard(deck: deck, model: basicModel, fieldValues: [front, back], tags: tags)
        case .cloze:
            let text: String
            if let span {
                let hint = kindIsPhrase ? "::\(escape(expression))" : ""
                text = "\(escape(before)){{c1::\(escape(span))\(hint)}}\(escape(after))"
            } else {
                text = "{{c1::\(escape(sentence))}}"
            }
            return AnkiCard(deck: deck, model: clozeModel, fieldValues: [text, back], tags: tags)
        }
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
