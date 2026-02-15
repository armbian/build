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

### Flash images

Boot your phone into Fastboot mode.

```bash
# From the root of this repo
# First erase `dtbo_b`
fastboot erase dtbo_b
# Then flash the Root partition
fastboot flash linux output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.rootfs.img
# Sometimes the phone will hang after the rootfs flash, and not accept anymore flashes
# rebooting it back into the bootloader seems to clear it up
fastboot reboot bootloader
# Flash the kernel to boot_b
fastboot flash boot_b output/images/Armbian-unofficial_26.02.0-trunk_Oneplus-kebab_noble_current_6.18.10.boot_sm8250-oneplus-kebab.img
# set slot b active to boot
fastboot set_active b
# Power off the phone, then boot back up using the power button
fastboot poweroff
```

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

### Toggle USB role

USB role of typec port is device mode by default for usb gadget network. If you want to connect devices like keyboard to typec port, you have to toggle the role manually to host mode, run the following commands under root:

```bash
systemctl stop usbgadget-rndis.service
echo host > /sys/kernel/debug/usb/a600000.usb/mode
```

Then you can see two new buses:

```bash
lsusb -t
/:  Bus 04.Port 1: Dev 1, Class=root_hub, Driver=xhci-hcd/1p, 10000M
/:  Bus 03.Port 1: Dev 1, Class=root_hub, Driver=xhci-hcd/1p, 480M
/:  Bus 02.Port 1: Dev 1, Class=root_hub, Driver=xhci-hcd/1p, 10000M
/:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=xhci-hcd/1p, 480M
```
