import Foundation

final class AppState {
    var isEnabled: Bool
    var accessibilityTrusted: Bool
    var inputMonitoringTrusted: Bool
    var keyboardMonitoringActive: Bool
    var launchAtLoginEnabled: Bool

    init(
        isEnabled: Bool,
        accessibilityTrusted: Bool,
        inputMonitoringTrusted: Bool,
        keyboardMonitoringActive: Bool,
        launchAtLoginEnabled: Bool
    ) {
        self.isEnabled = isEnabled
        self.accessibilityTrusted = accessibilityTrusted
        self.inputMonitoringTrusted = inputMonitoringTrusted
        self.keyboardMonitoringActive = keyboardMonitoringActive
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
