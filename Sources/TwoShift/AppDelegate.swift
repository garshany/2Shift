@preconcurrency import AppKit
import ServiceManagement
import TwoShiftCore

extension NSEvent.ModifierFlags {
    var shortcutModifiers: ShortcutModifiers {
        var result: ShortcutModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        return result
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let defaultsEnabledKey = "isEnabled"
    private let onboardingCompletedKey = "hasCompletedOnboarding"
    private let permissionCenter = PermissionCenter()
    private let textReplacementService = TextReplacementService(converter: LayoutConverter())
    private let shortcutPreferences = ShortcutPreferences()
    private let inputSourceSwitcher = InputSourceSwitcher()

    private var keyboardMonitor: KeyboardMonitor?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var permissionRefreshTimer: Timer?
    private var isReplacing = false
    private var isRecordingShortcut = false
    private var shortcutCaptureMonitor: Any?
    private var lastRenderState: RenderState?

    private struct RenderState: Equatable {
        var isEnabled: Bool
        var accessibilityTrusted: Bool
        var inputMonitoringTrusted: Bool
        var keyboardMonitoringActive: Bool
        var launchAtLoginEnabled: Bool
        var doubleShiftEnabled: Bool
        var customShortcutEnabled: Bool
        var customShortcut: ShortcutSpec
        var inputSourceSwitchEnabled: Bool
    }

    private lazy var appState = AppState(
        isEnabled: defaults.object(forKey: defaultsEnabledKey) as? Bool ?? true,
        accessibilityTrusted: permissionCenter.isAccessibilityTrusted,
        inputMonitoringTrusted: permissionCenter.isInputMonitoringTrusted,
        keyboardMonitoringActive: false,
        launchAtLoginEnabled: LoginItemController.isEnabled
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureKeyboardMonitor()
        refreshPermissions()

        let onboardingCompleted = defaults.bool(forKey: onboardingCompletedKey)
        if !onboardingCompleted || !appState.accessibilityTrusted || !appState.inputMonitoringTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openOnboarding()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPermissionRefreshTimer()
        removeShortcutCaptureMonitor()
        keyboardMonitor?.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "2⇧"
        item.button?.toolTip = "TwoShift"
        statusItem = item
        rebuildMenu()
    }

    private func configureKeyboardMonitor() {
        keyboardMonitor = KeyboardMonitor(
            configuration: shortcutPreferences.monitorConfiguration,
            onShortcut: { [weak self] in
                DispatchQueue.main.async {
                    self?.replaceSelectionFromShortcut()
                }
            }
        )
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(
            title: appState.isEnabled ? "Выключить" : "Включить",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = appState.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let convertItem = NSMenuItem(
            title: "Исправить выделенное",
            action: #selector(convertSelectionNow),
            keyEquivalent: ""
        )
        convertItem.target = self
        convertItem.isEnabled = appState.isEnabled
        menu.addItem(convertItem)

        let hotkeyInfoItem = NSMenuItem(
            title: "Горячие клавиши: \(shortcutPreferences.triggerSummary)",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyInfoItem.isEnabled = false
        menu.addItem(hotkeyInfoItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Настройки...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(
            title: "Помощник настройки...",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        let aboutItem = NSMenuItem(
            title: "О TwoShift...",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let accessibilityItem = NSMenuItem(
            title: appState.accessibilityTrusted ? "Доступность: разрешено" : "Доступность: нужно разрешение",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        accessibilityItem.state = appState.accessibilityTrusted ? .on : .off
        menu.addItem(accessibilityItem)

        let inputMonitoringItem = NSMenuItem(
            title: appState.inputMonitoringTrusted ? "Мониторинг ввода: разрешено" : "Мониторинг ввода: нужно разрешение",
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        inputMonitoringItem.target = self
        inputMonitoringItem.state = appState.inputMonitoringTrusted ? .on : .off
        menu.addItem(inputMonitoringItem)

        let loginItem = NSMenuItem(
            title: "Запускать при входе",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = appState.launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Выйти из TwoShift",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - State sync

    private func setEnabled(_ enabled: Bool) {
        appState.isEnabled = enabled
        defaults.set(enabled, forKey: defaultsEnabledKey)
        syncKeyboardMonitor()
        renderIfNeeded()
    }

    private func syncKeyboardMonitor() {
        let configuration = shortcutPreferences.monitorConfiguration
        keyboardMonitor?.update(configuration: configuration)

        let wantsMonitoring = appState.isEnabled
            && appState.inputMonitoringTrusted
            && configuration.hasAnyTrigger

        if wantsMonitoring {
            appState.keyboardMonitoringActive = keyboardMonitor?.start() ?? false
        } else {
            keyboardMonitor?.stop()
            appState.keyboardMonitoringActive = false
        }
    }

    private func refreshPermissions() {
        appState.accessibilityTrusted = permissionCenter.isAccessibilityTrusted
        appState.inputMonitoringTrusted = permissionCenter.isInputMonitoringTrusted
        appState.launchAtLoginEnabled = LoginItemController.isEnabled
        syncKeyboardMonitor()
        renderIfNeeded()
        updatePermissionRefreshTimer()
    }

    private func currentRenderState() -> RenderState {
        RenderState(
            isEnabled: appState.isEnabled,
            accessibilityTrusted: appState.accessibilityTrusted,
            inputMonitoringTrusted: appState.inputMonitoringTrusted,
            keyboardMonitoringActive: appState.keyboardMonitoringActive,
            launchAtLoginEnabled: appState.launchAtLoginEnabled,
            doubleShiftEnabled: shortcutPreferences.isDoubleShiftEnabled,
            customShortcutEnabled: shortcutPreferences.isCustomShortcutEnabled,
            customShortcut: shortcutPreferences.customShortcut,
            inputSourceSwitchEnabled: shortcutPreferences.isInputSourceSwitchEnabled
        )
    }

    /// Rebuilds windows and the menu only when visible state actually changed,
    /// so the 1-second permission poll does not reset focus every tick.
    private func renderIfNeeded(force: Bool = false) {
        let state = currentRenderState()
        guard force || state != lastRenderState else {
            return
        }
        lastRenderState = state

        if !isRecordingShortcut {
            settingsWindow?.contentView = makeSettingsContentView()
        }
        onboardingWindow?.contentView = makeOnboardingContentView()
        aboutWindow?.contentView = makeAboutContentView(info: diagnosticsInfo())
        rebuildMenu()
    }

    private func replaceSelectionFromShortcut() {
        guard appState.isEnabled, !isReplacing else {
            return
        }

        isReplacing = true
        defer { isReplacing = false }

        let result = textReplacementService.replaceSelectedText()
        switch result {
        case .missingAccessibilityPermission:
            permissionCenter.requestAccessibilityPermission()
            refreshPermissions()
        case .replaced(let direction):
            switchInputSourceIfNeeded(matching: direction)
        case .noSelection, .unchanged:
            // Nothing was converted, so there is no direction to follow:
            // fall back to a plain EN <-> RU toggle.
            switchInputSourceIfNeeded(matching: nil)
        }
    }

    /// Aligns the system keyboard layout with the conversion that just ran.
    /// Failures are silent by design: the layout is a convenience on top of
    /// the replacement, and the replacement has already succeeded.
    private func switchInputSourceIfNeeded(matching direction: ConversionDirection?) {
        guard shortcutPreferences.isInputSourceSwitchEnabled else {
            return
        }

        if let direction {
            inputSourceSwitcher.selectLayout(for: direction)
        } else {
            inputSourceSwitcher.toggleLayout()
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        setEnabled(!appState.isEnabled)
    }

    @objc private func convertSelectionNow() {
        replaceSelectionFromShortcut()
    }

    @objc private func openSettings() {
        refreshPermissions()

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки TwoShift"
        window.center()
        window.contentView = makeSettingsContentView()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        updatePermissionRefreshTimer()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        refreshPermissions()

        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "О TwoShift"
        window.center()
        window.contentView = makeAboutContentView(info: diagnosticsInfo())
        window.isReleasedWhenClosed = false
        window.delegate = self
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openOnboarding() {
        refreshPermissions()

        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройка TwoShift"
        window.center()
        window.contentView = makeOnboardingContentView()
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window
        updatePermissionRefreshTimer()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestAccessibilityPermission() {
        permissionCenter.requestAccessibilityPermission()
        refreshPermissions()
    }

    @objc private func openAccessibilitySettings() {
        permissionCenter.openAccessibilitySettings()
        refreshPermissions()
    }

    @objc private func openInputMonitoringSettings() {
        permissionCenter.requestInputMonitoringPermission()
        refreshPermissions()
    }

    @objc private func continuePermissionSetup() {
        refreshPermissions()

        if !appState.accessibilityTrusted {
            permissionCenter.requestAccessibilityPermission()
            permissionCenter.openAccessibilitySettings()
            startPermissionRefreshTimer()
            return
        }

        if !appState.inputMonitoringTrusted {
            permissionCenter.requestInputMonitoringPermission()
            startPermissionRefreshTimer()
            return
        }

        if needsRelaunchForMonitoring {
            relaunchApplication()
            return
        }

        refreshPermissions()
    }

    @objc private func onboardingPrimaryAction() {
        refreshPermissions()

        if !appState.accessibilityTrusted {
            permissionCenter.requestAccessibilityPermission()
            permissionCenter.openAccessibilitySettings()
            startPermissionRefreshTimer()
            return
        }

        if !appState.inputMonitoringTrusted {
            permissionCenter.requestInputMonitoringPermission()
            startPermissionRefreshTimer()
            return
        }

        if needsRelaunchForMonitoring {
            relaunchApplication()
            return
        }

        completeOnboarding()
    }

    private func completeOnboarding() {
        defaults.set(true, forKey: onboardingCompletedKey)
        onboardingWindow?.close()
    }

    @objc private func relaunchApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]

        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            showAlert(title: "Не удалось перезапустить TwoShift", message: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!appState.launchAtLoginEnabled)
    }

    @objc private func setEnabledFromCheckbox(_ sender: NSButton) {
        setEnabled(sender.state == .on)
    }

    @objc private func setLaunchAtLoginFromCheckbox(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }

    @objc private func setDoubleShiftFromCheckbox(_ sender: NSButton) {
        shortcutPreferences.isDoubleShiftEnabled = sender.state == .on
        syncKeyboardMonitor()
        renderIfNeeded()
    }

    @objc private func setInputSourceSwitchFromCheckbox(_ sender: NSButton) {
        shortcutPreferences.isInputSourceSwitchEnabled = sender.state == .on
        renderIfNeeded()
    }

    @objc private func setCustomShortcutEnabledFromCheckbox(_ sender: NSButton) {
        shortcutPreferences.isCustomShortcutEnabled = sender.state == .on
        syncKeyboardMonitor()
        renderIfNeeded()
    }

    @objc private func refreshPermissionsFromButton() {
        refreshPermissions()
    }

    @objc private func refreshPermissionsFromTimer() {
        refreshPermissions()
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsInfo().text, forType: .string)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemController.setEnabled(enabled)
            appState.launchAtLoginEnabled = LoginItemController.isEnabled
            renderIfNeeded()
        } catch {
            showAlert(title: "Не удалось включить автозапуск", message: error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Shortcut recording

    @objc private func beginShortcutCapture() {
        guard !isRecordingShortcut else {
            return
        }

        isRecordingShortcut = true
        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The local monitor always fires on the main thread, but NSEvent is
            // not Sendable, so only plain values cross into the actor context.
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.shortcutModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handleShortcutCapture(keyCode: keyCode, modifiers: modifiers) ?? false
            }
            return consumed ? nil : event
        }
        settingsWindow?.contentView = makeSettingsContentView()
    }

    /// Returns true when the event was consumed by the recorder.
    private func handleShortcutCapture(keyCode: UInt16, modifiers: ShortcutModifiers) -> Bool {
        guard isRecordingShortcut else {
            return false
        }

        if keyCode == 53, modifiers.isEmpty {
            endShortcutCapture()
            return true
        }

        let candidate = ShortcutSpec(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isSafeGlobalShortcut else {
            NSSound.beep()
            return true
        }

        shortcutPreferences.customShortcut = candidate
        shortcutPreferences.isCustomShortcutEnabled = true
        endShortcutCapture()
        syncKeyboardMonitor()
        renderIfNeeded(force: true)
        return true
    }

    private func endShortcutCapture() {
        removeShortcutCaptureMonitor()
        isRecordingShortcut = false
        settingsWindow?.contentView = makeSettingsContentView()
    }

    private func removeShortcutCaptureMonitor() {
        if let shortcutCaptureMonitor {
            NSEvent.removeMonitor(shortcutCaptureMonitor)
        }
        shortcutCaptureMonitor = nil
    }

    // MARK: - Views

    private func makeSettingsContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        let stack = makeVerticalStack(spacing: 14)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -22)
        ])

        stack.addArrangedSubview(makeHeader(title: "TwoShift", subtitle: "Конвертер раскладки для выделенного текста.", symbolName: "keyboard"))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeLabel(permissionSetupMessage(), font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        let enabled = NSButton(checkboxWithTitle: "Включено", target: self, action: #selector(setEnabledFromCheckbox(_:)))
        enabled.state = appState.isEnabled ? .on : .off
        stack.addArrangedSubview(enabled)

        let login = NSButton(checkboxWithTitle: "Запускать при входе", target: self, action: #selector(setLaunchAtLoginFromCheckbox(_:)))
        login.state = appState.launchAtLoginEnabled ? .on : .off
        stack.addArrangedSubview(login)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeLabel("Горячие клавиши", font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor))

        let doubleShift = NSButton(
            checkboxWithTitle: "Двойной Shift (два быстрых нажатия)",
            target: self,
            action: #selector(setDoubleShiftFromCheckbox(_:))
        )
        doubleShift.state = shortcutPreferences.isDoubleShiftEnabled ? .on : .off
        stack.addArrangedSubview(doubleShift)

        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 12
        shortcutRow.translatesAutoresizingMaskIntoConstraints = false

        let shortcutCheckbox = NSButton(
            checkboxWithTitle: "Сочетание клавиш:",
            target: self,
            action: #selector(setCustomShortcutEnabledFromCheckbox(_:))
        )
        shortcutCheckbox.state = shortcutPreferences.isCustomShortcutEnabled ? .on : .off
        shortcutRow.addArrangedSubview(shortcutCheckbox)

        let shortcutButton = NSButton(
            title: isRecordingShortcut ? "Нажмите сочетание..." : shortcutPreferences.customShortcut.displayString,
            target: self,
            action: #selector(beginShortcutCapture)
        )
        shortcutButton.bezelStyle = .rounded
        shortcutButton.isEnabled = !isRecordingShortcut
        shortcutRow.addArrangedSubview(shortcutButton)
        stack.addArrangedSubview(shortcutRow)

        let shortcutHint = isRecordingShortcut
            ? "Введите новое сочетание. Нужен ⌘, ⌥ или ⌃ (или F-клавиша). Esc — отмена."
            : "Нажмите на кнопку с сочетанием, чтобы записать новое."
        stack.addArrangedSubview(makeLabel(shortcutHint, font: .systemFont(ofSize: 11), color: .secondaryLabelColor))

        let switchLayout = NSButton(
            checkboxWithTitle: "Переключать раскладку системы",
            target: self,
            action: #selector(setInputSourceSwitchFromCheckbox(_:))
        )
        switchLayout.state = shortcutPreferences.isInputSourceSwitchEnabled ? .on : .off
        stack.addArrangedSubview(switchLayout)
        stack.addArrangedSubview(makeLabel(
            "После конвертации раскладка меняется на язык результата. Если конвертировать нечего — просто переключается EN ⇄ RU.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        ))

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(makePermissionRow(
            title: "Доступность",
            isAllowed: appState.accessibilityTrusted,
            buttonTitle: appState.accessibilityTrusted ? "Открыть" : "Разрешить",
            action: appState.accessibilityTrusted ? #selector(openAccessibilitySettings) : #selector(requestAccessibilityPermission)
        ))

        stack.addArrangedSubview(makePermissionRow(
            title: "Мониторинг ввода",
            isAllowed: appState.inputMonitoringTrusted,
            buttonTitle: appState.inputMonitoringTrusted ? "Открыть" : "Разрешить",
            action: #selector(openInputMonitoringSettings)
        ))

        let setup = NSButton(title: permissionPrimaryButtonTitle(), target: self, action: #selector(continuePermissionSetup))
        setup.bezelStyle = .rounded
        setup.isEnabled = permissionPrimaryButtonEnabled
        stack.addArrangedSubview(setup)

        let refresh = NSButton(title: "Обновить статусы", target: self, action: #selector(refreshPermissionsFromButton))
        refresh.bezelStyle = .rounded
        stack.addArrangedSubview(refresh)

        return container
    }

    private func makeOnboardingContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 560))
        let stack = makeVerticalStack(spacing: 16)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -26)
        ])

        stack.addArrangedSubview(makeHeader(
            title: "Добро пожаловать в TwoShift",
            subtitle: "ghbdtn → привет: исправление текста, набранного не в той раскладке.",
            symbolName: nil
        ))
        stack.addArrangedSubview(makeLabel(
            "Для работы нужны два системных разрешения. Текст обрабатывается только на этом Mac и никуда не отправляется.",
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        ))
        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(makeOnboardingStepRow(
            number: "1",
            title: "Доступность",
            details: "Позволяет скопировать выделенный текст и вставить исправленный (Cmd+C / Cmd+V).",
            isAllowed: appState.accessibilityTrusted,
            buttonTitle: "Разрешить",
            action: #selector(requestAccessibilityPermission)
        ))

        stack.addArrangedSubview(makeOnboardingStepRow(
            number: "2",
            title: "Мониторинг ввода",
            details: "Позволяет заметить двойное нажатие Shift в любом приложении.",
            isAllowed: appState.inputMonitoringTrusted,
            buttonTitle: "Разрешить",
            action: #selector(openInputMonitoringSettings)
        ))

        if needsRelaunchForMonitoring {
            stack.addArrangedSubview(makeOnboardingStepRow(
                number: "3",
                title: "Перезапуск",
                details: "macOS включит слушатель клавиатуры после перезапуска TwoShift.",
                isAllowed: false,
                buttonTitle: "Перезапустить",
                action: #selector(relaunchApplication)
            ))
        }

        stack.addArrangedSubview(separator())

        let login = NSButton(checkboxWithTitle: "Запускать TwoShift при входе в систему", target: self, action: #selector(setLaunchAtLoginFromCheckbox(_:)))
        login.state = appState.launchAtLoginEnabled ? .on : .off
        stack.addArrangedSubview(login)

        if allPermissionsReady {
            stack.addArrangedSubview(makeLabel(
                "Всё готово! Выделите ghbdtn в любом приложении и дважды нажмите Shift.",
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: .systemGreen
            ))
        }

        let primary = NSButton(
            title: allPermissionsReady ? "Готово" : permissionPrimaryButtonTitle(),
            target: self,
            action: #selector(onboardingPrimaryAction)
        )
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        stack.addArrangedSubview(primary)

        return container
    }

    private func makeOnboardingStepRow(
        number: String,
        title: String,
        details: String,
        isAllowed: Bool,
        buttonTitle: String,
        action: Selector
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let numberLabel = makeLabel(number, font: .systemFont(ofSize: 15, weight: .bold), color: isAllowed ? .systemGreen : .labelColor)
        numberLabel.widthAnchor.constraint(equalToConstant: 16).isActive = true
        row.addArrangedSubview(numberLabel)

        let labels = makeVerticalStack(spacing: 3)
        labels.addArrangedSubview(makeLabel(title, font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor))
        let detailsLabel = makeLabel(details, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        detailsLabel.maximumNumberOfLines = 3
        detailsLabel.preferredMaxLayoutWidth = 280
        labels.addArrangedSubview(detailsLabel)
        labels.addArrangedSubview(makeLabel(
            isAllowed ? "Разрешено ✓" : "Нужно разрешение",
            font: .systemFont(ofSize: 11, weight: .medium),
            color: isAllowed ? .systemGreen : .systemOrange
        ))
        row.addArrangedSubview(labels)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        if !isAllowed {
            let button = NSButton(title: buttonTitle, target: self, action: action)
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }

        return row
    }

    private func makeAboutContentView(info: DiagnosticsInfo) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 360))
        let stack = makeVerticalStack(spacing: 16)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -22)
        ])

        stack.addArrangedSubview(makeHeader(title: "TwoShift", subtitle: "Версия \(info.version) (\(info.build))", symbolName: nil))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Bundle ID", value: info.bundleID))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Подпись", value: info.signature))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Доступность", value: info.accessibilityTrusted ? "разрешено" : "нужно разрешение"))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Мониторинг ввода", value: info.inputMonitoringTrusted ? "разрешено" : "нужно разрешение"))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Слушатель клавиатуры", value: info.keyboardMonitoringActive ? "активен" : "неактивен"))
        stack.addArrangedSubview(makeDiagnosticRow(title: "Автозапуск", value: info.launchAtLoginEnabled ? "включен" : "выключен"))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeLabel("Горячие клавиши: \(shortcutPreferences.triggerSummary).", font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        let copy = NSButton(title: "Скопировать диагностику", target: self, action: #selector(copyDiagnostics))
        copy.bezelStyle = .rounded
        stack.addArrangedSubview(copy)

        return container
    }

    private func makeHeader(title: String, subtitle: String, symbolName: String?) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let image: NSImage
        if let symbolName, let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image = symbol
        } else {
            image = NSApp.applicationIconImage
        }

        let imageView = NSImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 42).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 42).isActive = true
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        stack.addArrangedSubview(imageView)

        let labels = makeVerticalStack(spacing: 4)
        labels.addArrangedSubview(makeLabel(title, font: .systemFont(ofSize: 22, weight: .semibold), color: .labelColor))
        labels.addArrangedSubview(makeLabel(subtitle, font: .systemFont(ofSize: 13), color: .secondaryLabelColor))
        stack.addArrangedSubview(labels)

        return stack
    }

    private func makePermissionRow(title: String, isAllowed: Bool, buttonTitle: String, action: Selector) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let labels = makeVerticalStack(spacing: 2)
        labels.addArrangedSubview(makeLabel(title, font: .systemFont(ofSize: 13), color: .labelColor))
        labels.addArrangedSubview(makeLabel(isAllowed ? "Разрешено" : "Нужно разрешение", font: .systemFont(ofSize: 11), color: isAllowed ? .systemGreen : .systemOrange))
        row.addArrangedSubview(labels)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded
        row.addArrangedSubview(button)

        return row
    }

    private func makeDiagnosticRow(title: String, value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true
        row.addArrangedSubview(titleLabel)

        let valueLabel = makeLabel(value, font: .systemFont(ofSize: 13), color: .labelColor)
        valueLabel.isSelectable = true
        row.addArrangedSubview(valueLabel)

        return row
    }

    private func makeVerticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        return label
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    // MARK: - Permission helpers

    private var needsRelaunchForMonitoring: Bool {
        appState.isEnabled
            && appState.inputMonitoringTrusted
            && shortcutPreferences.monitorConfiguration.hasAnyTrigger
            && !appState.keyboardMonitoringActive
    }

    private var allPermissionsReady: Bool {
        appState.accessibilityTrusted
            && appState.inputMonitoringTrusted
            && !needsRelaunchForMonitoring
    }

    private var permissionPrimaryButtonEnabled: Bool {
        !appState.accessibilityTrusted ||
            !appState.inputMonitoringTrusted ||
            needsRelaunchForMonitoring
    }

    private func permissionPrimaryButtonTitle() -> String {
        if !appState.accessibilityTrusted {
            return "Разрешить Доступность"
        }

        if !appState.inputMonitoringTrusted {
            return "Разрешить Мониторинг ввода"
        }

        if needsRelaunchForMonitoring {
            return "Перезапустить TwoShift"
        }

        return "Готово"
    }

    private func permissionSetupMessage() -> String {
        if !appState.accessibilityTrusted {
            return "Шаг 1 из 2: разрешите Доступность, чтобы TwoShift мог заменить выделенный текст."
        }

        if !appState.inputMonitoringTrusted {
            return "Шаг 2 из 2: разрешите Мониторинг ввода, чтобы срабатывал двойной Shift."
        }

        if needsRelaunchForMonitoring {
            return "Разрешения выданы, но macOS не запустила слушатель клавиатуры. Нужен быстрый перезапуск TwoShift."
        }

        return "Разрешения выданы. Горячие клавиши: \(shortcutPreferences.triggerSummary)."
    }

    private func needsPermissionRefreshTimer() -> Bool {
        (settingsWindow != nil || onboardingWindow != nil) && permissionPrimaryButtonEnabled
    }

    private func updatePermissionRefreshTimer() {
        if needsPermissionRefreshTimer() {
            startPermissionRefreshTimer()
        } else {
            stopPermissionRefreshTimer()
        }
    }

    private func startPermissionRefreshTimer() {
        guard permissionRefreshTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshPermissionsFromTimer),
            userInfo: nil,
            repeats: true
        )
        permissionRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }

    private func diagnosticsInfo() -> DiagnosticsInfo {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let signature = CodeSignatureInfo.current()

        return DiagnosticsInfo(
            version: version,
            build: build,
            bundleID: bundleID,
            accessibilityTrusted: appState.accessibilityTrusted,
            inputMonitoringTrusted: appState.inputMonitoringTrusted,
            keyboardMonitoringActive: appState.keyboardMonitoringActive,
            launchAtLoginEnabled: appState.launchAtLoginEnabled,
            signature: signature
        )
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            if isRecordingShortcut {
                removeShortcutCaptureMonitor()
                isRecordingShortcut = false
            }
            settingsWindow = nil
            updatePermissionRefreshTimer()
        }

        if notification.object as? NSWindow === aboutWindow {
            aboutWindow = nil
        }

        if notification.object as? NSWindow === onboardingWindow {
            onboardingWindow = nil
            if allPermissionsReady {
                defaults.set(true, forKey: onboardingCompletedKey)
            }
            updatePermissionRefreshTimer()
        }
    }
}
