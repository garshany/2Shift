import Foundation

struct DiagnosticsInfo: Equatable {
    let version: String
    let build: String
    let bundleID: String
    let accessibilityTrusted: Bool
    let inputMonitoringTrusted: Bool
    let keyboardMonitoringActive: Bool
    let launchAtLoginEnabled: Bool
    let signature: String

    var text: String {
        """
        TwoShift \(version) (\(build))
        Bundle ID: \(bundleID)
        Signature: \(signature)
        Accessibility: \(accessibilityTrusted ? "allowed" : "missing")
        Input Monitoring: \(inputMonitoringTrusted ? "allowed" : "missing")
        Keyboard Monitor: \(keyboardMonitoringActive ? "active" : "inactive")
        Launch at Login: \(launchAtLoginEnabled ? "enabled" : "disabled")
        """
    }
}
