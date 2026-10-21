#!/bin/bash
set -euo pipefail

# Update the Homebrew cask in ff2248/homebrew-tunneldeck. Used by release.yml after the DMG upload.
#
# Usage: scripts/update_homebrew_cask.sh <version> <sha256>
#   version  semver without the "v" prefix (e.g. 1.0.0)
#   sha256   hex digest of the DMG

VERSION="${1:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"
SHA256="${2:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"

command -v brew >/dev/null || { echo "Error: brew not found"; exit 1; }
command -v git >/dev/null || { echo "Error: git not found"; exit 1; }

REPO="${TAP_REPO:-git@github.com:ff2248/homebrew-tunneldeck.git}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone "$REPO" "$WORK_DIR"
cd "$WORK_DIR"
mkdir -p Casks

cat > Casks/tunneldeck.rb << CASK
cask "tunneldeck" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/ff2248/TunnelDeck/releases/download/v#{version}/TunnelDeck-v#{version}.dmg"
  name "TunnelDeck"
  desc "Menu bar manager for SSH local port forwards"
  homepage "https://github.com/ff2248/TunnelDeck"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "TunnelDeck.app"

  uninstall quit: "io.github.ff2248.tunneldeck"

  zap trash: [
    "~/Library/Application Support/TunnelDeck",
    "~/Library/Preferences/io.github.ff2248.tunneldeck.plist",
  ]
end
CASK

HOMEBREW_NO_AUTO_UPDATE=1 brew style --fix Casks/tunneldeck.rb

if [[ "${DRY_RUN:-}" == 1 ]]; then
  cat Casks/tunneldeck.rb
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/tunneldeck.rb
git diff --cached --quiet || { git commit -m "Update TunnelDeck to ${VERSION}" && git push; }
