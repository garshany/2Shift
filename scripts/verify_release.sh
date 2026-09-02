#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-TwoShift}"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUNDLE_ID="${BUNDLE_ID:-com.twoshift.app}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="${1:-$ROOT_DIR/dist/release/$APP_NAME-$APP_VERSION.dmg}"
ZIP_PATH="$ROOT_DIR/dist/release/$APP_NAME-$APP_VERSION.zip"
MANIFEST_PATH="$ROOT_DIR/dist/release/$APP_NAME-$APP_VERSION-manifest.txt"

assert_file() {
    if [[ ! -f "$1" ]]; then
        echo "Missing file: $1" >&2
        exit 1
    fi
}

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(plutil -extract "$key" raw -o - "$APP_DIR/Contents/Info.plist")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Info.plist mismatch for $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_manifest_checksum() {
    local artifact_path="$1"
    local artifact_name
    local expected
    local actual

    artifact_name="$(basename "$artifact_path")"
    expected="$(awk -v name="$artifact_name" '$0 == "- " name { getline; getline; print $2 }' "$MANIFEST_PATH")"
    actual="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"

    if [[ -z "$expected" ]]; then
        echo "Manifest does not contain checksum for $artifact_name." >&2
        exit 1
    fi

    if [[ "$expected" != "$actual" ]]; then
        echo "Checksum mismatch for $artifact_name." >&2
        exit 1
    fi
}

assert_file "$APP_DIR/Contents/Info.plist"
assert_file "$ZIP_PATH"
assert_file "$DMG_PATH"
assert_file "$MANIFEST_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
assert_plist_value "CFBundleIdentifier" "$BUNDLE_ID"
assert_plist_value "CFBundleShortVersionString" "$APP_VERSION"
assert_plist_value "CFBundleExecutable" "$APP_NAME"

hdiutil verify "$DMG_PATH" >/dev/null
assert_manifest_checksum "$DMG_PATH"
assert_manifest_checksum "$ZIP_PATH"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --verify --verbose=2 "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
    echo "Skipping DMG signature and Gatekeeper assessment because CODESIGN_IDENTITY is not set."
fi

if command -v xcrun >/dev/null 2>&1 && [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun stapler validate "$DMG_PATH"
fi

echo "Release verification passed."
