import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored as a Carbon key code and modifier mask.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// What the key prints, captured when it was recorded ("W", "Space").
    var keyLabel: String

    static let defaultLog = HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey), keyLabel: "W")
    static let defaultToggle = HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey | shiftKey), keyLabel: "W")
    static let defaultQuickLog = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: "Space")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// Builds a shortcut from a key press, or nil if it has no modifier —
    /// a bare letter as a global shortcut would swallow ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mods
        keyLabel = HotKey.label(for: event)
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        if let fKey = [kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                       kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"][Int(event.keyCode)] {
            return fKey
        }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`, which, unlike
/// an event tap, needs no Accessibility permission.
final class HotKeys {
    enum Action: UInt32 {
        case logDefault = 1
        case toggleWidget = 2
        case quickLog = 3
    }

    var onAction: ((Action) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x53495048   // 'SIPH'

    func register(_ bindings: [(Action, HotKey)]) {
        unregister()
        guard !bindings.isEmpty else { return }
        installHandlerIfNeeded()
        for (action, key) in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotKeys.signature, id: action.rawValue)
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotKeys.signature, let action = Action(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKeys.onAction?(action) }
            return noErr
        }, 1, &type, me, &handler)
    }

    deinit { unregister() }
}
