import Vision
import CoreGraphics

/// Local OCR using Apple Vision. No network, no third-party code.
struct VisionOCRService: OCRService {
    var language: Language = .english

    func recognizeText(in image: CGImage) async throws -> String {
        let languageCode = language.visionCode
        return try await Task.detached(priority: .userInitiated) { () throws -> String in
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
            return OCRLineAssembler.assemble(request.results ?? [])
        }.value
    }
}

/// Turns Vision observations into reading-order text. Text boxes that sit on the same
/// visual row (a dialogue split into several boxes) are merged into one line.
enum OCRLineAssembler {
    static func assemble(_ observations: [VNRecognizedTextObservation]) -> String {
        let items: [(box: CGRect, text: String)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            return (observation.boundingBox, candidate.string)
        }
        // Vision's origin is bottom-left, so "top of the image" = larger midY.
        let sorted = items.sorted { $0.box.midY > $1.box.midY }

        var rows: [[(box: CGRect, text: String)]] = []
        for item in sorted {
            if let reference = rows.last?.first,
               abs(reference.box.midY - item.box.midY) < max(reference.box.height, item.box.height) * 0.5 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows
            .map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
