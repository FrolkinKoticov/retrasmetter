import Foundation
import CoreGraphics

protocol OCRService: Sendable {
    func recognizeText(in image: CGImage) async throws -> String
}

enum OCRError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let message): return tr("Text recognition failed: %@", message)
        }
    }
}
