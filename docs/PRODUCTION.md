# TwoShift Production Checklist

## Recommended channel

Use direct distribution with Developer ID signing and notarization first.

Mac App Store submission is higher risk for this product because the app needs global keyboard monitoring and synthetic `Cmd+C` / `Cmd+V`. Apple requires App Sandbox for Mac App Store distribution, and sandboxed global-input utilities often need extra review justification or may be rejected.

Relevant Apple docs:

- Developer ID: https://developer.apple.com/support/developer-id/
- Signing Mac software with Developer ID: https://developer.apple.com/developer-id/
- Packaging Mac software for distribution: https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- App Sandbox: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox

## Apple account setup

1. Enroll in the Apple Developer Program.
2. Create or download a `Developer ID Application` certificate.
3. Install the certificate into the login keychain.
4. Create a stable bundle identifier in Apple Developer, then use it for all releases.
5. Store notary credentials:

```bash
xcrun notarytool store-credentials twoshift-notary \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password app-specific-password
```

## Release build

```bash
export BUNDLE_ID=com.yourcompany.twoshift
export APP_VERSION=0.2.0
export BUILD_NUMBER=1
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE=twoshift-notary

scripts/check_core.sh
scripts/preflight_production.sh
scripts/package_release.sh
scripts/notarize_release.sh
scripts/verify_release.sh
```

Primary artifact:

```text
dist/release/TwoShift-0.2.0.dmg
```

Release integrity manifest:

```text
dist/release/TwoShift-0.2.0-manifest.txt
```

Release notes template:

```text
docs/RELEASE_NOTES_0.2.0.md
```

## Manual QA before release

- Fresh install on another Mac or a clean user account.
- First launch shows the `2⇧` menu bar item.
- Permission flow works for Accessibility and Input Monitoring.
- Relaunch after granting permissions keeps the app enabled.
- TextEdit: `ghbdtn` -> `привет`.
- Safari or Chrome text field: `ghbdtn` -> `привет`.
- Telegram: selected text converts.
- VS Code: selected text converts.
- JetBrains IDE: double Shift conflict is acceptable because `Cmd+Shift+Space` works.
- Existing clipboard content is restored after conversion.
- Empty selection converts nothing; with layout switching on it toggles EN <-> RU.
- With layout switching on, `ghbdtn` -> `привет` also leaves the system layout on Russian.
- With only one keyboard layout enabled in System Settings, the trigger still converts and does not hang.
- Turning off "Переключать раскладку системы" restores the old behavior (conversion only).
- Password/secure fields do nothing.
- Launch at Login persists after reboot.

## App Store position

Do not prioritize Mac App Store for the first production release.

Reasons:

- App Sandbox is required for Mac App Store distribution.
- This utility needs input monitoring and synthetic key events.
- The app has a strong privacy-sensitive behavior: temporarily reading selected text via clipboard.

If Mac App Store becomes mandatory, create a separate branch with sandbox entitlements, remove or redesign unsupported global behavior, and prepare a detailed App Review note explaining why the app needs the permissions.
