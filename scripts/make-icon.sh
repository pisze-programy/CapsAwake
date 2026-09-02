#!/bin/zsh
set -euo pipefail

# Renders AppIcon.icns into Resources/ from scripts/make-icon.swift.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> rendering 1024px master"
/usr/bin/swift "$ROOT_DIR/scripts/make-icon.swift" "$TMP/icon_1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

resize() { # source target size
  /usr/bin/sips -z "$3" "$3" "$1" --out "$2" >/dev/null
}

resize "$TMP/icon_1024.png" "$ICONSET/icon_16x16.png" 16
resize "$TMP/icon_1024.png" "$ICONSET/icon_16x16@2x.png" 32
resize "$TMP/icon_1024.png" "$ICONSET/icon_32x32.png" 32
resize "$TMP/icon_1024.png" "$ICONSET/icon_32x32@2x.png" 64
resize "$TMP/icon_1024.png" "$ICONSET/icon_128x128.png" 128
resize "$TMP/icon_1024.png" "$ICONSET/icon_128x128@2x.png" 256
resize "$TMP/icon_1024.png" "$ICONSET/icon_256x256.png" 256
resize "$TMP/icon_1024.png" "$ICONSET/icon_256x256@2x.png" 512
resize "$TMP/icon_1024.png" "$ICONSET/icon_512x512.png" 512
resize "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png" 1024

echo "==> composing icns"
mkdir -p "$ROOT_DIR/Resources"
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
echo "$ROOT_DIR/Resources/AppIcon.icns"
