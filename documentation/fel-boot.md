# FEL/NFS boot explanation

### What is FEL/NFS boot?

FEL/NFS boot mode is a possibility to test freshly created Armbian distribution without using SD card. It is implemented by loading u-boot, kernel, initrd, boot script and .bin/.dtb file via [USB FEL mode](https://linux-sunxi.org/FEL/USBBoot) and providing root filesystem via NFS share.

NOTE: this mode is designed only for testing. To use root on NFS permanently, use `ROOTFS_TYPE=nfs` option.
NOTE: "hot" switching between kernel branches (default <-> dev/next) is not supported

### Requirements

- Allwinner device that supports FEL mode. Check [wiki](https://linux-sunxi.org/FEL) to find out how to enter FEL mode with your device
- USB connection between build host and board OTG port (VM USB passthrough or USB over IP may work too)
- Network connection between build host and board. For target board **wired** Ethernet connection is required (either via onboard Ethernet or via USB ethernet adapter that has required kernel modules built-in)
- NFS ports on build host should be reachable from board perspective (you may need to open ports in firewall or change network configuration of your VM)
- Selected kernel should have built-in support for DHCP and NFS root filesystem
- `CLEAN_LEVEL="make,debs"` to always update u-boot configuration

#### Additional requirements (recommended)

- DHCP server in local network
- UART console connected to target board

### Build script options

- KERNEL_ONLY=no
- EXTENDED_DEBOOTSTRAP=yes
- ROOTFS_TYPE=fel

Example:
```
./compile.sh KERNEL_ONLY=no BOARD=cubietruck BRANCH=next PROGRESS_DISPLAY=plain USE_MAINLINE_GOOGLE_MIRROR=yes RELEASE=jessie BUILD_DESKTOP=no EXTENDED_DEBOOTSTRAP=yes ROOTFS_TYPE=fel
```

### Shutdown and reboot

Once you start FEL boot, you will see this prompt:

```
[ o.k. ] Press any key to boot again, <q> to finish [ FEL ]
```

Pressing `q` deletes current rootfs and finishes build process, so you need to shut down or reboot your board to avoid possible problems unmounting/deleting temporary rootfs. All changes to root filesystem will persist until you exit FEL mode.

To reboot again into testing system, switch your board into FEL mode and press any key other than `q`.

Because kernel and .bin/.dtb file are loaded from rootfs each time, it's possible to update kernel or its configuration (via `apt-get`, `dtc`, `fex2bin`/`bin2fex`) from within running system.

### Advanced configuration

If you don't have DHCP server in your local network or if you need to alter kernel command line, use `lib/scripts/fel-boot.cmd.template` as a template and save modified script as `userpatches/fel-boot.cmd`. Check [this](https://git.kernel.org/cgit/linux/kernel/git/stable/linux-stable.git/plain/Documentation/filesystems/nfs/nfsroot.txt) for configuring static IP for NFS root

Set `FEL_DTB_FILE` to relative path to .dtb or .bin file if it can't be obtained from u-boot config (mainline kernel) or boot/script.bin (legacy kernel)

You may need to set these additional options (it's a good idea to put them in `userpatches/lib.config`:

Set `FEL_NET_IFNAME` to name of your network interface if you have more than one non-loopback interface with assigned IPv4 address on your build host

Set `FEL_LOCAL_IP` to IP address that can be used to reach NFS server on your build host if it can't be obtained from ifconfig (i.e. port forwarding to VM guest)

Set `FEL_AUTO=yes` to skip prompt before trying FEL load

### Customization

You can even create `userpatches/fel-hooks.sh` and define there 2 functions: `fel_post_prepare` and `fel_pre_load`. All normal build variables like $BOARD, $BRANCH and so on can be used in these functions to define specific actions.

`fel_post_prepare` is executed once after setting up u-boot script and NFS share, you can use it to add extra stuff to boot.scr (like `gpio set` or `setenv machid`) based on device name.

`fel_pre_load` is executed before calling sunxi-fel, you can use it to implement logic to select one of multiple connected boards; to pass additional arguments to `sunxi-fel` you can use `FEL_EXTRA_ARGS` variable.

An example is provided as `scripts/fel-hooks.sh.example`.

