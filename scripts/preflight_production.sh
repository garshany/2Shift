#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-TwoShift}"
APP_VERSION="${APP_VERSION:-0.2.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

status=0

check_ok() {
    printf "OK   %s\n" "$1"
}

check_fail() {
    printf "MISS %s\n" "$1"
    status=1
}

if command -v swift >/dev/null 2>&1; then
    check_ok "Swift toolchain is installed"
else
    check_fail "Swift toolchain is installed"
fi

if command -v hdiutil >/dev/null 2>&1; then
    check_ok "hdiutil is installed"
else
    check_fail "hdiutil is installed"
fi

if command -v xcrun >/dev/null 2>&1 && xcrun notarytool --help >/dev/null 2>&1; then
    check_ok "notarytool is available"
else
    check_fail "notarytool is available"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    if security find-identity -v -p codesigning | grep -F "$CODESIGN_IDENTITY" >/dev/null; then
        check_ok "CODESIGN_IDENTITY exists in keychain"
    else
        check_fail "CODESIGN_IDENTITY exists in keychain"
    fi
else
    check_fail "CODESIGN_IDENTITY is set"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        check_ok "NOTARY_PROFILE can authenticate"
    else
        check_fail "NOTARY_PROFILE can authenticate"
    fi
else
    check_fail "NOTARY_PROFILE is set"
fi

exit "$status"
