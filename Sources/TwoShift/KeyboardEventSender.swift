@preconcurrency import AppKit

enum KeyCode {
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
}

enum KeyboardEventSender {
    static func sendCommandKey(virtualKey: CGKeyCode) {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
