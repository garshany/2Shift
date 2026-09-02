#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-TwoShift}"
APP_VERSION="${APP_VERSION:-0.2.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG_PATH="${1:-$ROOT_DIR/dist/release/$APP_NAME-$APP_VERSION.dmg}"

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile name." >&2
    echo "Example:" >&2
    echo "  xcrun notarytool store-credentials twoshift-notary --apple-id you@example.com --team-id TEAMID --password app-specific-password" >&2
    exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "DMG not found: $DMG_PATH" >&2
    exit 2
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

echo "$DMG_PATH"
