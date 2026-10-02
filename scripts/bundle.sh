#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product VisaGames
bundle=".build/Visa Games.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Vehicles" "$bundle/Contents/Resources/Props" \
  "$bundle/Contents/Resources/Fonts"
cp .build/release/VisaGames "$bundle/Contents/MacOS/VisaGames"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
# Stampy app icon (CFBundleIconFile = AppIcon).
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
fi
# Illustrated vehicle heroes (all child-visible kinds) + soft world props.
if [ -d Resources/Vehicles ]; then
  cp Resources/Vehicles/*.png "$bundle/Contents/Resources/Vehicles/" 2>/dev/null || true
fi
if [ -d Resources/Props ]; then
  cp Resources/Props/*.png "$bundle/Contents/Resources/Props/" 2>/dev/null || true
fi
# Canvas fonts (SIL OFL 1.1) travel with their licence files; a missing font fails the bundle.
cp Resources/Fonts/*.ttf Resources/Fonts/OFL-*.txt "$bundle/Contents/Resources/Fonts/"
codesign --force --sign - "$bundle"
printf '%s\n' "Built $bundle"
