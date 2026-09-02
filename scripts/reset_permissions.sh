#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.twoshift.app}"

tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Reset Accessibility and Input Monitoring for $BUNDLE_ID."
echo "Launch TwoShift again and grant both permissions in System Settings."
