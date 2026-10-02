#!/bin/sh
# Rebuild Resources/AppIcon.icns from Resources/AppIcon.iconset (macOS only).
set -eu
cd "$(dirname "$0")/.."
ICONSET="Resources/AppIcon.iconset"
OUT="Resources/AppIcon.icns"
if [ ! -d "$ICONSET" ]; then
  echo "error: missing $ICONSET" >&2
  exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
  echo "error: iconutil not found (macOS required)" >&2
  exit 1
fi
iconutil -c icns "$ICONSET" -o "$OUT"
ls -la "$OUT"
