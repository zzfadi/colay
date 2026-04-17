#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) release binary and wrap it in a macOS .app bundle.
#
# Usage:  scripts/build-app.sh <version>
# Outputs: build/colay.app
#
# Signing is handled by a separate step (scripts/sign-and-notarize.sh) so this script
# works on any dev machine or CI without credentials.

set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="colay"
BUNDLE_ID="com.zzfadi.colay"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> building universal binary ($VERSION)"
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
[[ -f "$BIN" ]] || { echo "binary not found at $BIN"; exit 1; }

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN" "$MACOS_DIR/$APP_NAME"

# Resource bundle SwiftPM generates for Resources/demo.json lives next to the binary.
RES_BUNDLE="$(dirname "$BIN")/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RES_BUNDLE" ]]; then
  cp -R "$RES_BUNDLE" "$RES_DIR/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                    <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>             <string>colay</string>
  <key>CFBundleIdentifier</key>              <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>             <string>APPL</string>
  <key>CFBundleVersion</key>                 <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
  <key>LSMinimumSystemVersion</key>          <string>13.0</string>
  <key>LSUIElement</key>                     <true/>
  <key>NSHighResolutionCapable</key>         <true/>
  <key>NSHumanReadableCopyright</key>        <string>MIT License. See LICENSE.</string>
</dict>
</plist>
PLIST

echo "==> done: $APP_DIR"
