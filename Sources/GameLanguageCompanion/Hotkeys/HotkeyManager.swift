import Foundation
import Carbon.HIToolbox

enum HotkeyModifiers: String, CaseIterable, Identifiable {
    case option, controlOption, commandOption, shiftOption, controlShift
    var id: String { rawValue }

    var carbonFlags: UInt32 {
        switch self {
        case .option: return UInt32(optionKey)
        case .controlOption: return UInt32(controlKey | optionKey)
        case .commandOption: return UInt32(cmdKey | optionKey)
        case .shiftOption: return UInt32(shiftKey | optionKey)
        case .controlShift: return UInt32(controlKey | shiftKey)
        }
    }

    var symbols: String {
        switch self {
        case .option: return "⌥"
        case .controlOption: return "⌃⌥"
        case .commandOption: return "⌘⌥"
        case .shiftOption: return "⇧⌥"
        case .controlShift: return "⌃⇧"
        }
    }
}

enum HotkeyKeys {
    /// ANSI virtual key codes for letters.
    static let letterKeyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11,
        "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35,
        "L": 37, "J": 38, "K": 40, "N": 45, "M": 46
    ]
    static var letters: [String] { letterKeyCodes.keys.sorted() }
}

/// System-wide hotkeys via Carbon `RegisterEventHotKey`. Unlike an NSEvent global monitor it
/// needs no Accessibility permission, swallows the key so the game never sees it, and fires
/// without activating this app (so the game keeps keyboard focus).
///
/// Two hotkeys: the main one (toggles Reading Mode) and Escape, which is only registered
/// while Reading Mode is active.
final class HotkeyManager: @unchecked Sendable {
    var onTrigger: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    var onSubtitles: (@MainActor () -> Void)?

    private var mainRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var subtitlesRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private enum ID: UInt32 { case main = 1, escape = 2, subtitles = 3 }

    deinit {
        unregister()
        setEscapeEnabled(false)
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Returns false when macOS refuses the combination (usually: already taken).
    @discardableResult
    func register(key: String, modifiers: HotkeyModifiers) -> Bool {
        unregister()
        guard let keyCode = HotkeyKeys.letterKeyCodes[key.uppercased()], installHandlerIfNeeded() else { return false }
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C4348), id: ID.main.rawValue)   // 'GLCH'
        let status = RegisterEventHotKey(keyCode, modifiers.carbonFlags, hotKeyID,
                                         GetApplicationEventTarget(), 0, &mainRef)
        return status == noErr
    }

    /// Second hotkey: live subtitles on/off. Returns false if macOS refuses the combination.
    @discardableResult
    func registerSubtitles(key: String, modifiers: HotkeyModifiers) -> Bool {
        if let subtitlesRef { UnregisterEventHotKey(subtitlesRef) }
        subtitlesRef = nil
        guard let keyCode = HotkeyKeys.letterKeyCodes[key.uppercased()], installHandlerIfNeeded() else { return false }
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C4348), id: ID.subtitles.rawValue)
        return RegisterEventHotKey(keyCode, modifiers.carbonFlags, hotKeyID,
                                   GetApplicationEventTarget(), 0, &subtitlesRef) == noErr
    }

    func unregister() {
        if let mainRef { UnregisterEventHotKey(mainRef) }
        mainRef = nil
    }

    /// Escape is grabbed only while Reading Mode is on, so it never interferes with the game otherwise.
    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            guard escapeRef == nil, installHandlerIfNeeded() else { return }
            let hotKeyID = EventHotKeyID(signature: OSType(0x474C4348), id: ID.escape.rawValue)
            RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, GetApplicationEventTarget(), 0, &escapeRef)
        } else if let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
    }

    private func installHandlerIfNeeded() -> Bool {
        if handlerRef != nil { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.fire(id: hotKeyID.id)
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        return status == noErr
    }

    private func fire(id: UInt32) {
        let callback: (@MainActor () -> Void)?
        switch id {
        case ID.escape.rawValue: callback = onEscape
        case ID.subtitles.rawValue: callback = onSubtitles
        default: callback = onTrigger
        }
        Task { @MainActor in callback?() }
    }
}
