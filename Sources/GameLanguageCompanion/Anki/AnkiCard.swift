import Foundation

/// A note ready to be sent to Anki. Field *values* are ordered (first = front/text,
/// second = back/extra); the service maps them onto the note type's real field names, so
/// localized or custom note types work too.
struct AnkiCard: Sendable, Equatable {
    var deck: String
    var model: String
    var fieldValues: [String]
    var tags: [String]
}
