@preconcurrency import AppKit
import TwoShiftCore

enum ReplacementResult: Equatable {
    /// Carries the direction so the caller can align the system layout with
    /// the text that was just pasted.
    case replaced(direction: ConversionDirection)
    case noSelection
    case unchanged
    case missingAccessibilityPermission
}

final class TextReplacementService {
    private let converter: LayoutConverter
    private let pasteboard: NSPasteboard
    private let copyTimeoutSeconds: TimeInterval = 0.45
    private let pasteRestoreDelaySeconds: TimeInterval = 0.18

    init(converter: LayoutConverter, pasteboard: NSPasteboard = .general) {
        self.converter = converter
        self.pasteboard = pasteboard
    }

    func replaceSelectedText() -> ReplacementResult {
        guard AXIsProcessTrusted() else {
            return .missingAccessibilityPermission
        }

        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount

        KeyboardEventSender.sendCommandKey(virtualKey: KeyCode.c)

        guard waitForPasteboardChange(after: changeCountBeforeCopy) else {
            snapshot.restore(to: pasteboard)
            return .noSelection
        }

        guard let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty else {
            snapshot.restore(to: pasteboard)
            return .noSelection
        }

        let direction = converter.detectedDirection(for: selectedText)
        let convertedText = converter.converted(selectedText, direction: direction)
        guard let direction, convertedText != selectedText else {
            snapshot.restore(to: pasteboard)
            return .unchanged
        }

        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)
        let temporaryPasteboardChangeCount = pasteboard.changeCount
        KeyboardEventSender.sendCommandKey(virtualKey: KeyCode.v)

        Thread.sleep(forTimeInterval: pasteRestoreDelaySeconds)
        if pasteboard.changeCount == temporaryPasteboardChangeCount {
            snapshot.restore(to: pasteboard)
        }
        return .replaced(direction: direction)
    }

    private func waitForPasteboardChange(after oldChangeCount: Int) -> Bool {
        let deadline = Date().addingTimeInterval(copyTimeoutSeconds)

        while Date() < deadline {
            if pasteboard.changeCount != oldChangeCount {
                return true
            }

            Thread.sleep(forTimeInterval: 0.02)
        }

        return pasteboard.changeCount != oldChangeCount
    }
}
