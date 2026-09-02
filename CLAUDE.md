# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TwoShift is a macOS menu bar utility (menu item `2⇧`, Swift Package Manager, macOS 13+, Swift 6) that converts selected text between English and Russian keyboard layouts (`ghbdtn` → `привет`). Triggered by double-Shift or `Cmd+Shift+Space` in any app. Fully local, no network; UI strings are in Russian.

## Commands

```bash
scripts/check_core.sh        # run core test suite (swift run TwoShiftCoreCheck)
scripts/build_app.sh         # release build + assemble dist/TwoShift.app (ad-hoc signed without CODESIGN_IDENTITY)
scripts/install_local.sh     # copy dist app to /Applications, auto-reset TCC permissions if signature changed
scripts/package_release.sh   # produce dist/release/*.dmg, *.zip, *-manifest.txt
scripts/preflight_production.sh  # pre-release environment/tooling checks
scripts/notarize_release.sh && scripts/verify_release.sh  # notarization (needs NOTARY_PROFILE)
```

Scripts are parameterized via env vars: `APP_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `BUNDLE_ID`, `CODESIGN_IDENTITY`, `NOTARY_PROFILE`. They pin `SDKROOT` to the CommandLineTools MacOSX15.4 SDK if present and unset.

**Testing:** there is no `swift test` target — `Tests/TwoShiftCoreTests/` is empty. The test suite is the `TwoShiftCoreCheck` executable (`Sources/TwoShiftCoreCheck/main.swift`): sequential `expectEqual` assertions that throw on first failure and print `TwoShiftCoreCheck passed`. Add new core-conversion cases there. GUI-side code (clipboard, event tap) has no automated tests; manual QA checklist lives in `docs/PRODUCTION.md`.

## Architecture

Three SPM targets:

- **TwoShiftCore** — pure, Sendable, AppKit-free library. `LayoutConverter` holds the EN↔RU character pair table (including macOS Russian punctuation: `^`→`,`, `&`→`.`, `#`→`№` etc.) and auto-detects direction by counting Latin vs Cyrillic "score" characters (ties go to englishToRussian). `ShortcutSpec`/`ShortcutModifiers` model the configurable hotkey: exact-modifier matching, ANSI key-name display strings, `sanitized()` validation for values restored from UserDefaults, and the `isSafeGlobalShortcut` rule (needs Cmd/Opt/Ctrl or a function key — Shift alone would fire during typing). Keep this target free of AppKit/CoreGraphics so it stays checkable via TwoShiftCoreCheck.
- **TwoShiftCoreCheck** — the test harness executable (above).
- **TwoShift** — the app. No storyboard/xib; `LSUIElement` background app whose Info.plist is generated inline by `scripts/build_app.sh` (edit the plist there, not in a resource file).

### Conversion pipeline (the flow that matters)

`KeyboardMonitor` (listen-only `CGEvent` tap on the main run loop; configured via `KeyboardMonitorConfiguration` from `ShortcutPreferences` — detects double-Shift within 0.42s (only when Shift is the sole modifier) and/or the user-recorded shortcut with exact modifier match, 0.65s cooldown, re-enables the tap on `tapDisabledByTimeout/ByUserInput`) → `AppDelegate` (MainActor; `isReplacing` flag guards re-entry) → `TextReplacementService.replaceSelectedText()`:

1. Bail out unless `AXIsProcessTrusted()`.
2. `ClipboardSnapshot.capture` the current pasteboard.
3. Send synthetic `Cmd+C` (`KeyboardEventSender`), poll `pasteboard.changeCount` up to 0.45s — no change means no selection; restore snapshot.
4. Convert via `LayoutConverter`; if unchanged, restore snapshot.
5. Write converted text, send synthetic `Cmd+V`, wait 0.18s, restore the original clipboard only if `changeCount` wasn't bumped by someone else.

The timing constants (`copyTimeoutSeconds`, `pasteRestoreDelaySeconds`, double-press interval, cooldown) are deliberate tuning points for slow apps — treat changes to them as behavior changes, not cleanup.

### Permissions model

Two separate TCC permissions, checked by `PermissionCenter`: **Accessibility** (synthetic Cmd+C/V) and **Input Monitoring** (the event tap). macOS ties TCC grants to bundle ID + code signature, so frequent ad-hoc rebuilds invalidate grants — `install_local.sh` compares CDHash and resets TCC (`RESET_PERMISSIONS=auto|always|never`). `AppDelegate` refreshes permission state on activation and via a 1s timer while the settings or onboarding window is open; window content is rebuilt only when a `RenderState` snapshot actually changes (and never mid-recording of a shortcut). First launch (or missing permissions, tracked via `hasCompletedOnboarding`) opens the onboarding assistant: numbered steps for both permissions with live status, a conditional relaunch step (macOS starts the event tap only after relaunch when Input Monitoring was just granted), and a launch-at-login checkbox.

## Distribution constraints

Direct distribution with Developer ID + notarization only — Mac App Store is explicitly deprioritized because App Sandbox conflicts with global input monitoring and synthetic key events (see `docs/PRODUCTION.md`). Secure input fields intentionally don't work; rich text is pasted back as plain text.
