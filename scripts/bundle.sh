#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product VisaGames
bundle=".build/Visa Games.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Vehicles"
cp .build/release/VisaGames "$bundle/Contents/MacOS/VisaGames"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
# Option 4 hybrid hero PNGs (illustrated); fleet stays procedural in Swift.
if [ -d Resources/Vehicles ]; then
  cp Resources/Vehicles/*.png "$bundle/Contents/Resources/Vehicles/" 2>/dev/null || true
fi
codesign --force --sign - "$bundle"
printf '%s\n' "Built $bundle"
