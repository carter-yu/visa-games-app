#!/bin/sh
# Install the Release bundle to /Applications and refresh a Desktop alias.
# Intended for the family Mac mini after `sh scripts/bundle.sh`.
# Does not merge git; does not launch the kiosk.
set -eu
cd "$(dirname "$0")/.."

APP_NAME="Visa Games.app"
SRC=".build/${APP_NAME}"
DST="/Applications/${APP_NAME}"

if [ ! -d "$SRC" ]; then
  echo "error: missing $SRC — run sh scripts/bundle.sh first" >&2
  exit 1
fi

# Read version from the built Info.plist for the log line.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || echo "?")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC/Contents/Info.plist" 2>/dev/null || echo "?")

echo "Installing $SRC → $DST ($VERSION / $BUILD)"

# Quit a running copy so ditto can replace the bundle cleanly.
if pgrep -x VisaGames >/dev/null 2>&1; then
  echo "Quitting running VisaGames…"
  osascript -e 'tell application "Visa Games" to quit' 2>/dev/null || true
  sleep 1
  pkill -x VisaGames 2>/dev/null || true
  sleep 1
fi

rm -rf "$DST"
ditto "$SRC" "$DST"
# Ad-hoc re-sign after ditto (keeps Gatekeeper happier for local family install).
codesign --force --sign - "$DST" 2>/dev/null || true

# Desktop alias helper (Finder alias, not a symlink).
DESKTOP="${HOME}/Desktop"
ALIAS_NAME="Visa Games"
ALIAS_PATH="${DESKTOP}/${ALIAS_NAME}"
if [ -d "$DESKTOP" ]; then
  # Remove prior alias / symlink / leftover so Finder can recreate.
  rm -rf "$ALIAS_PATH" "${ALIAS_PATH}.app" 2>/dev/null || true
  osascript <<OSA
tell application "Finder"
  try
    set appPOSIX to POSIX file "$DST"
    set deskPOSIX to POSIX file "$DESKTOP"
    make alias file to appPOSIX at deskPOSIX with properties {name:"$ALIAS_NAME"}
  end try
end tell
OSA
  echo "Desktop alias → $ALIAS_PATH"
else
  echo "warn: no Desktop at $DESKTOP — skipped alias" >&2
fi

echo "Installed $DST ($VERSION / $BUILD)"
echo "Launch from Applications or the Desktop alias (not required for this script)."
