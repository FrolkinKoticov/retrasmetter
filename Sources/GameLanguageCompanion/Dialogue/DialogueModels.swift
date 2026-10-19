import Foundation
import CoreGraphics

/// One word of the dialogue together with where it is on screen.
struct RecognizedWord: Identifiable, Equatable, Sendable {
    let id: UUID
    /// As read by OCR (may include punctuation, e.g. "reluctant,").
    let text: String
    /// Global AppKit screen coordinates (bottom-left origin).
    let boundingBox: CGRect
    let confidence: Float
    let lineIndex: Int

    /// The word without punctuation at its edges ("reluctant," → "reluctant").
    var lookupText: String { Self.trimEdges(text) }

    static func trimEdges(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines))
    }
}

/// What the dialogue area currently shows.
struct CurrentDialogue: Equatable, Sendable {
    let fullText: String
    let words: [RecognizedWord]
    let timestamp: Date
    let speaker: String?
    let sourceGame: String?
    /// The dialogue area in global AppKit screen coordinates.
    let regionFrame: CGRect

    /// Text of words[range] joined like `fullText`, without punctuation at both ends.
    func text(in range: ClosedRange<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound < words.count else { return "" }
        let joined = words[range].map(\.text).joined(separator: " ")
        return RecognizedWord.trimEdges(joined)
    }

    func frame(of range: ClosedRange<Int>) -> CGRect {
        guard range.lowerBound >= 0, range.upperBound < words.count else { return .zero }
        return words[range].map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
    }
}
