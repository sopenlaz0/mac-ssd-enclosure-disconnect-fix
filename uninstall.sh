#!/bin/zsh
# Remove the fix. Restart afterwards. See the README for restoring full security.
set -euo pipefail

BUNDLE="io.github.sopenlaz0.RTL9210ForceBOT"
DEST="/Library/Extensions/RTL9210ForceBOT.kext"

if [[ ! -d "$DEST" ]]; then
  echo "The fix is not installed ($DEST is missing). Nothing to do."
  exit 0
fi

echo "Removing the fix (your Mac password is needed)..."
sudo kmutil unload -b "$BUNDLE" || echo "(It was not loaded right now; continuing.)"
sudo rm -rf "$DEST"

if [[ -d "$DEST" ]]; then
  echo "❌ Could not remove $DEST" >&2
  exit 1
fi
echo "✅ Removed. Restart your Mac to go back to the default behaviour."
echo "   To restore full security afterwards, see 'Undo everything' in the README."
