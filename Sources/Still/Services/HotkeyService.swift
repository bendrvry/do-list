import AppKit
import Carbon.HIToolbox
import StillCore

/// Registers the system-wide show/hide shortcut.
///
/// Uses Carbon's `RegisterEventHotKey`, which delivers the key combination to this app
/// without Accessibility or Input Monitoring permission and without seeing any other
/// keystrokes.
@MainActor
@Observable
final class HotkeyService {
    enum Status: Equatable {
        case registered(KeyCombo)
        case disabled
        /// The system refused the combination, usually because another app owns it.
        case unavailable(KeyCombo)
    }

    private(set) var status: Status = .disabled
    @ObservationIgnored var onPress: (() -> Void)?

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5354_494C // "STIL"

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            // Carbon dispatches hot key events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }

    @discardableResult
    func register(_ combo: KeyCombo?) -> Status {
        unregister()
        guard let combo else {
            status = .disabled
            return status
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let result = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let ref {
            hotKeyRef = ref
            status = .registered(combo)
        } else {
            status = .unavailable(combo)
        }
        return status
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

extension KeyCombo {
    /// Builds a combo from an AppKit key event, or `nil` if it lacks a ⌘ or ⌃ modifier
    /// (macOS no longer allows global shortcuts that use only ⌥ and ⇧).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= KeyCombo.commandMask }
        if flags.contains(.option) { carbon |= KeyCombo.optionMask }
        if flags.contains(.control) { carbon |= KeyCombo.controlMask }
        if flags.contains(.shift) { carbon |= KeyCombo.shiftMask }
        guard carbon & (KeyCombo.commandMask | KeyCombo.controlMask) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    /// e.g. "⌃⌥T"
    var displayString: String {
        var result = ""
        if modifiers & KeyCombo.controlMask != 0 { result += "⌃" }
        if modifiers & KeyCombo.optionMask != 0 { result += "⌥" }
        if modifiers & KeyCombo.shiftMask != 0 { result += "⇧" }
        if modifiers & KeyCombo.commandMask != 0 { result += "⌘" }
        return result + Self.keyName(for: keyCode)
    }

    /// Spoken form for VoiceOver, e.g. "Control Option T".
    var accessibilityName: String {
        var parts: [String] = []
        if modifiers & KeyCombo.controlMask != 0 { parts.append("Control") }
        if modifiers & KeyCombo.optionMask != 0 { parts.append("Option") }
        if modifiers & KeyCombo.shiftMask != 0 { parts.append("Shift") }
        if modifiers & KeyCombo.commandMask != 0 { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// The character the key produces on the current keyboard layout.
    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
