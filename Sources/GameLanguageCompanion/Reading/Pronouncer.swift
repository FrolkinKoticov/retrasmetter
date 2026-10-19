import AVFoundation

/// Pronunciation with the built-in system voices (no network, no paid API).
@MainActor
final class Pronouncer {
    static let shared = Pronouncer()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: Language) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
