#!/bin/bash
# Builds build/Tracer.app and signs it. Usage: scripts/bundle.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug
IDENTITY="${TRACER_SIGN_IDENTITY:-Tracer Local Signing}"

# Own scratch path: a release build in .build breaks swift test's macro plugins.
SCRATCH=build/.swiftpm-build
swift build -c "$CONFIG" --scratch-path "$SCRATCH"
BIN="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)/Tracer"

APP=build/Tracer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tracer"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Not -v: a self-signed identity is "not trusted" yet still signs fine.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found; ad-hoc signing (Screen Recording will be re-asked after each build). See docs/signing.md." >&2
    codesign --force --options runtime --sign - "$APP"
fi
echo "Built $APP"
