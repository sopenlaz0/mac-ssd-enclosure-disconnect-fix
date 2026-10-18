#!/bin/zsh
# Remove the RTL9210ForceBOT codeless kext. Reboot afterwards to fully drop it.
set -euo pipefail

DEST="/Library/Extensions/RTL9210ForceBOT.kext"
if [[ ! -d "$DEST" ]]; then
  echo "Not installed ($DEST missing)."; exit 0
fi
sudo kmutil unload -b io.github.sopenlaz0.RTL9210ForceBOT 2>/dev/null || true
sudo rm -rf "$DEST"
sudo kmutil clear-staging 2>/dev/null || true
echo "Removed. Reboot to return to the default (UAS) behaviour."
