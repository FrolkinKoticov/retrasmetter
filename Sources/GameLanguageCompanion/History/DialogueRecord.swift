import Foundation
import SwiftData

@Model
final class DialogueRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var speaker: String?
    var original: String
    var translation: String?
    var game: String?
    var provider: String?
    var isSaved: Bool

    init(original: String, speaker: String? = nil, translation: String? = nil,
         game: String? = nil, provider: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.speaker = speaker
        self.original = original
        self.translation = translation
        self.game = game
        self.provider = provider
        self.isSaved = false
    }
}
