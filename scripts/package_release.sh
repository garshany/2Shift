#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-TwoShift}"
APP_VERSION="${APP_VERSION:-0.2.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION.dmg"
DMG_STAGING="$DIST_DIR/dmg-staging"

mkdir -p "$RELEASE_DIR"

"$ROOT_DIR/scripts/build_app.sh"

rm -f "$ZIP_PATH" "$DMG_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

rm -rf "$DMG_STAGING"

"$ROOT_DIR/scripts/release_manifest.sh" >/dev/null

echo "$ZIP_PATH"
echo "$DMG_PATH"
echo "$RELEASE_DIR/$APP_NAME-$APP_VERSION-manifest.txt"
