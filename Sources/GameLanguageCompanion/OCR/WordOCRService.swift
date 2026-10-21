import Vision
import CoreGraphics
import Foundation

/// A word as Vision reports it. `box` is normalized (0…1) with a bottom-left origin,
/// relative to the recognized image.
struct RawOCRWord: Sendable {
    let text: String
    let box: CGRect
    let confidence: Float
    let lineIndex: Int
}

struct WordOCRResult: Sendable {
    var words: [RawOCRWord]
    /// One entry per visual row, in reading order.
    var lines: [String]
}

/// Local OCR with word-level bounding boxes (Apple Vision, no network).
struct VisionWordOCR: Sendable {
    var language: Language = .english
    /// Passive monitoring runs at `.utility` so it never competes with the game for CPU.
    var priority: TaskPriority = .userInitiated

    func recognizeWords(in image: CGImage) async throws -> WordOCRResult {
        let languageCode = language.visionCode
        return try await Task.detached(priority: priority) { () throws -> WordOCRResult in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [languageCode]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRError.failed(error.localizedDescription)
            }
            return Self.assemble(request.results ?? [])
        }.value
    }

    // MARK: Assembly

    private struct Item {
        let box: CGRect
        let candidate: VNRecognizedText
    }

    private static func assemble(_ observations: [VNRecognizedTextObservation]) -> WordOCRResult {
        let items: [Item] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            return Item(box: observation.boundingBox, candidate: candidate)
        }
        // Vision's origin is bottom-left: the top of the image has the larger midY.
        let sorted = items.sorted { $0.box.midY > $1.box.midY }

        var rows: [[Item]] = []
        for item in sorted {
            if let reference = rows.last?.first,
               abs(reference.box.midY - item.box.midY) < max(reference.box.height, item.box.height) * 0.5 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }

        var words: [RawOCRWord] = []
        var lines: [String] = []
        for row in rows {
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            var rowWords: [RawOCRWord] = []
            for item in ordered {
                rowWords.append(contentsOf: tokens(of: item, lineIndex: lines.count))
            }
            guard !rowWords.isEmpty else { continue }
            words.append(contentsOf: rowWords)
            lines.append(rowWords.map(\.text).joined(separator: " "))
        }
        return WordOCRResult(words: words, lines: lines)
    }

    /// Splits one recognized text box into whitespace-separated words, each with its own box.
    private static func tokens(of item: Item, lineIndex: Int) -> [RawOCRWord] {
        let string = item.candidate.string
        let total = max(string.count, 1)
        var result: [RawOCRWord] = []
        var index = string.startIndex

        while index < string.endIndex {
            while index < string.endIndex, string[index].isWhitespace { index = string.index(after: index) }
            guard index < string.endIndex else { break }
            let start = index
            while index < string.endIndex, !string[index].isWhitespace { index = string.index(after: index) }
            let range = start..<index

            let token = normalize(String(string[range]))
            guard token.contains(where: { $0.isLetter || $0.isNumber }) else { continue }   // icons, bullets

            var box: CGRect
            if let exact = try? item.candidate.boundingBox(for: range)?.boundingBox {
                box = exact
            } else {
                // Fallback: split the observation's box in proportion to character offsets.
                let from = Double(string.distance(from: string.startIndex, to: range.lowerBound)) / Double(total)
                let to = Double(string.distance(from: string.startIndex, to: range.upperBound)) / Double(total)
                box = CGRect(x: item.box.minX + item.box.width * from, y: item.box.minY,
                             width: item.box.width * (to - from), height: item.box.height)
            }
            result.append(RawOCRWord(text: token, box: box, confidence: item.candidate.confidence, lineIndex: lineIndex))
        }
        return result
    }

    private static func normalize(_ token: String) -> String {
        let fixed = token
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return fixed == "|" ? "I" : fixed          // a lone bar is almost always a misread capital I
    }
}

/// Turns raw OCR words into a `CurrentDialogue` placed on screen.
enum DialogueBuilder {
    /// - Parameter frame: the dialogue area in global AppKit screen coordinates.
    static func build(from result: WordOCRResult, frame: CGRect, game: String?, detectSpeaker: Bool) -> CurrentDialogue? {
        var words = result.words
        guard !words.isEmpty else { return nil }

        var speaker: String?
        if detectSpeaker {
            let cleaned = OCRTextCleaner(detectSpeakerLabel: true).clean(result.lines.joined(separator: "\n"))
            if let label = cleaned.speaker, let firstLine = result.lines.first,
               comparable(firstLine) == comparable(label) {
                speaker = label
                words = words.filter { $0.lineIndex != 0 }.map {
                    RawOCRWord(text: $0.text, box: $0.box, confidence: $0.confidence, lineIndex: $0.lineIndex - 1)
                }
            }
        }
        guard !words.isEmpty else { return nil }

        let recognized = words.map { raw in
            RecognizedWord(
                id: UUID(), text: raw.text,
                boundingBox: CGRect(x: frame.minX + raw.box.minX * frame.width,
                                    y: frame.minY + raw.box.minY * frame.height,
                                    width: raw.box.width * frame.width,
                                    height: raw.box.height * frame.height),
                confidence: raw.confidence, lineIndex: raw.lineIndex)
        }
        return CurrentDialogue(fullText: recognized.map(\.text).joined(separator: " "), words: recognized,
                               timestamp: Date(), speaker: speaker, sourceGame: game, regionFrame: frame)
    }

    private static func comparable(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Key used to decide whether two OCR passes show "the same" dialogue:
    /// ignores case, whitespace, punctuation and apostrophe style.
    static func comparisonKey(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// True when the texts differ by at most one character in a long line (OCR flutter).
    static func effectivelySame(_ a: String, _ b: String) -> Bool {
        let x = comparisonKey(a), y = comparisonKey(b)
        if x == y { return true }
        guard x.count >= 20, y.count >= 20, abs(x.count - y.count) <= 1, x.count < 600 else { return false }
        return levenshtein(Array(x), Array(y), limit: 1) <= 1
    }

    private static func levenshtein(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where i <= a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            var rowMin = current[0]
            for j in 1...max(b.count, 1) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return rowMin }
            previous = current
        }
        return previous[b.count]
    }
}
