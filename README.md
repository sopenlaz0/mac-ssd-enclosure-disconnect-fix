# Mac SSD Enclosure Disconnect Fix

**Does your external SSD keep disconnecting from your Mac during big copies?**

You might be hitting a known problem between macOS and one very common USB SSD enclosure chip. This repo is a small, undoable fix for it.

## Is this you?

- Your NVMe SSD sits in a USB-C enclosure (UGREEN, ORICO, Sabrent and many no-name brands).
- Copying a lot of data (tens of GB) makes it **freeze, disappear, or show "Disk Not Ejected Properly"**.
- **The same drive works fine on Windows.**

## Check if your enclosure is affected (30 seconds)

1. Plug the enclosure into your Mac.
2. Hold **Option** and click the Apple menu  → **System Information**.
3. Click **USB** in the sidebar, then click your enclosure.
4. Look at the numbers:
   - **Vendor ID: `0x0bda`** (Realtek)
   - **Product ID: `0x9210`**

**If both match, this fix is for you.** If they don't, this fix won't do anything for your enclosure.

Or, from this folder, run `./check.sh`.

## What the fix does

Your Mac can talk to USB drives in two ways:

| Mode | Speed | With this chip |
|---|---|---|
| **UAS** (the default, fast mode) | Faster | Can disconnect under heavy writes |
| **BOT** (the older, simple mode) | Somewhat slower | Avoids the UAS-specific failures |

This fix tells your Mac to use **BOT** for this one chip. Apple already does exactly this for about 20 other problem enclosures; this chip just isn't on Apple's list.

It's a single settings file: **no code runs**, and it's fully removable.

## Before you install: the security trade-off ⚠️

Apple only lets extensions like this load if you **lower your Mac's startup security**. Please read this part.

- You will need **Reduced Security**, and possibly **Permissive Security** (SIP turned off), which is a bigger downgrade.
- This fix is **ad-hoc signed**: it has a signature, but not one from an Apple-approved developer. That is why the extra steps are needed.
- Lower security settings apply to **your whole Mac**, not just this fix.
- **Status: experimental.** Loading has not yet been confirmed on Apple Silicon (macOS 27).

**Don't want to lower security?** See [No-security-change alternatives](#no-security-change-alternatives) below.

## Install

**Step 1: Allow extensions** (Apple Silicon Macs)

1. Shut down. Press and hold the power button until you see **Loading startup options**.
2. Click **Options**, then go to **Utilities → Startup Security Utility**.
3. Pick your disk, choose **Reduced Security**, and tick **"Allow user management of kernel extensions from identified developers"**.
4. Restart.

**Step 2: Install the fix**

```bash
git clone https://github.com/sopenlaz0/mac-ssd-enclosure-disconnect-fix.git
cd mac-ssd-enclosure-disconnect-fix
./install.sh
```

If it asks, approve it in **System Settings → Privacy & Security**, then restart.

**Step 3: Check it worked**

Replug your enclosure, then run:

```bash
./check.sh
```

You want to see: **✅ Yes: … is in the stable (BOT) mode, set by this fix.**

**If install says macOS refused it:** your Mac is still blocking unapproved extensions. The remaining option is turning off System Integrity Protection: boot into Recovery as in Step 1, open **Utilities → Terminal**, run `csrutil disable`, and restart. That puts your Mac in **Permissive Security**. Only do this if you accept the risk, and see "Undo everything" below for how to turn it back on.

## Undo everything

1. Remove the fix:
   ```bash
   ./uninstall.sh
   ```
2. Restart.
3. If you turned off SIP: boot into Recovery, open **Terminal**, run `csrutil enable`, and restart. Check with `csrutil status`; it should say **enabled**.
4. Go back to **Full Security**: Recovery → **Startup Security Utility** → **Full Security**.

## No-security-change alternatives

- **Get a USB4 / Thunderbolt enclosure with an ASMedia ASM2464PD chip.** On Macs with USB4 or Thunderbolt ports, your SSD then shows up as a native internal-style drive and skips this problem entirely.
- **Do big transfers on Windows or Linux**, and use the drive on the Mac for smaller copies.

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
