#!/usr/bin/env bash
# Codesigns and notarizes build/colay.app if the required environment variables are set.
# Falls back to an ad-hoc signed build (runs locally but triggers the Gatekeeper warning
# for people who download it) when credentials are missing.
#
# Required env for a *trusted* release:
#   DEVELOPER_ID_APPLICATION  — "Developer ID Application: Fadi Alzuabi (TEAMID)"
#   APPLE_ID                  — your Apple developer account email
#   APPLE_ID_PASSWORD         — app-specific password
#   APPLE_TEAM_ID             — 10-char team id
#
# Optional:
#   ENTITLEMENTS              — path to a .entitlements file (default: scripts/colay.entitlements)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/colay.app"
ENT="${ENTITLEMENTS:-$ROOT/scripts/colay.entitlements}"

[[ -d "$APP" ]] || { echo "No app bundle at $APP — run build-app.sh first"; exit 1; }

# iCloud / FileProvider may re-stamp directories inside ~/Desktop, ~/Documents, etc.
# with com.apple.FinderInfo right after we clear them, and codesign --strict rejects
# that. Best fix is to not build inside a synced folder; second best is to strip on
# every file right before signing.
echo "==> stripping xattrs"
find "$APP" -exec xattr -c {} \; 2>/dev/null || true

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "==> no Developer ID; ad-hoc signing (downloaders will see a Gatekeeper warning)"
  codesign --force --deep --sign - --options runtime "$APP"
  exit 0
fi

echo "==> codesigning with $DEVELOPER_ID_APPLICATION"
codesign --force --deep \
  --options runtime \
  --entitlements "$ENT" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  "$APP"

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_ID_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "==> skipping notarization (APPLE_ID / APPLE_ID_PASSWORD / APPLE_TEAM_ID not all set)"
  exit 0
fi

echo "==> zipping for notarization"
ZIP="$ROOT/build/colay.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> submitting to notary service (this blocks until Apple responds)"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "==> stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
echo "==> signed + notarized"
