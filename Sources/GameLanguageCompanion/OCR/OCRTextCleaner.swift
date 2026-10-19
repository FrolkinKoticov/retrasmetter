import Foundation

struct CleanedDialogue: Sendable, Equatable {
    /// Name label shown above the line in many games ("Ryuji"), when detected.
    var speaker: String?
    var text: String
    var isEmpty: Bool { text.isEmpty }
}

/// Turns raw OCR output into one natural sentence/paragraph.
struct OCRTextCleaner: Sendable {
    var detectSpeakerLabel = true

    func clean(_ raw: String) -> CleanedDialogue {
        var lines = raw
            .components(separatedBy: .newlines)
            .map(normalizeLine)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }   // drop icon/noise lines
        lines = removeDuplicateLines(lines)

        var speaker: String?
        if detectSpeakerLabel, lines.count >= 2, looksLikeSpeakerLabel(lines[0]) {
            speaker = lines.removeFirst()
        }

        let text = polish(join(lines))
        return CleanedDialogue(speaker: speaker, text: text)
    }

    // MARK: Steps

    private func normalizeLine(_ line: String) -> String {
        var s = line
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        // Collapse every kind of whitespace run.
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        // A lone "|" is almost always a misread capital I.
        s = s.split(separator: " ", omittingEmptySubsequences: true)
            .map { $0 == "|" ? "I" : String($0) }
            .joined(separator: " ")
        return s
    }

    private func removeDuplicateLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            let key = line.lowercased()
            if seen.insert(key).inserted { result.append(line) }
        }
        return result
    }

    private func looksLikeSpeakerLabel(_ line: String) -> Bool {
        guard line.count <= 24 else { return false }
        let words = line.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }
        if line.contains(where: { ".,!?…:;\"".contains($0) }) { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" }
        }
    }

    private func join(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            if result.isEmpty {
                result = line
            } else if result.hasSuffix("-"), let first = line.first, first.isLowercase {
                result.removeLast()          // hyphenated line break: "some-" + "thing"
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }

    private func polish(_ text: String) -> String {
        var s = text
        for mark in [",", ".", "!", "?", ";", ":"] {
            s = s.replacingOccurrences(of: " \(mark)", with: mark)
        }
        s = s.replacingOccurrences(of: "\u{2026}", with: "...")
        s = collapseRepeatedHalf(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Hello there Hello there" (text rendered twice by a shadow/outline) → "Hello there".
    private func collapseRepeatedHalf(_ text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count >= 2, words.count % 2 == 0 else { return text }
        let half = words.count / 2
        let first = words[..<half].joined(separator: " ")
        let second = words[half...].joined(separator: " ")
        return first.lowercased() == second.lowercased() ? first : text
    }
}
