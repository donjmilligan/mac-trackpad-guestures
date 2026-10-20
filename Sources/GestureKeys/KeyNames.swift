import AppKit
import Carbon
import GestureCore

extension ModifierSet {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.function) { insert(.function) }
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

extension KeyCombo {
    var displayString: String {
        modifiers.symbols + KeyNames.name(for: keyCode)
    }
}

extension GestureAction {
    var displayName: String {
        switch self {
        case let .keyboardShortcut(combo): combo.displayString
        case let .shellCommand(command): "$ " + command
        case let .system(action): action.title
        }
    }
}

enum KeyNames {
    static let arrowKeys: Set<UInt16> = [123, 124, 125, 126]
    /// Keys that real keyboards report with the fn flag set (arrows, F-keys, navigation keys).
    static let functionFlagKeys: Set<UInt16> = arrowKeys.union(special.keys.filter { (96...122).contains($0) || $0 == 64 || $0 == 79 || $0 == 80 || $0 == 90 })

    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 76: "⌤", 71: "⌧",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let name = special[keyCode] { return name }
        return character(for: keyCode) ?? "key \(keyCode)"
    }

    /// The character the key produces on the current keyboard layout, ignoring modifiers.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string.uppercased()
    }
}
