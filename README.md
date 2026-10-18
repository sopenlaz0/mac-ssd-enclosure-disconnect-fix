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

- You need Reduced Security, and possibly Permissive Security (SIP turned off), which is a bigger downgrade.
- The fix is ad-hoc signed. It has a signature, but not one from an Apple-approved developer, which is why the extra steps are needed.
- The lower security settings apply to your whole Mac, not just this fix.
- This is experimental. Loading hasn't been confirmed yet on Apple Silicon (macOS 27).

If you'd rather not lower security, see [Alternatives](#alternatives) below.

## Install

### 1. Allow extensions (Apple Silicon Macs)

1. Shut down, then press and hold the power button until you see Loading startup options.
2. Click Options, then go to Utilities → Startup Security Utility.
3. Select your disk, choose Reduced Security, and tick "Allow user management of kernel extensions from identified developers".
4. Restart.

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

If the installer says macOS refused it, your Mac is still blocking unapproved extensions. The remaining option is turning off System Integrity Protection: boot into Recovery as in Step 1, open **Utilities → Terminal**, run `csrutil disable`, and restart. That puts your Mac in Permissive Security, so only do it if you accept the risk. "Undo everything" below explains how to turn it back on.

## Undo everything

1. Remove the fix:
   ```bash
   ./uninstall.sh
   ```
2. Restart.
3. If you turned off SIP, boot into Recovery, open Terminal, run `csrutil enable`, and restart. `csrutil status` should then say enabled.
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
- **Not yet verified:** a before/after test of long writes (with checksums and kernel logs) using this fix. If you test it, please open an issue with your results.

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
- BOT has no command queueing, so expect lower peak speed than UAS.

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
