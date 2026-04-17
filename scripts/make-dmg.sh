#!/usr/bin/env bash
# Build a styled installer DMG with a background image, arrow, and /Applications shortcut.
# Usage:  scripts/make-dmg.sh <version>
# Output: build/colay-<version>.dmg
#
# Uses `create-dmg` (brew install create-dmg) when available for the styled window.
# Falls back to a plain hdiutil UDZO image if create-dmg or the background image
# is missing, so CI + source builds without extras still produce something.

set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/colay.app"
BG="$ROOT/docs/dmg-background.png"
DMG="$ROOT/build/colay-$VERSION.dmg"

[[ -d "$APP" ]] || { echo "missing $APP — run scripts/build-app.sh first"; exit 1; }
rm -f "$DMG"

if command -v create-dmg >/dev/null 2>&1 && [[ -f "$BG" ]]; then
  echo "==> creating styled DMG with create-dmg"
  create-dmg \
    --volname "colay $VERSION" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "colay.app" 135 195 \
    --app-drop-link 405 195 \
    --hide-extension "colay.app" \
    --no-internet-enable \
    "$DMG" \
    "$APP"
else
  echo "==> create-dmg unavailable; falling back to plain UDZO"
  STAGE="$ROOT/build/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "colay $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
fi

echo "==> done: $DMG"
