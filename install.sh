#!/bin/zsh
# Install the RTL9210ForceBOT codeless kext into /Library/Extensions and stage it for loading.
# Requires: Apple Silicon Macs must first allow third-party kernel extensions (see README).
set -euo pipefail

HERE="${0:A:h}"
KEXT="RTL9210ForceBOT.kext"
DEST="/Library/Extensions/$KEXT"

[[ -d "$HERE/$KEXT" ]] || { echo "error: $KEXT not found next to this script" >&2; exit 1; }
plutil -lint "$HERE/$KEXT/Contents/Info.plist" >/dev/null

echo "Copying $KEXT to /Library/Extensions (admin password required)..."
sudo rm -rf "$DEST"
sudo cp -R "$HERE/$KEXT" "$DEST"
sudo chown -R root:wheel "$DEST"
sudo chmod -R 755 "$DEST"

echo "Asking macOS to load it. If prompted, approve it in"
echo "  System Settings > Privacy & Security (\"System software ... was blocked\"), then reboot."
if sudo kmutil load -p "$DEST"; then
  echo "Loaded. Unplug and replug the enclosure, then run ./verify.sh"
else
  echo
  echo "macOS did not load it yet. This is expected on first install:"
  echo "  1. Approve it in System Settings > Privacy & Security, if the button is there."
  echo "  2. Reboot (macOS rebuilds its auxiliary kernel collection)."
  echo "  3. Replug the enclosure and run ./verify.sh"
fi
