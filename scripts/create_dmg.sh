#!/bin/bash
set -euo pipefail

# Build the DMG installer for TunnelDeck. Used by release.yml.
#
# Usage: scripts/create_dmg.sh <app_path> <output_dmg>

APP_PATH="${1:?Usage: scripts/create_dmg.sh <app_path> <output_dmg>}"
DMG_OUTPUT="${2:?Usage: scripts/create_dmg.sh <app_path> <output_dmg>}"

command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Install via: brew install create-dmg"; exit 1; }

create-dmg \
  --volname "TunnelDeck" \
  --volicon "$(dirname "$0")/../Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --text-size 16 \
  --icon "TunnelDeck.app" 165 190 \
  --app-drop-link 495 190 \
  --hide-extension "TunnelDeck.app" \
  --no-internet-enable \
  "$DMG_OUTPUT" \
  "$APP_PATH"
