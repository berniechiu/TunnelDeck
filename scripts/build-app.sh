#!/bin/bash
# Builds build/TunnelDeck.app from source with an ad-hoc signature and the hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product TunnelDeck
app=build/TunnelDeck.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/TunnelDeck" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --options runtime --sign - "$app"
echo "$app"
