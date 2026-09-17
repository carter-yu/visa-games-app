#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product VisaGames
bundle=".build/Visa Games.app"
mkdir -p "$bundle/Contents/MacOS"
cp .build/release/VisaGames "$bundle/Contents/MacOS/VisaGames"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
printf '%s\n' "Built $bundle"
