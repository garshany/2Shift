@preconcurrency import AppKit

final class PermissionCenter {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isInputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    func requestAccessibilityPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringPermission() {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        openInputMonitoringSettings()
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
