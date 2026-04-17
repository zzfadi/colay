#!/usr/bin/env bash
# Produces a drag-to-Applications .dmg containing build/colay.app.
# Usage:  scripts/make-dmg.sh <version>
# Output: build/colay-<version>.dmg

set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/colay.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/colay-$VERSION.dmg"

[[ -d "$APP" ]] || { echo "missing $APP"; exit 1; }

echo "==> staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> creating $DMG"
hdiutil create \
  -volname "colay $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "==> done: $DMG"
