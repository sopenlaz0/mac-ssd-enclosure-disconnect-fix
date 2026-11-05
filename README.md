# Mac SSD Enclosure Disconnect Fix

A fix for USB SSD enclosures that disconnect from a Mac during large copies. It applies to enclosures built on the Realtek RTL9210 chip, which is used by UGREEN, ORICO, Sabrent and many unbranded brands.

The typical symptom: the drive works fine for small copies, but during a long write (tens of GB) it freezes or disappears, and macOS shows "Disk Not Ejected Properly". The same drive usually works fine on Windows.

## Check whether your enclosure has this chip

1. Plug the enclosure into your Mac.
2. Hold Option, click the Apple menu, and choose System Information.
3. Select USB in the sidebar, then select your enclosure.
4. Check that Vendor ID is `0x0bda` and Product ID is `0x9210`.

If both match, the fix applies to your enclosure. If not, it won't change anything.

You can also run `./check.sh` from this folder.

## What it does

macOS can talk to USB drives in two modes:

- **UAS** is the default. It's faster, but with this chip it can disconnect under heavy writes.
- **BOT** is older and simpler. It's somewhat slower and avoids the UAS-specific failures.

This fix makes macOS use BOT for this chip only. Apple already does the same for about 20 other enclosures; this chip just isn't on Apple's list.

The fix is a single settings file. No code runs, and you can remove it at any time.

## Security trade-off

macOS only loads extensions like this one if you lower your Mac's startup security, so read this before installing.

- On Apple Silicon you need Reduced Security **and** SIP's kext-signing check turned off (`csrutil enable --without kext`). Reduced Security alone is not enough: macOS rejects the fix with "Bad code signature".
- The fix is ad-hoc signed. It has a signature, but not one from an Apple-approved developer, which is why the extra steps are needed.
- The lower security settings apply to your whole Mac, not just this fix.
- Tested on an M4 MacBook Air (macOS 27.0.1): it loads, and two 50 GB writes passed, but the drive still dropped later under Docker. It's an improvement, not a cure. See [Test results](#test-results).

If you'd rather not lower security, see [Alternatives](#alternatives) below.

## Install

### 1. Allow extensions (Apple Silicon Macs)

1. Shut down, then press and hold the power button until you see Loading startup options.
2. Click Options, then go to Utilities → Startup Security Utility.
3. Select your disk, choose Reduced Security, and tick "Allow user management of kernel extensions from identified developers".
4. Go to Utilities → Terminal and run:
   ```bash
   csrutil enable --without kext
   ```
   This turns off only SIP's kext-signing check. Filesystem protection and the rest of SIP stay on. macOS warns that it's an unsupported configuration; that's expected.
5. Restart.

Recovery runs instead of macOS, so keep these steps on your phone or on paper.

### 2. Install the fix

```bash
git clone https://github.com/sopenlaz0/mac-ssd-enclosure-disconnect-fix.git
cd mac-ssd-enclosure-disconnect-fix
./install.sh
```

If it asks, approve it in System Settings → Privacy & Security, then restart.

### 3. Check that it worked

Replug your enclosure, then run:

```bash
./check.sh
```

It should report that your enclosure is in BOT mode, set by this fix.

If the installer says macOS refused it with "Bad code signature" (exit code 29), SIP's kext-signing check is still on. Run `csrutil status`: it should list `Kext Signing: disabled`. If not, repeat step 1.4. If `--without kext` still isn't enough on your Mac, the last option is `csrutil disable`, which turns off all of SIP (Permissive Security), so only do it if you accept the risk. "Undo everything" below explains how to turn it back on.

## Undo everything

1. Remove the fix:
   ```bash
   ./uninstall.sh
   ```
2. Restart.
3. If you changed SIP (`--without kext` or `disable`), boot into Recovery, open Terminal, run `csrutil enable`, and restart. `csrutil status` should then say enabled.
4. To go back to Full Security, open Recovery → Startup Security Utility and choose Full Security.

## Alternatives

- Use a USB4 or Thunderbolt enclosure with an ASMedia ASM2464PD chip. On a Mac with USB4 or Thunderbolt ports, the SSD then shows up like an internal drive and avoids this problem.
- Do large transfers on Windows or Linux, and keep Mac copies small.

---

## Technical details

### What we observed

- Hardware: a UGREEN enclosure (Realtek RTL9210, firmware build tag `F001`) with an ADATA Legend 710 2 TB NVMe SSD (DRAM-less), on an M1 Max Mac running macOS 27.
- During long writes, the kernel log showed:
  `AppleUSBXHCIStreamingEndpoint ... no transfer ring claimed event`, then `status 0xe00002d6 (timeout)`, then `USB device ... will be reset!` and `hardware connection lost`.
- On Windows, the same drive and enclosure wrote 100 GB at a steady ~633 MB/s with no errors, peaking at 58 °C. SMART was clean: 0% used, 0 media errors.

### Likely cause (hypothesis)

The failures involve **UAS streams**, a USB feature that only the UAS mode uses. A DRAM-less SSD can pause for a long time during internal cleanup, and the RTL9210's UAS stream handling appears not to survive those pauses on macOS. BOT does not use streams, so it avoids this failure path.

To be precise about the limits:

- Apple's built-in **BOT and UAS** settings both use **30-second** read/write timeouts and 20 retries. Switching to BOT does **not** give commands more time.
- Speed: in the test below, BOT was faster than UAS, probably because UAS kept stalling. Your results may differ.

### Test results

Same UGREEN RTL9210 enclosure and ADATA Legend 710 2 TB, on an **M4 MacBook Air, macOS 27.0.1**, plugged straight into a USB-C port (10 Gb/s). Each test writes 50 GiB of random data with `dd`, hashing it on the way in, then reads the file back and compares SHA-256.

| Mode | Volume | Result |
|---|---|---|
| UAS (no fix) | exFAT | ❌ Enclosure dropped off USB at ~45 GiB (`Device not configured`), ~254 MB/s |
| UAS (no fix) | APFS, just erased | ❌ Stalled after 10 MB, then `Input/output error` and dropped |
| BOT (this fix) | APFS | ✅ 50 GiB in 113 s (~475 MB/s), read back in 70 s, SHA-256 matched |
| BOT (this fix) | APFS | ✅ 50 GiB in 117 s (~460 MB/s), read back in 70 s, SHA-256 matched |
| BOT (this fix) | APFS | ❌ Real use: Docker Desktop copied its disk image there (30 min `cp -Rp`), then started its VM from it. Within a minute the drive dropped: `AppleUSBIORequest` errors, `usb reset`, and repeated re-enumeration. The SSD then stayed undetected until it was replugged about an hour later |

**So BOT reduces the drops but doesn't stop them.** It survived two long sequential writes that UAS failed, but not a VM's mixed I/O right after a long copy. Don't keep anything on these drives that isn't backed up elsewhere, and don't run Docker or VMs from them.

Loading notes:

- Reduced Security alone: `kmutil load` refused with `Authenticating extension failed: Bad code signature` (exit code 29), although `codesign --verify` reports the bundle as valid.
- After `csrutil enable --without kext`: loaded, and the enclosure's interface switched from protocol 98 (UAS) to 80 (BOT).

After the UAS failures the SSD once stopped being detected anywhere, even on Windows. Leaving it powered and idle in a PC's M.2 slot (at the BIOS screen) brought it back.

Not yet covered: kernel logs from the BOT runs, longer soak tests, other drives, and Intel Macs. If you test it, please open an issue with your results.

### Apple's quirk table

macOS ships a list of per-device fixes in `com.apple.driver.USBStorageDeviceSpecifics`: 173 entries on macOS 27. Twenty of them set `USB Mass Storage Characteristics → Force BOT Protocol = true`. **None cover Realtek (`0x0bda`).**

This fix adds one entry for `0BDA:9210`, in the same shape as Apple's own:

- `IOClass` = `IOUSBMassStorageInterfaceNub`
- `IOProviderClass` = `IOUSBHostInterface`
- `idVendor` = `3034` (0x0bda), `idProduct` = `37392` (0x9210)
- `bConfigurationValue` = `1`, `bInterfaceNumber` = `0`

The entries were read from the running system's kernel cache with [`ipsw`](https://github.com/blacktop/ipsw):

```bash
ipsw kernel dec /System/Volumes/Preboot/*/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache -o .
ipsw kernel extract kernelcache.decompressed com.apple.iokit.IOUSBMassStorageDriver --output .
```

### Side effects

- **Every** enclosure that reports `0BDA:9210` switches to BOT on this Mac, not just one.
- BOT has no command queueing, so on a drive that works fine in UAS, expect lower peak speed.

### Linux

Linux turns UAS off for at least one RTL9210-based product (HIKSEMI MD202) in its USB storage quirks. For other RTL9210 devices you can do the same manually with the kernel parameter `usb-storage.quirks=0bda:9210:u`.

### Files

| File | What it does |
|---|---|
| `RTL9210ForceBOT.kext` | The fix: one settings file (`Info.plist`), ad-hoc signed |
| `install.sh` | Copies it into `/Library/Extensions` and asks macOS to load it |
| `check.sh` | Shows whether the fix is installed and whether your enclosure uses it |
| `uninstall.sh` | Removes it |

## License

MIT
