#!/bin/bash
# Convert docs/icon.png (1024x1024) → build/AppIcon.icns
set -euo pipefail

SRC="${1:-docs/icon.png}"
OUT="${2:-build/AppIcon.icns}"

if [ ! -f "$SRC" ]; then
  echo "missing $SRC — run 'swift scripts/make-icon.swift' first" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

for pair in "16:16" "32:16@2x" "32:32" "64:32@2x" "128:128" "256:128@2x" "256:256" "512:256@2x" "512:512" "1024:512@2x"; do
  px="${pair%:*}"
  name="${pair#*:}"
  sips -z "$px" "$px" "$SRC" --out "$ICONSET/icon_${name}.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "==> wrote $OUT"
