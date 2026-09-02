#!/bin/zsh
set -euo pipefail

# Build a notarized Developer ID DMG for a GitHub Release.
#
# Prereqs:
#   - "Developer ID Application" certificate in the login keychain
#   - notary credentials: xcrun notarytool store-credentials <PROFILE>
#   - (optional) gh authenticated for the release step
#
# Usage:
#   ./scripts/release.sh 0.1.0                 # build + notarize + print DMG
#   ./scripts/release.sh 0.1.0 --notarize-only # reuse an existing dist/ build
#   ./scripts/release.sh 0.1.0 --gh            # also create the GitHub release
#   NOTARY_PROFILE=NAME ./scripts/release.sh 0.1.0

VERSION="${1:?usage: release.sh <version> [--gh|--notarize-only]}"
MODE="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NOTARY_PROFILE="${NOTARY_PROFILE:-CAPSAWAKE_NOTARY}"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE="$DIST_DIR/CapsAwake.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
APP="$EXPORT_DIR/CapsAwake.app"
DMG="$DIST_DIR/CapsAwake-$VERSION.dmg"
STAGE="$DIST_DIR/dmg-stage"
cd "$ROOT_DIR"

finalize() {
  echo "==> notarize"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json | tee "$DIST_DIR/notary.json"

  echo "==> staple"
  xcrun stapler staple "$DMG"

  echo "==> verify"
  codesign --verify --deep --strict "$APP"
  xcrun stapler validate "$DMG"
  # Local files have no quarantine, so spctl can report "Insufficient Context";
  # the authoritative proof is the notarytool "Accepted" status + the staple.
  spctl --assess --type open --verbose=4 "$DMG" 2>&1 | grep -q accepted && echo "spctl: accepted"

  echo "DMG ready: $DMG"

  if [[ "$MODE" == "--gh" ]]; then
    gh release create "v$VERSION" "$DMG" --title "CapsAwake $VERSION" --generate-notes
  fi
}

if [[ "$MODE" == "--notarize-only" ]]; then
  [[ -f "$DMG" && -d "$APP" ]] || { echo "Run release.sh $VERSION first to build the DMG." >&2; exit 1; }
  finalize
  exit 0
fi

echo "==> archive (Release)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
xcodebuild \
  -project CapsAwake.xcodeproj \
  -scheme CapsAwake \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$ROOT_DIR/.derived" \
  archive > "$DIST_DIR/archive.log" 2>&1 || { tail -40 "$DIST_DIR/archive.log" >&2; exit 1; }

echo "==> export (Developer ID)"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist ExportOptions.plist > "$DIST_DIR/export.log" 2>&1 || { tail -40 "$DIST_DIR/export.log" >&2; exit 1; }

if [[ ! -d "$APP" ]]; then
  echo "Export did not produce $APP" >&2
  exit 1
fi

echo "==> make DMG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/CapsAwake.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "CapsAwake $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

finalize
