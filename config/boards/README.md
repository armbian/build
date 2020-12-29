|variable| meaning |
|:--|:--|
| # | Name of the board with specs displayed in the build menu |
| BOARD_NAME | welcome text and hostname |
| BOARDFAMILY | [sun8i, sun7i, rockchip64](../sources) |
| BOOTCONFIG | name of u-boot config |
| BOOTCONFIG_LEGACY | name of u-boot config for legacy branch |
| BOOTCONFIG_CURRENT | name of u-boot config for current branch |
| BOOTCONFIG_DEV | name of u-boot config for dev branch |
| BOOTSIZE | size of a separate boot partition in Mib |
| BOOT_LOGO | yes/desktop enable armbian boot logo during booting |
| IMAGE_PARTITION_TABLE | "msdos" (default) or "gpt" (boot loader must supports it) |
| BOOTFS_TYPE | boot partition type: ext4, fat |
| DEFAULT_OVERLAYS | usbhost1 usbhost2 ... |
| DEFAULT_CONSOLE | serial = change default boot output |
| MODULES | space delimited modules for all branches |
| MODULES_LEGACY | space delimited modules for legacy branch |
| MODULES_CURRENT | space delimited modules for current branch |
| MODULES_DEV | space delimited modules for dev branch |
| MODULES_BLACKLIST | space delimited modules blacklist for all branches |
| MODULES_BLACKLIST_LEGACY | space delimited modules blacklist for legacy branch |
| MODULES_BLACKLIST_CURRENT | space delimited modules blacklist for current branch |
| MODULES_BLACKLIST_DEV | space delimited modules blacklist for dev branch |
| SERIALCON | ttyS0,ttyS1, ... |
| BUILD_DESKTOP | yes/no |
| KERNEL_TARGET | legacy,current,dev |
| FULL_DESKTOP | yes/no = install Office, Thunderbird, ... |
| DESKTOP_AUTOLOGIN | yes/no |
| PACKAGE_LIST_BOARD | space delimited packages to be installed on this boards |
| PACKAGE_LIST_BOARD_REMOVE | space delimited packages to be removed |
| PACKAGE_LIST_DESKTOP_BOARD | space delimited packages to be installed on this boards desktop build |
| PACKAGE_LIST_DESKTOP_BOARD_REMOVE | space delimited packages to be removed |
| BOOT_FDT_FILE | Forcing loading specific device tree configuration - if its different than the one defined by u-boot |
| CPUMIN | Minimum CPU frequency to scale (Hz) |
| CPUMAX | Maximum CPU frequency to scale (Hz) |
| FORCE_BOOTSCRIPT_UPDATE | install bootscripts if they are not present |
| OVERLAY_PREFIX | prefix for DT and overlay file paths which will be set while creating image |


Statuses displayed at the login prompt:


|file type|description|
|:--|:--|
|.csc or. tvb	|community creations|
|.wip		|work in progress|
|.eos		|end of life|

