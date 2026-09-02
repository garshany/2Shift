#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-TwoShift}"
BUNDLE_ID="${BUNDLE_ID:-com.twoshift.app}"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME.app"
RESET_PERMISSIONS="${RESET_PERMISSIONS:-auto}"

cdhash_for_app() {
    local app_path="$1"
    if [[ ! -d "$app_path" ]]; then
        return 0
    fi

    codesign -dv --verbose=4 "$app_path" 2>&1 | awk -F= '$1 == "CDHash" { print $2; exit }'
}

should_reset_permissions() {
    case "$RESET_PERMISSIONS" in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
        auto)
            [[ -n "${OLD_CDHASH:-}" && -n "${NEW_CDHASH:-}" && "$OLD_CDHASH" != "$NEW_CDHASH" ]]
            return
            ;;
        *)
            echo "RESET_PERMISSIONS must be auto, always, or never." >&2
            exit 1
            ;;
    esac
}

OLD_CDHASH="$(cdhash_for_app "$INSTALL_PATH")"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null
NEW_CDHASH="$(cdhash_for_app "$APP_PATH")"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 0.4
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME"
    sleep 0.4
fi

if [[ -d "$INSTALL_PATH" ]]; then
    BACKUP_PATH="$INSTALL_DIR/$APP_NAME.app.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$INSTALL_PATH" "$BACKUP_PATH"
    echo "Backed up previous app: $BACKUP_PATH"
fi

ditto "$APP_PATH" "$INSTALL_PATH"
codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH" >/dev/null

if should_reset_permissions; then
    "$ROOT_DIR/scripts/reset_permissions.sh" >/dev/null
    if [[ "$RESET_PERMISSIONS" == "always" ]]; then
        echo "Reset macOS permissions for $BUNDLE_ID because RESET_PERMISSIONS=always."
    else
        echo "Reset macOS permissions for $BUNDLE_ID because the app signature changed."
    fi
fi

open "$INSTALL_PATH"

echo "Installed and launched: $INSTALL_PATH"
echo "Permission reset mode: $RESET_PERMISSIONS"
