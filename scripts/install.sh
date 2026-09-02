#!/bin/zsh
set -euo pipefail

# Build, sign and install CapsAwake.app into /Applications, then launch it once.
# First launch registers the privileged helper daemon (SMAppService) and the
# login item; the daemon may need one-time approval in System Settings →
# General → Login Items & Extensions (the app offers to open it).

APP_NAME="CapsAwake"
BUNDLE_ID="com.piszeprogramy.capsawake"
HELPER_LABEL="$BUNDLE_ID.helper"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="/Applications/$APP_NAME.app"
LOG_DIR="/Library/Logs/CapsAwake"

echo "==> building signed app"
BUILT="$("$ROOT_DIR/scripts/build-app.sh" | /usr/bin/tail -1)"

echo "==> stopping running instance (so the new binary is the one that starts)"
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> unloading any running helper (forces a fresh daemon for the new build)"
sudo /bin/launchctl bootout system/"$HELPER_LABEL" 2>/dev/null || true

echo "==> installing to /Applications"
sudo /bin/mkdir -p "$LOG_DIR"
sudo /bin/rm -rf "$APP_BUNDLE"
sudo /usr/bin/ditto "$BUILT" "$APP_BUNDLE"
sudo /usr/sbin/chown -R root:wheel "$APP_BUNDLE" "$LOG_DIR"
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "==> launching (approve the helper in System Settings if prompted)"
/usr/bin/open "$APP_BUNDLE"

echo "Installed $APP_NAME. The status dot appears in the menu bar."
