#!/bin/zsh
# Show which macOS mass-storage driver is bound to an attached Realtek RTL9210 (0BDA:9210) enclosure.
# Expected after install: IOUSBMassStorageDriver (BOT). Default without the fix: IOUSBMassStorageUASDriver.

echo "== Kext loaded?"
if kmutil showloaded --list-only 2>/dev/null | grep -q io.github.sopenlaz0.RTL9210ForceBOT; then
  echo "yes: io.github.sopenlaz0.RTL9210ForceBOT"
else
  echo "not listed (check the driver below; that is what matters)"
fi

echo "== Driver bound to each RTL9210 (0BDA:9210) enclosure"
# Walk each USB device subtree; report the mass-storage driver class found under Realtek 0x0bda/0x9210.
ioreg -r -c IOUSBHostDevice -l -w0 | awk '
  /^\+-o .*<class IOUSBHostDevice/ { flush(); name=$0; sub(/^\+-o /,"",name); sub(/  <class.*/,"",name); vid=""; pid=""; drv=""; next }
  /"idVendor" = /  && vid=="" { vid=$NF }
  /"idProduct" = / && pid=="" { pid=$NF }
  /<class IOUSBMassStorageUASDriver/ { drv="UAS" }
  /<class IOUSBMassStorageDriver[,>]/ { if (drv=="") drv="BOT" }
  function flush() {
    if (vid==3034 && pid==37392) {
      found=1
      if (drv=="UAS")      { print "UAS  (IOUSBMassStorageUASDriver): fix NOT active  [" name "]"; rc=2 }
      else if (drv=="BOT") { print "BOT  (IOUSBMassStorageDriver): fix active  [" name "]" }
      else                 { print "no mass-storage driver attached yet  [" name "]"; rc=3 }
    }
  }
  END { flush(); if (!found) { print "No RTL9210 (0BDA:9210) enclosure attached. Plug it in and rerun."; exit 1 } exit rc }
'
