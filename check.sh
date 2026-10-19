#!/bin/zsh
# Plain-language check: is the fix installed, and is your RTL9210 (0BDA:9210) enclosure using it?
# Exit codes: 0 = fix active, 1 = no affected enclosure plugged in, 2 = enclosure still in UAS mode, 3 = other.

BUNDLE="io.github.sopenlaz0.RTL9210ForceBOT"
KEXT="/Library/Extensions/RTL9210ForceBOT.kext"

echo "1) Is the fix installed?"
if [[ -d "$KEXT" ]]; then
  if out=$(kmutil showloaded --collection codeless --show all --list-only 2>&1); then
    if grep -q "$BUNDLE" <<<"$out"; then
      echo "   ✅ Installed, and macOS knows about it."
    else
      echo "   ⚠️  Installed, but macOS has not picked it up yet."
      echo "      Approve it in System Settings > Privacy & Security, then restart."
    fi
  else
    echo "   ⚠️  Installed, but macOS could not be asked about it:"
    echo "      $out"
  fi
else
  echo "   ❌ Not installed. Run ./install.sh"
fi

echo
echo "2) Is your enclosure using it?"
# Walk the USB tree at every depth (devices behind hubs included) and attribute each
# storage driver and personality to its nearest USB-device ancestor.
ioreg -r -c IOUSBHostDevice -l -w0 | LC_ALL=C awk -v bundle="$BUNDLE" '
  function pop(ind) { while (sp > 0 && sind[sp] >= ind) sp-- }
  /\+-o / {
    ind = index($0, "+-o"); pop(ind)
    if ($0 ~ /<class IOUSBHostDevice/) {
      name = $0; sub(/.*\+-o /, "", name); sub(/  <class.*/, "", name)
      sp++; sind[sp] = ind; sdev[sp] = name; cur = name
      if (!(name in seen)) { seen[name] = 1; order[++n] = name }
    } else {
      cur = ""; dev = (sp > 0) ? sdev[sp] : ""
      if ($0 ~ /<class IOUSBMassStorageUASDriver/) drv[dev] = "UAS"
      else if ($0 ~ /<class IOUSBMassStorageDriver[,>]/ && drv[dev] == "") drv[dev] = "BOT"
    }
    next
  }
  /"idVendor" = /  { if (cur != "" && !(cur in vid)) vid[cur] = $NF }
  /"idProduct" = / { if (cur != "" && !(cur in pid)) pid[cur] = $NF }
  index($0, "\"IOPersonalityPublisher\" = \"" bundle "\"") { if (sp > 0) ours[sdev[sp]] = 1 }
  END {
    rc = 1
    for (i = 1; i <= n; i++) {
      d = order[i]
      if (vid[d] != 3034 || pid[d] != 37392) continue
      if (drv[d] == "BOT" && ours[d])  { print "   ✅ Yes: " d " is in the stable (BOT) mode, set by this fix."; if (rc != 2) rc = 0 }
      else if (drv[d] == "BOT")        { print "   ℹ️  " d " is in BOT mode, but not because of this fix."; if (rc == 1) rc = 3 }
      else if (drv[d] == "UAS")        { print "   ❌ No: " d " is still in the fast (UAS) mode that can disconnect."; rc = 2 }
      else                             { print "   ⚠️  " d " is plugged in but has no storage driver yet. Replug it."; if (rc == 1) rc = 3 }
    }
    if (rc == 1) print "   No affected enclosure (Realtek 0BDA:9210) is plugged in. Plug it in and run this again."
    exit rc
  }
'
