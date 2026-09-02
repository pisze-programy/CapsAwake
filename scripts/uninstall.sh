#!/bin/zsh
set -euo pipefail

# Restore normal sleep behavior and remove CapsAwake: stop the app, unload the
# helper daemon, clear the SleepDisabled flag, and remove app + login item.

APP_NAME="CapsAwake"
BUNDLE_ID="com.piszeprogramy.capsawake"
HELPER_LABEL="$BUNDLE_ID.helper"
APP_BUNDLE="/Applications/$APP_NAME.app"
LOG_DIR="/Library/Logs/CapsAwake"
USER_DEFAULTS="com.piszeprogramy.capsawake"

echo "==> stopping app"
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> unloading helper daemon"
sudo /bin/launchctl bootout system/"$HELPER_LABEL" 2>/dev/null || true

echo "==> restoring normal sleep (clear SleepDisabled)"
sudo /usr/bin/pmset -a disablesleep 0 2>/dev/null || true

echo "==> removing login item (user domain)"
/bin/launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true

echo "==> removing app, logs and defaults"
sudo /bin/rm -rf "$APP_BUNDLE"
sudo /bin/rm -rf "$LOG_DIR"
/usr/bin/defaults delete "$USER_DEFAULTS" 2>/dev/null || true

echo "Uninstalled $APP_NAME. Normal sleep behavior restored."
