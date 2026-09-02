#!/bin/zsh
set -euo pipefail

# Build CapsAwake.app with Xcode. Signs helper and app automatically with the
# team certificate from project.yml. Output: <repo>/.derived/.../CapsAwake.app,
# or copies it to an optional target path.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT_DIR/.derived"
cd "$ROOT_DIR"

echo "==> xcodebuild (Release)"
xcodebuild \
  -project CapsAwake.xcodeproj \
  -scheme CapsAwake \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

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
