# Pre-installation

## Unlock your bootloader

Unlock the bootloader of your Oneplus 8t

## Partition the UFS

**This procedure will wipe all your Android data!!!**

We are going to resize `userdata` partition of android and create two partitions for our armbian installation.

You need to boot into a recovery, I recommend [Orange Fox Recovery Project](https://github.com/Wishmasterflo/device_oneplus_opkona). You will also need [parted](hthttps://www.hovatek.com/redirectcode.php?link=aHR0cHM6Ly9tZWdhLm56LyMhN1A0R1VZQUkhRVVxTnhpY0FyOEpPT3c4TTk3VTRmdU1Xc1hmcm9sT3M4WU5rSGpfNXZWVQ==) for aarch64.

Then push the tools to your device and enter ADB shell:

```bash
adb push parted /cache/
adb shell "chmod 755 /cache/parted"
adb shell
```

After entering ADB shell:

```bash
/cache/parted /dev/block/sda
```

Print the current partition table:

```bash
(parted) print
```

Then you will see your current partition table with userdata being the last partition.

Below is an example of output:

```bash
.........
Number  Start    End      Size     File system   Name       Flags
.........
34      2048MB   122GB    120GB    ext4          userdata
```

Now let’s continue partitioning:

Here the size of `userdata` can be decided by yourself. In this guide we take 30G as the example.

```bash
(parted) resizepart 34
# 34 is the partition number for userdata
End? [122GB]? 32GB
```

32GB is the End value for the new userdata partition.

Since the starting point for userdata is 2048MB = 2GB, the new size would be 32G - 2G = 30G.

Then create the linux and esp partitions:

```bash
# esp partition for booting
(parted) mkpart esp fat32 32GB 32.5GB
# set the esp partition as `EFI system partition type`
# replace 35 with the count of your esp partition if different
(parted) set 35 esp on
# partition for installing Linux
(parted) mkpart linux ext4 32.5GB 100%
# print your partition table and confirm everything looks right
(parted) print
# Troubleshooting, may not be required but name the linux partition
# replace 36 with the partition number of your linux partition if different
(parted) name 36 linux
# print your partition table and confirm everything looks right, should see a new esp partition and one named linux
(parted) print
(parted) quit
```

Now `userdata` resizing is done. After reboot to android you will get into a emergency mode, you will have to wipe the data to boot into android with resized `userdata` partition.

## Installation

### Build the images

Follow directions from the [README](../README.md) to build your images. This repo does not offer pre-built images.

### Download and flash disabled vbmeta.img

This device requires a disabled VBMeta image to be flashed prior to booting or flashing anything custom.

Download a vbmeta.img from [LineageOS for oneplus-kebab](https://mirror.math.princeton.edu/pub/lineageos/full/kebab/20260213/vbmeta.img)
and flash it to vbmeta_b

```bash
fastboot flash vbmeta_b vbmeta.img
```

### Flash images

Boot your phone into Fastboot mode.

```bash
# From the root of this repo
# First erase `dtbo_b` (required so slot B does not use Android's device tree overlay)
fastboot erase dtbo_b
# Then flash the Root partition (writes to the partition named "linux", e.g. sda30)
fastboot flash linux output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.rootfs.img
# Sometimes the phone will hang after the rootfs flash, and not accept anymore flashes
# rebooting it back into the bootloader seems to clear it up
fastboot reboot bootloader
# Flash the kernel to boot_b
fastboot flash boot_b output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.boot_sm8250-oneplus-kebab.img
# Set slot b active
fastboot set_active b
# Verify before rebooting (optional)
fastboot getvar current-slot
# Then power off the phone using the bootloader menu on the phone
# Phone should boot into armbian on next power on
```

## Troubleshooting: active slot reverts to A after reboot

If you set the active slot to `b`, reboot (or power off and boot), but the phone boots Android (slot A) and `fastboot getvar current-slot` shows `a` again, the bootloader is **rolling back** because **slot B failed to boot**. On A/B devices, a failed boot from the selected slot is marked unsuccessful and the bootloader switches back to the other slot. So the fix is to make slot B boot successfully.

**Check the following:**

1. **Erase `dtbo_b` before any slot B boot**  
   If `dtbo_b` is not erased, the bootloader can use Android’s device tree overlay for slot B, which can cause the kernel to fail or not find the right root. From fastboot, run:
   ```bash
   fastboot erase dtbo_b
   ```
   Then re-flash `boot_b` and `set_active b` if you had already flashed them.

2. **Ensure every flash completed**  
   If the phone hung after `fastboot flash linux ...`, later commands may not have run. After `fastboot reboot bootloader`, run the full sequence again from `fastboot erase dtbo_b` through `fastboot flash boot_b` and `fastboot set_active b`. Confirm each command prints `OKAY` (or the equivalent success line).

3. **Confirm `boot_b` is the Armbian boot image**  
   If you only re-ran part of the sequence, `boot_b` might still be Android’s boot image. Re-flash the Armbian `.boot_sm8250-oneplus-kebab.img` to `boot_b` and then `fastboot set_active b` and `fastboot reboot`.

4. **Partition layout**  
   Your `linux` partition (e.g. partition 30: 22.5GB–253GB, ext4) and the small `esp` partition (e.g. 29: 22.0GB–22.5GB, boot, esp) must already exist from the partitioning step. The same rootfs image that worked on another phone is correct; root is found by UUID, so a different partition number for `linux` is fine as long as the partition exists and the rootfs was flashed to it.

After fixing the above, run `fastboot set_active b`, then `fastboot reboot`. The next boot should be from slot B (Armbian). If it still reverts to A, slot B is still failing early (e.g. kernel or initrd); re-check that `dtbo_b` was erased and that the Armbian boot image was written to `boot_b` with no errors.

### Slot B still fails: black screen briefly, then Android

If you see a short black screen and then Android (slot A) every time, the bootloader is trying slot B, the boot fails very early (e.g. kernel panic or root not found), and it rolls back to A. Try these in order:

**1. One-time boot (no flash)**  
Boot the Armbian boot image once without changing what’s on the partitions. From fastboot, with the same `.boot_sm8250-oneplus-kebab.img` you use for `boot_b`:

```bash
fastboot boot output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.boot_sm8250-oneplus-kebab.img
```

- If Armbian **boots** (USB gadget, `ssh root@172.16.42.1` works): the image and rootfs are fine; the problem is likely how **flashed** `boot_b` is used on this device (e.g. slot B path or dtbo). You can keep using `fastboot boot …` to start Armbian until you try the slot A test below.
- If it **does not** boot (same black screen then Android or reboot): the failure is not slot-specific (e.g. root not found on this device, or kernel/initrd issue).

**If you get "Failed to load/authenticate boot image: Load Error"** when running `fastboot boot …`: some bootloaders reject the image when loaded from the host (signature or format check) even though the same image may work when flashed to a partition. You cannot use the one-time boot test on that device. Skip to **step 2 (Try slot A with Armbian)** below.

**2. Try slot A with Armbian**  
To see if slot B is the only problem, put Armbian on slot A and boot from A. This overwrites Android’s boot on slot A (you will not be able to boot Android from slot A until you reflash it).

```bash
fastboot erase dtbo_a
fastboot flash boot_a output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.boot_sm8250-oneplus-kebab.img
fastboot set_active a
fastboot reboot
```

- If Armbian **boots** from slot A: your rootfs and kernel are good; something about **slot B** on this device (dtbo, boot path, or rollback logic) is causing the failure. You can use slot A for Armbian; set `abl_boot_partition_label=boot_a` in `/boot/armbianEnv.txt` when you’re in Armbian (see “Check your A/B slot” below).
- If it still **fails** (black screen then rollback to B, or no boot): the issue is likely not slot-specific (e.g. this unit’s firmware or hardware, or root UUID/partition on this phone).


## Post-installation

### First login

After booting into armbian, you have to connect typec port to the usb port of a computer and ssh into the system from usb gadget network:

```bash
ssh root@172.16.42.1
```

Default user and password is `root/1234`, you will set new user and password at first login.

### Check your A/B slot

We have flashed armbian's kernel to boot_b, and set the default slot to b to boot armbian by default.

But the slot may change when android os has done a system update. If you have armbian kernel flashed to boot_a, you also have to update `/boot/armbianEnv.txt` with:

```bash
abl_boot_partition_label=boot_a
```

And check output of `cat /proc/cmdline`, if something like `slot_suffix=_b` is wrong, you have to run this command to set correct slot in kernel args.

```bash
sudo dpkg-reconfigure linux-image-current-sm8250
```

If everything is correct, you should see output from `sudo qbootctl` like this:

```bash
sudo qbootctl
Current slot: _b
SLOT _a:
        Active      : 0
        Successful  : 1
        Bootable    : 1
SLOT _b:
        Active      : 1
        Successful  : 1
        Bootable    : 1
```

slot b is where armbian's kernel is flashed, and `Active`, `Successful` and `Bootable` are all 1.

### Toggle USB role (Type-C port as host)

The Type-C port is in **device** mode by default (for USB gadget/RNDIS networking). To use it as a **host** port (keyboard, storage, etc.) you need a kernel built with USB OTG role switch enabled.

**Why the manual toggle often fails:** On older images the device tree fixed the port as `dr_mode = "peripheral"`, so writing `host` to `/sys/kernel/debug/usb/a600000.usb/mode` has no effect and the mode stays `device`. USB devices plugged into the Type-C port then do not appear in `lsusb` or `dmesg`.

**Fix:** Use an image built with the **USB OTG role switch** device tree patch (e.g. `0011-arm64-dts-qcom-sm8250-oneplus-kebab-Enable-USB-OTG-role-switch.patch`). That patch sets `dr_mode = "otg"` and adds the Type-C connector so the port can switch roles.

**After rebuilding with the OTG patch:**

1. Stop the gadget so the port is free to switch:

   ```bash
   sudo systemctl stop usbgadget-rndis.service
   ```

2. The role may switch automatically when you plug in a USB device (host/peripheral is chosen by the Type-C/PD subsystem). If not, try forcing host via the role switch interface:

   ```bash
   # List role switch devices; the Type-C port’s role is under one of these
   ls /sys/class/usb_role/
   # Example: force host (path can vary)
   echo host | sudo tee /sys/class/usb_role/*/role
   ```

3. Plug in your USB device and check:

   ```bash
   lsusb -t
   dmesg | tail -20
   ```

**If you cannot rebuild:** On an image without the OTG patch, the Type-C port will not operate as a host; use a different USB host port if your device has one (e.g. `usb_2` on Kebab).
