@preconcurrency import AppKit
import TwoShiftCore

struct KeyboardMonitorConfiguration: Equatable {
    var doubleShiftEnabled: Bool
    var shortcut: ShortcutSpec?

    var hasAnyTrigger: Bool {
        doubleShiftEnabled || shortcut != nil
    }
}

extension CGEventFlags {
    var shortcutModifiers: ShortcutModifiers {
        var result: ShortcutModifiers = []
        if contains(.maskCommand) { result.insert(.command) }
        if contains(.maskShift) { result.insert(.shift) }
        if contains(.maskAlternate) { result.insert(.option) }
        if contains(.maskControl) { result.insert(.control) }
        return result
    }
}

final class KeyboardMonitor {
    private let onShortcut: () -> Void
    private let doublePressInterval: TimeInterval = 0.42
    private let triggerCooldown: TimeInterval = 0.65

    // Read from the event tap callback and written from the main thread; both
    // run on the main run loop, so no extra synchronization is needed.
    private var configuration: KeyboardMonitorConfiguration

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedShiftKeys = Set<Int64>()
    private var lastShiftPressTime: TimeInterval?
    private var cooldownUntil: TimeInterval = 0

    init(configuration: KeyboardMonitorConfiguration, onShortcut: @escaping () -> Void) {
        self.configuration = configuration
        self.onShortcut = onShortcut
    }

    deinit {
        stop()
    }

    func update(configuration: KeyboardMonitorConfiguration) {
        guard self.configuration != configuration else {
            return
        }

        self.configuration = configuration
        pressedShiftKeys.removeAll()
        lastShiftPressTime = nil
    }

    func start() -> Bool {
        if eventTap != nil {
            return true
        }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        pressedShiftKeys.removeAll()
        lastShiftPressTime = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        if type == .keyDown {
            handleKeyDown(event: event)
            return
        }

        guard type == .flagsChanged else {
            return
        }

        handleFlagsChanged(event: event)
    }

    private func handleKeyDown(event: CGEvent) {
        guard let shortcut = configuration.shortcut else {
            return
        }

        let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        if shortcut.matches(keyCode: keyCode, activeModifiers: event.flags.shortcutModifiers) {
            triggerShortcut()
        }
    }

    private func handleFlagsChanged(event: CGEvent) {
        guard configuration.doubleShiftEnabled else {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 56 || keyCode == 60 else {
            return
        }

        let shiftIsDown = event.flags.contains(.maskShift)
        // Count the press only when Shift is the sole modifier, so combos like
        // Cmd+Shift do not accumulate toward the double-Shift gesture.
        if shiftIsDown, event.flags.shortcutModifiers == [.shift], !pressedShiftKeys.contains(keyCode) {
            pressedShiftKeys.insert(keyCode)
            registerShiftPress()
        } else if !shiftIsDown {
            pressedShiftKeys.removeAll()
        }
    }

    private func registerShiftPress() {
        let now = Date.timeIntervalSinceReferenceDate
        defer { lastShiftPressTime = now }

        guard now >= cooldownUntil else {
            return
        }

        if let previous = lastShiftPressTime, now - previous <= doublePressInterval {
            triggerShortcut(now: now)
        }
    }

    private func triggerShortcut(now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        guard now >= cooldownUntil else {
            return
        }

        cooldownUntil = now + triggerCooldown
        lastShiftPressTime = nil
        onShortcut()
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
