#!/bin/bash
# Builds build/Tracer-<version>.dmg from a signed release build. Usage: scripts/release.sh [--publish]
# --publish also tags v<version> on main and uploads the DMG to a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true
IDENTITY="${TRACER_SIGN_IDENTITY:-Tracer Local Signing}"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
TAG="v$VERSION"
DMG="build/Tracer-$VERSION.dmg"

if $PUBLISH; then
    git fetch -q origin main --tags
    [[ "$(git branch --show-current)" == "main" ]] || { echo "error: publish from main" >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "error: working tree has uncommitted changes" >&2; exit 1; }
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "error: main isn't in sync with origin/main" >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "error: $TAG already exists; bump CFBundleShortVersionString in Resources/Info.plist" >&2; exit 1; }
fi

scripts/bundle.sh

# Downloaded copies keep Screen Recording permission across updates only if every release has the same signature.
SIGNATURE="$(codesign -dvv build/Tracer.app 2>&1)"
if ! grep -qx "Authority=$IDENTITY" <<< "$SIGNATURE"; then
    echo "error: build/Tracer.app isn't signed with \"$IDENTITY\"; see docs/signing.md" >&2
    exit 1
fi
codesign --verify --strict build/Tracer.app

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Tracer.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Tracer $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
echo "Built $DMG"

if $PUBLISH; then
    gh release create "$TAG" "$DMG" --target main --title "Tracer $VERSION" --generate-notes
fi
