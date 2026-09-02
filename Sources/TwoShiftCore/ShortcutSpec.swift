import Foundation

public struct ShortcutModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)
    public static let all: ShortcutModifiers = [.command, .shift, .option, .control]
}

public struct ShortcutSpec: Sendable, Equatable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers

    public static let defaultShortcut = ShortcutSpec(keyCode: 49, modifiers: [.command, .shift])

    public init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    public func matches(keyCode: UInt16, activeModifiers: ShortcutModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == activeModifiers.intersection(.all)
    }

    /// A shortcut is safe to use as a global trigger only when it cannot fire
    /// during normal typing: it needs Cmd/Opt/Ctrl, or must be a function key.
    /// Shift alone is excluded because Shift+letter is regular text input.
    public var isSafeGlobalShortcut: Bool {
        if !modifiers.intersection([.command, .option, .control]).isEmpty {
            return true
        }
        return Self.functionKeyCodes.contains(keyCode)
    }

    /// Validates values restored from persistence (UserDefaults can be edited
    /// externally). Returns nil for out-of-range key codes or unsafe combos.
    public static func sanitized(keyCode: Int, modifiersRawValue: Int) -> ShortcutSpec? {
        guard keyCode >= 0, keyCode <= 0x7F else {
            return nil
        }
        guard modifiersRawValue >= 0, modifiersRawValue <= Int(UInt8.max) else {
            return nil
        }

        let spec = ShortcutSpec(
            keyCode: UInt16(keyCode),
            modifiers: ShortcutModifiers(rawValue: UInt8(modifiersRawValue))
        )
        return spec.isSafeGlobalShortcut ? spec : nil
    }

    /// macOS-conventional symbol order: ⌃⌥⇧⌘.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    public static func keyName(for keyCode: UInt16) -> String {
        if let name = keyNames[keyCode] {
            return name
        }
        return "key \(keyCode)"
    }

    public static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80
    ]

    /// Names follow the ANSI (US) virtual key code layout; letter keys keep
    /// their physical labels regardless of the active input source.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 32: "U", 34: "I", 31: "O", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        76: "Enter", 117: "⌦", 115: "Home", 119: "End",
        116: "PageUp", 121: "PageDown",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19"
    ]
}
