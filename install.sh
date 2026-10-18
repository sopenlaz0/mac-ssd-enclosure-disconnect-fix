#!/bin/zsh
# Install the fix: copy RTL9210ForceBOT.kext to /Library/Extensions and ask macOS to load it.
# Read the README first: Apple Silicon Macs need lowered security settings for this to load.
set -euo pipefail

HERE="${0:A:h}"
KEXT="RTL9210ForceBOT.kext"
DEST="/Library/Extensions/$KEXT"

[[ -d "$HERE/$KEXT" ]] || { echo "error: $KEXT not found next to this script" >&2; exit 1; }
plutil -lint "$HERE/$KEXT/Contents/Info.plist" >/dev/null

echo "Copying the fix into /Library/Extensions (your Mac password is needed)..."
sudo rm -rf "$DEST"
sudo cp -R "$HERE/$KEXT" "$DEST"
sudo chown -R root:wheel "$DEST"
sudo chmod -R 755 "$DEST"

echo "Asking macOS to load it..."
set +e
sudo kmutil load -p "$DEST"
rc=$?
set -e

case $rc in
  0)  echo "✅ Loaded. Unplug and replug your enclosure, then run ./check.sh" ;;
  27) echo "👉 macOS needs your approval: open System Settings > Privacy & Security,"
      echo "   allow the blocked software, restart, then run ./check.sh" ;;
  28) echo "👉 Restart your Mac to finish, then replug the enclosure and run ./check.sh" ;;
  *)  echo "❌ macOS refused to load it (kmutil exit code $rc)." >&2
      echo "   This usually means your security settings still block it. See the README." >&2
      exit "$rc" ;;
esac
