#!/bin/bash
# Builds build/Tracer.app and signs it. Usage: scripts/bundle.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug
IDENTITY="${TRACER_SIGN_IDENTITY:-Tracer Local Signing}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Tracer"

APP=build/Tracer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tracer"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found; ad-hoc signing (Screen Recording will be re-asked after each build). See docs/signing.md." >&2
    codesign --force --options runtime --sign - "$APP"
fi
echo "Built $APP"
