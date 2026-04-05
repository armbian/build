## Understanding the generic bootscript
The generic bootscript [template] attempts to [do all the things](http://www.quickmeme.com/img/55/55157deb762c88e8979fe0c515e68802cceaa45f0f35707af310059bae831ecd.jpg) found in the bootscripts of `sunxi`, `mvebu` and `rockchip64`.

There are a number of functional blocks in the generic bootscript:

1. Define U-Boot environment variables.
1. Load a U-Boot environment (`armbianEnv.txt` in our case).
1. Prepare kernel commandline parameters based on loaded environment settings.
1. Process device tree (DT).
1. Process the kernel image.
1. Process the initial ramdisk.
1. Load the initial ramdisk.
1. Boot the kernel with locations of the initial ramdisk and device tree.

The DT is now loaded first, followed by the kernel image with the initial ramdisk last.

When U-Boot has support for the command `setexpr` built in, the bootscript will calculate the load addresses of the kernel image and initial ramdisk. This ensures that no overlap issue will occur, which results in the kernel not starting or U-Boot not even trying to boot the kernel.

In case `setexpr` is not available in U-Boot, the predefined load address `fdt_addr_r`, `kernel_addr_r` and `ramdisk_addr_r` will be used. These are either hardcoded in U-Boot, or are set in the default U-Boot environment for the board.

### Templating
Differences and deviations in the actions or settings performed by these bootscript have been extracted and are now rendered as a template. Each board that uses the generic bootscript will have to provide input to fully render the template.
For example, they all have a serial console so all bootscripts contain actions to prepare the kernel to use the serial console. The actual console device is however not always the same.

The following variables need to be defined on the board configuration to render the generic bootscript template:

|Variable|Usage|
|-|-|
|`BOOTSCRIPT_TEMPLATE__ALIGN_TO`|For the calculation of load addresses by the generic bootscript, addresses need to be aligned for most CPU types. For example, for ARM64 CPUs, the start of the `Image` file to be aligned to a 2MiB (`0x00200000`) boundary. For most architectures, aligning these addresses to a 4KiB (`0x1000`) address boundary is good practice.|
|`BOOTSCRIPT_TEMPLATE__BOARD_FAMILY`|The CPU family, currently not used by the generic bootscript.|
|`BOOTSCRIPT_TEMPLATE__ROOTFS_TYPE`|The filesystem type of the root filesystem, e.g. `ext4` or `f2fs`.|
|`BOOTSCRIPT_TEMPLATE__BOARD_VENDOR`|The vendor of the board, e.g. `allwinner`, `rockchips64`.|
|`BOOTSCRIPT_TEMPLATE__LOAD_ADDR`|Some architectures/CPUs have a different load address that is used to load scripts or FDT files. Use the `loadaddr` that fits with your architecture, e.g. `0x00300000` for the Helios4 (`mvebu`) or `0x09000000` for the NanoPi R2s.|

Two exceptions for templating are listed below:
|Variable|Usage|
|-|-|
|`BOOTSCRIPT_TEMPLATE__DISPLAY_CONSOLE`|Leave this empty; it will be automatically determined (and overwritten) by `distro-agnostic.sh`. This will contain the combination of the variables `$DISPLAYCON` and `$SRC_CMDLINE`.|
|`BOOTSCRIPT_TEMPLATE__SERIAL_CONSOLE`|Leave this empty; it will be automatically determined (and overwritten) by `distro-agnostic.sh`. This will contain the combination of the variables `$SERIALCON` and `$SRC_CMDLINE`.|

The generic bootscript template will be rendered during building. If any of the bootscript template variables are not defined, the build process will error out.

Example of a board configuration file for the Orange Pi Zero:
```
# Allwinner H2+ quad core 256/512MB RAM SoC WiFi SPI
BOARD_NAME="Orange Pi Zero"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_zero_defconfig"
MODULES_CURRENT="g_serial"
MODULES_BLACKLIST="sunxi_cedrus"
DEFAULT_OVERLAYS="usbhost2 usbhost3 tve"
DEFAULT_CONSOLE="both"
HAS_VIDEO_OUTPUT="yes"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="orangepi_zero_defconfig"

DISPLAYCON=''
SERIALCON="ttyS0:115200,ttyGS0"

BOOTSCRIPT='boot-generic.cmd.template:boot.cmd'
BOOTSCRIPT_TEMPLATE__ALIGN_TO='0x00001000'
BOOTSCRIPT_TEMPLATE__BOARD_FAMILY="${BOARDFAMILY:-sun8i}"
BOOTSCRIPT_TEMPLATE__BOARD_VENDOR='allwinner'
BOOTSCRIPT_TEMPLATE__LOAD_ADDR='0x45000000'
BOOTSCRIPT_TEMPLATE__ROOTFS_TYPE="${ROOTFS_TYPE:-ext4}"
BOOTSCRIPT_TEMPLATE__DISPLAY_CONSOLE='' # leave empty here, use DISPLAYCON instead
BOOTSCRIPT_TEMPLATE__SERIAL_CONSOLE='' # leave empty here, use SERIALCON instead

function orange_pi_zero_enable_xradio_workarounds() {
        /usr/bin/systemctl enable xradio_unload.service
...
```

### Rendering of the template
The bootscript template is rendered in `lib/functions/rootfs/distro-agnostic.sh` by the function `render_bootscript_template`.

As the display and serial console devices can be defined throughout the build process, the following functions will gather them all and process them accordingly:
- `bootscript_export_display_console` for `DISPLAYCON`
- `bootscript_export_serial_console` for `SERIALCON`

Multiple console devices can be defined by separating them with a `,` (comma). Standard Linux kernel arguments are allowed:
```
SERIALCON="ttyS0:115200,ttyGS0"
```

See [Linux kernel serial-console documentation](https://www.kernel.org/doc/html/latest/admin-guide/serial-console.html) for more information on the arguments and syntax.

### Calculating the size of the device tree
For the device tree (DT) it depends on the U-Boot version if the bootscript can determine it's size. The `fdt` shell command has a subcommand `header get` that can return the size of the current DT in-memory. In case the size of the in-memory DT cannot be determined, the filesize of the FDT will be used - aligned to `${align_to}`.

### Calculating the size of the linux kernel image
In case the image file is a `zImage`, the image size will be based on the filesize of the `zImage`. (Self-)extraction of the image will be done into a different area of memory.
In case the image file is an `Image`, the bootscript will use the filesize as stated inside the `Image` file's header.

### Calculating the size of the initial ramdisk
The initial ramdisk size is based on the filesize of the ramdisk itself. The kernel will extract it to somewhere it deems appropriate.

# References

- [U-Boot shell commands](https://docs.u-boot.org/en/latest/usage/index.html#shell-commands).
- [U-Boot environment variables](https://docs.u-boot.org/en/latest/usage/environment.html).
- [FDT](https://www.kernel.org/doc/html/latest/devicetree/usage-model.html).
- Initial ramdisk [initrd](https://docs.kernel.org/admin-guide/initrd.html).
- Kernel image types [[1]](https://www.baeldung.com/linux/kernel-images) [[2]](https://unix.stackexchange.com/a/295142).
- [Helios4 doesn't boot after upgrading to linux-6.6.71 (linux-image-current-mvebu_25.2.0-trunk.343)](https://forum.armbian.com/topic/49440-helios4-doesnt-boot-after-upgrading-to-linux-6671-linux-image-current-mvebu_2520-trunk343/#findComment-217099).
- [[Bug]: mvebu/Helios4: Wrong Ramdisk Image Format, Ramdisk image is corrupt or invalid #8165](https://github.com/armbian/build/issues/8165).
- [[Bug]: U-Boot load address calculation bug and DT overlap oobe #8178](https://github.com/armbian/build/issues/8178).
