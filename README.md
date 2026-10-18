# rtl9210-macos-force-bot

A codeless macOS kernel extension that makes macOS drive **Realtek RTL9210 (USB ID `0BDA:9210`) NVMe enclosures in Bulk-Only Transport (BOT) mode instead of UAS**, using the same `Force BOT Protocol` quirk Apple already applies to other problem enclosures.

It contains no code: one `Info.plist` with one IOKit personality.

## The problem

With some RTL9210 enclosures (seen here with a UGREEN enclosure and a DRAM-less ADATA Legend 710 SSD), macOS drops the drive during long writes:

- Kernel log: `AppleUSBXHCIStreamingEndpoint ... no transfer ring claimed event`, then `status 0xe00002d6 (timeout)`, then `USB device ... will be reset!` and `hardware connection lost`.
- The volume unmounts and in-flight writes fail.
- The same drive and enclosure on Windows wrote 100 GB at a steady ~633 MB/s with no errors, peaking at 58 °C. SMART was clean (0% used, 0 media errors).

## Why it happens

Taken from the macOS 27 kernel cache:

1. Apple's UAS driver (`IOUSBMassStorageUASDriver`) gives each command **30 s** (`Read/Write Time Out Duration = 30000`, `Retry Count = 20`).
2. A DRAM-less SSD behind a USB bridge can stall writes for 20–43 s while it does internal cleanup. Past 30 s, macOS times the command out and resets the device.
3. Apple ships a quirk table, `com.apple.driver.USBStorageDeviceSpecifics` (173 personalities on macOS 27). Twenty of them set `USB Mass Storage Characteristics → Force BOT Protocol = true`. **The table has no Realtek (`0x0bda`) entries**, so RTL9210 enclosures always get UAS.

This kext adds that missing entry for `0BDA:9210`, in the same shape as Apple's own entries.

## Trade-off

BOT is a simpler protocol: no command queueing and no UAS streams. Expect lower peak throughput and IOPS than UAS. In return you avoid the UAS stream timeouts. The personality applies to **every** device that reports `0BDA:9210`, so other RTL9210 enclosures on the same Mac also switch to BOT.

## Status

**Experimental. Not yet confirmed loading on Apple Silicon.** This kext is unsigned. Read the security section before installing.

## Security: what installing requires

Third-party kernel extensions are blocked by default on Apple Silicon. To load this one you will most likely need to:

1. Shut down, then hold the power button to enter **Recovery**.
2. Open **Utilities → Startup Security Utility**, choose your disk, select **Reduced Security**, and enable **"Allow user management of kernel extensions from identified developers."**
3. Because this kext is **not signed** with a kext-enabled Developer ID, macOS may still refuse it. In that case, the remaining option is disabling System Integrity Protection: in Recovery, open Terminal and run `csrutil disable`.

These settings weaken protections for the whole Mac, not just this kext. Only do this if you accept that trade-off. You can return to Full Security afterwards in the same utility, but this kext will then stop loading.

## Install

```bash
git clone https://github.com/sopenlaz0/rtl9210-macos-force-bot.git
cd rtl9210-macos-force-bot
./install.sh
```

Approve it in **System Settings → Privacy & Security** if asked, reboot, replug the enclosure, then:

```bash
./verify.sh
```

Expected: `BOT (IOUSBMassStorageDriver): fix active`. Without the fix you will see `UAS (IOUSBMassStorageUASDriver)`.

## Uninstall

```bash
./uninstall.sh
```

Then reboot.

## How the personality was derived

The Apple entries were read from the running system's kernel cache with [`ipsw`](https://github.com/blacktop/ipsw):

```bash
ipsw kernel dec /System/Volumes/Preboot/*/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache -o .
ipsw kernel extract kernelcache.decompressed com.apple.iokit.IOUSBMassStorageDriver --output .
```

The quirk entries live in the kernel cache's prelinked `IOKitPersonalities`, each published by `com.apple.driver.USBStorageDeviceSpecifics`. This kext's personality mirrors the existing `Force BOT Protocol` entries:

- `IOClass` = `IOUSBMassStorageInterfaceNub`
- `IOProviderClass` = `IOUSBHostInterface`
- `idVendor` = `3034` (0x0bda), `idProduct` = `37392` (0x9210)
- `bConfigurationValue` = `1`, `bInterfaceNumber` = `0`

## Alternatives that avoid kernel extensions

- Use a **USB4/Thunderbolt enclosure with an ASMedia ASM2464PD bridge**. On a USB4 Mac the SSD appears as native NVMe and skips the USB mass-storage path entirely.
- Use the enclosure on Windows or Linux for large transfers. Linux already disables UAS for some RTL9210 devices in its `usb-storage` quirks.

## License

MIT
