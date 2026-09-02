import Foundation
import TwoShiftCore

@MainActor
final class ShortcutPreferences {
    private enum Keys {
        static let doubleShiftEnabled = "doubleShiftEnabled"
        static let customShortcutEnabled = "customShortcutEnabled"
        static let customShortcutKeyCode = "customShortcutKeyCode"
        static let customShortcutModifiers = "customShortcutModifiers"
        static let switchInputSourceEnabled = "switchInputSourceEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isDoubleShiftEnabled: Bool {
        get { defaults.object(forKey: Keys.doubleShiftEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.doubleShiftEnabled) }
    }

    var isCustomShortcutEnabled: Bool {
        get { defaults.object(forKey: Keys.customShortcutEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.customShortcutEnabled) }
    }

    /// Whether a trigger also switches the system keyboard layout.
    var isInputSourceSwitchEnabled: Bool {
        get { defaults.object(forKey: Keys.switchInputSourceEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.switchInputSourceEnabled) }
    }

    var customShortcut: ShortcutSpec {
        get {
            guard defaults.object(forKey: Keys.customShortcutKeyCode) != nil else {
                return .defaultShortcut
            }

            let keyCode = defaults.integer(forKey: Keys.customShortcutKeyCode)
            let modifiers = defaults.integer(forKey: Keys.customShortcutModifiers)
            return ShortcutSpec.sanitized(keyCode: keyCode, modifiersRawValue: modifiers) ?? .defaultShortcut
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Keys.customShortcutKeyCode)
            defaults.set(Int(newValue.modifiers.rawValue), forKey: Keys.customShortcutModifiers)
        }
    }

    var monitorConfiguration: KeyboardMonitorConfiguration {
        KeyboardMonitorConfiguration(
            doubleShiftEnabled: isDoubleShiftEnabled,
            shortcut: isCustomShortcutEnabled ? customShortcut : nil
        )
    }

    /// Human summary for menu/about text, e.g. "двойной Shift или ⇧⌘Space".
    var triggerSummary: String {
        var parts: [String] = []
        if isDoubleShiftEnabled {
            parts.append("двойной Shift")
        }
        if isCustomShortcutEnabled {
            parts.append(customShortcut.displayString)
        }
        return parts.isEmpty ? "выключены" : parts.joined(separator: " или ")
    }
}
