# Internal build options

These options are used to declare variables used by the armbian build system to build a board-specific configuration.

If you are unsure about the documentation then invoke `$ grep -r -A5 -B5 "BUILD_OPTION_HERE" /path/to/local/armbian/build/repository` to get context to the option from the source code.

- **BOARD_NAME** ( company product version ): defines the board name used in welcome text, hostname and others relevant usage.The general convention is `COMPANY PRODUCT VERSION` - Often used as part of the scripting logic (namely for hacks) so follow the name declared in the board configuration.
	- Example: `OLIMEX Teres A64`
- **BOARDFAMILY** ( board-family ): defines the family of the board to apply board-specific configuration during build time such as adjustments for the temperature, LED behavior, etc..
	- Refer to [sources table](https://github.com/armbian/build/blob/master/config/sources/README.md)
	- Example: `sun50iw1`
- **BOOTCONFIG** ( u-boot identifier ): declares the name of the u-boot configuration for the build without the '\_defconifig' suffix
	- Refer to the [u-boot source tree](https://github.com/u-boot/u-boot/tree/master/configs) to find configuration for the board
	- Example: `teres-i`
- **BOOTSIZE** ( int ): Declares the size of the boot partitin in Mib
	- Default: `256`
	- Example: `256`
- **BOOT_LOGO** ( string ): defines whether to use a eyecandy during bootloader phase
	- Values:
		- yes: Show the armbian boot logo
		- desktop: Show the armbian boot logo when `BUILD_DESKTOP` is set to `yes`
	- Default: `not set`
- **IMAGE_PARTITION_TABLE** ( string ): defines which disklabel type to use
	- Values:
		- msdos: Use dos/msdos disklabel
		- gpt: Use GPT disklabel
	- Default: msdos
- **BOOTFS_TYPE** ( filesystem ): defines the expected filesystem for the boot file system
	- Values:
		- none: Uses /boot on the root filesystem
		- ext4: Use the [Fourth Extended Filesystem](https://en.wikipedia.org/wiki/Ext4)
		- ext2: Use the [Second Extended Filesystem](https://en.wikipedia.org/wiki/Ext2)
		- fat: Use the [File Allocation Table 32](https://en.wikipedia.org/wiki/File_Allocation_Table#FAT32)
	- Default: `ext4`
- **DEFAULT_OVERLAYS** ( space-separated list list of dtb overlays ): defines dtb overlays that are enabled by default. There is a basic dtb for each family but they have different level of used SoC features. Board X might have four USB ports but others might not. Therefore other does not need to have those enabled while board X does.
	- Examples:
		- usbhost0
		- usbhost2
		- usbhost3
		- cir
		- analog-codec
		- gpio-regulator-1.3v
		- uart1
- **DEFAULT_CONSOLE** ( string ): declares default console for the boot output
	- Values:
		- serial: Output boot messages to serial console
	- Default: `not set`
- **MODULES** ( space-separated list of kernel modules ): appends modules to the kernel command line for **all** kernel branches
- **MODULES_LEGACY** ( space-separated list of kernel modules ): appends modules to the kernel command line for **legacy** kernel
- **MODULES_CURRENT** ( space-separated list of kernel modules ): appends modules to the kernel command line for **current** kernel
- **MODULES_EDGE** ( space-separated list of kernel modules ): appends modules to the kernel command line for **edge** kernel
- **MODULES_BLACKLIST** ( space-separated list of kernel modules ): appends modules to the kernel's blacklist/deny list for **all** kernel branches
- **MODULES_BLACKLIST_LEGACY** ( space-separated list of kernel modules ): appends modules to the kernel's blacklist/deny list for **legacy** kernel
- **MODULES_BLACKLIST_CURRENT** ( space-separated list of kernel modules ): appends modules to the kernel's blacklist/deny list for **current** kernel
- **MODULES_BLACKLIST_EDGE** ( space-separated list of kernel modules ): appends modules to the kernel's blacklist/deny list for **edge** kernel
- **SERIALCON** ( comma-separated list of terminal interfaces [:bandwidth] ): declares which serial console should be used on the system
	- Example: `ttyS0:15000000,ttyGS1`
- **SKIP_ARMBIAN_REPO** ( boolean ): Whether to include the armbian repository in the built image
    - Values:
        - yes: Include (default)
        - no: Do NO include
- **HAS_VIDEO_OUTPUT** ( boolean ): defines whether the system has video output such as eye candy, bootsplash, etc..
	- Values:
		- yes: Enable video-related configuration
		- no: Disable video-related configuration
- **KERNEL_TARGET** ( comma-separated list of kernel releases or branches ): declares which kernels should be used for the build
	- Values:
		- legacy: Use legacy kernel
		- current: Use current kernel
		- edge: Use edge kernel
		- [branch]: Use specified [branch] kernel
		- [none]: Exits with error
- **FULL_DESKTOP** ( boolean ): defines whether to install desktop stack of applications such as office, thunderbird, etc..
	- Values:
		- yes: install desktop stack
		- no: doesn't install desktop stack
- **DESKTOP_AUTOLOGIN** ( boolean ): Toggle desktop autologin
	- Values:
		- yes: Automatically login to the desktop
		- no: disable desktop autologin
	- Default: `no`
- **PACKAGE_LIST_BOARD** ( space-separated list of packages ): Declares which packages should be installed on the system
- **PACKAGE_LIST_BOARD_REMOVE** ( space-separated list of packages ): Declares packages to be removed from the system
- **BOOT_FDT_FILE** ( device tree configuration ): Force to load specific device tree configuration if different from the one defined by u-boot
	- Values:
		- [family]/[file.dtb]: Replace device tree with the one specified
		- none: Do not use device tree configuration
	- Example: `rockchip/rk3568-rock-3-a.dtb`
- **CPUMIN** ( minimum CPU frequency to scale in Hz ): Set minimal CPU frequency of the system
	- Default: Differs per family `480000` for sunxi8 boards
- **CPUMAX**  ( minimum CPU frequency to scale in Hz ): Set maximal CPU frequency of the system
	- Default: Differs per family `1400000` for sunxi8 boards
- **FORCE_BOOTSCRIPT_UPDATE** ( boolean ): Force bootscript installation if they are not present
	- Values:
		- yes: Enable
		- no: Disable
- **OVERLAY_PREFIX** ( prefix ): Prefix for device tree and overlay file paths which will be set while creating an image
	- Example: `sun8i-h3`

## Deprecated

- **BOOTCONFIG_LEGACY** ( u-boot identifier ): use **BOOTCONFIG** instead
- **BOOTCONFIG_CURRENT** ( u-boot identifier ): use **BOOTCONFIG** instead
- **BOOTCONFIG_EDGE** ( u-boot identifier ): use **BOOTCONFIG** instead
- **PACKAGE_LIST_BOARD_DESKTOP** ( space-separated list of packages ): use **PACKAGE_LIST_BOARD** instead
- **PACKAGE_LIST_BOARD_DESKTOP_REMOVE** ( space-separated list of packages ): use **PACKAGE_LIST_BOARD** instead

## File extensions
Statuses displayed at the login prompt:


|file type|description|
|:--|:--|
|.csc or .tvb	|community creations or no active maintainer|
|.wip		|work in progress|
|.eos		|end of life|
