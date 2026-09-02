# TwoShift

TwoShift is a small macOS menu bar utility that converts selected text between English and Russian keyboard layouts.

Example:

- `ghbdtn` -> `привет`
- `руддщ` -> `hello`

## MVP behavior

1. Select text in any macOS app.
2. Press `Shift` twice quickly, or press the custom shortcut (default `Cmd+Shift+Space`).
3. TwoShift copies the selection, converts it locally, pastes the result, and restores the previous clipboard contents.

Both triggers are configurable in `2⇧` -> `Настройки...`: the double-Shift gesture can be
toggled, and the shortcut can be re-recorded to any combination that includes `Cmd`, `Opt`,
or `Ctrl` (or a bare function key).

The same trigger also switches the system keyboard layout ("Переключать раскладку системы",
on by default): after a conversion the layout follows the language of the pasted result, and
when there is nothing to convert it simply toggles between the enabled EN and RU layouts.

The app has no server side and does not send text anywhere.
It temporarily reads the selected text through the clipboard, does not log it, and restores the previous clipboard contents after paste.

## Build and local check

```bash
scripts/check_core.sh
scripts/build_app.sh
```

The local `.app` bundle is created at:

```text
dist/TwoShift.app
```

## Package for sharing

```bash
scripts/package_release.sh
```

Artifacts:

- `dist/release/TwoShift-0.2.0.dmg`
- `dist/release/TwoShift-0.2.0.zip`
- `dist/release/TwoShift-0.2.0-manifest.txt`

Without `CODESIGN_IDENTITY`, artifacts are only local/ad-hoc signed and are suitable for alpha testing, not public distribution.

## Production release

See [docs/PRODUCTION.md](docs/PRODUCTION.md).

Short version:

```bash
export BUNDLE_ID=com.yourcompany.twoshift
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE=twoshift-notary

scripts/package_release.sh
scripts/notarize_release.sh
scripts/verify_release.sh
```

Before notarization, run:

```bash
scripts/preflight_production.sh
```

## macOS permissions

TwoShift needs:

- Accessibility, to send `Cmd+C` and `Cmd+V`.
- Input Monitoring, to listen for the global double-Shift gesture.

On first launch TwoShift opens a setup assistant (`Помощник настройки...` in the menu reopens it) that walks through both permissions step by step, shows live status, and offers the relaunch step when macOS requires it.

If the double-Shift listener does not start, open `2⇧` -> `Настройки...` and follow the permission setup button.
The app refreshes permission status automatically while the settings window is open. Relaunch is only needed when the app explicitly shows `Перезапустить TwoShift`.

macOS privacy permissions are tied to the bundle identity and signature. If you rebuild the app often during development, macOS may ask for permissions again.
`scripts/install_local.sh` resets TwoShift's local TCC permissions automatically when an ad-hoc signature change is detected, so System Settings does not keep stale allowed checkmarks from an older build.

User install instructions are in [docs/INSTALL_RU.md](docs/INSTALL_RU.md).
Privacy details are in [docs/PRIVACY.md](docs/PRIVACY.md).

For support diagnostics, open the menu bar item `2⇧` -> `О TwoShift...` -> `Скопировать диагностику`.

## Known MVP limits

- Secure input fields and password fields are intentionally not supported by macOS.
- Some apps copy or paste slower than others; the MVP uses short timeouts and may need tuning.
- Rich text formatting is not preserved; selected text is pasted back as plain text.
- Shortcut key names in the recorder are shown using the ANSI (US) key layout labels.
