#!/bin/zsh
set -euo pipefail

# Build CapsAwake.app with Xcode. Signs helper and app automatically with the
# team certificate from project.yml.
#
# IMPORTANT: stdout must contain ONLY the final .app path (install.sh captures
# it). All progress goes to stderr / a log file.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT_DIR/.derived"
BUILD_LOG="$DERIVED/build-app.log"
cd "$ROOT_DIR"

echo "==> xcodebuild (Release)" >&2
mkdir -p "$DERIVED"
if ! xcodebuild \
  -project CapsAwake.xcodeproj \
  -scheme CapsAwake \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build > "$BUILD_LOG" 2>&1; then
  echo "xcodebuild failed. Last lines of $BUILD_LOG:" >&2
  tail -40 "$BUILD_LOG" >&2
  exit 1
fi

APP="$DERIVED/Build/Products/Release/CapsAwake.app"
if [[ ! -d "$APP" ]]; then
  echo "Build did not produce $APP" >&2
  exit 1
fi

if (( $# > 0 )); then
  /bin/rm -rf "$1"
  /usr/bin/ditto "$APP" "$1"
  echo "$1"
else
  echo "$APP"
fi
