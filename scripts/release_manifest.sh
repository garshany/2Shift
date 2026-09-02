#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-TwoShift}"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.twoshift.app}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION.dmg"
MANIFEST_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION-manifest.txt"

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "Missing file: $1" >&2
        exit 2
    fi
}

require_file "$ZIP_PATH"
require_file "$DMG_PATH"
require_file "$APP_DIR/Contents/Info.plist"

signature_summary="$(codesign -dv "$APP_DIR" 2>&1 | awk -F= '/^Signature=/{print $2}')"
team_identifier="$(codesign -dv "$APP_DIR" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
team_identifier="${team_identifier:-not set}"
signature_summary="${signature_summary:-unknown}"

{
    echo "TwoShift release manifest"
    echo "Generated UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "App name: $APP_NAME"
    echo "Version: $APP_VERSION"
    echo "Build: $BUILD_NUMBER"
    echo "Bundle ID: $BUNDLE_ID"
    echo "Signature: $signature_summary"
    echo "Team ID: $team_identifier"
    echo
    echo "Artifacts:"
    for artifact in "$DMG_PATH" "$ZIP_PATH"; do
        size="$(stat -f%z "$artifact")"
        checksum="$(shasum -a 256 "$artifact" | awk '{print $1}')"
        echo "- $(basename "$artifact")"
        echo "  size: $size"
        echo "  sha256: $checksum"
    done
    echo
    echo "Build host:"
    sw_vers | sed 's/^/  /'
    echo "  $(swift --version 2>&1 | head -n 1)"
} > "$MANIFEST_PATH"

echo "$MANIFEST_PATH"
