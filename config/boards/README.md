|variable| meaning |
|:--|:--|
| # | Name of the board with specs displayed in the build menu |
| BOARD_NAME | welcome text and hostname |
| BOARDFAMILY | Applies a board-specific configuration such as temperature sensors, LEDs, etc.. See [sources](../sources) for options |
| BOOTCONFIG | name of u-boot config |
| BOOTCONFIG_LEGACY | name of u-boot config for legacy branch |
| BOOTCONFIG_CURRENT | name of u-boot config for current branch |
| BOOTCONFIG_EDGE | name of u-boot config for edge branch |
| BOOTSIZE | size of a separate boot partition in Mib |
| BOOT_LOGO | yes/desktop enable armbian boot logo during booting |
| IMAGE_PARTITION_TABLE | "msdos" (default) or "gpt" (boot loader must supports it) |
| BOOTFS_TYPE | boot partition type: ext4, fat |
| DEFAULT_OVERLAYS | usbhost1 usbhost2 ... |
| DEFAULT_CONSOLE | serial = change default boot output |
| MODULES | space delimited modules for all branches |
| MODULES_LEGACY | space delimited modules for legacy branch |
| MODULES_CURRENT | space delimited modules for current branch |
| MODULES_EDGE | space delimited modules for edge branch |
| MODULES_BLACKLIST | space delimited modules blacklist for all branches |
| MODULES_BLACKLIST_LEGACY | space delimited modules blacklist for legacy branch |
| MODULES_BLACKLIST_CURRENT | space delimited modules blacklist for current branch |
| MODULES_BLACKLIST_EDGE | space delimited modules blacklist for edge branch |
| SERIALCON | ttyS0,ttyS1, ... |
| HAS_VIDEO_OUTPUT | yes/no |
| KERNEL_TARGET | legacy,current,edge |
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
|.csc or .tvb	|community creations or no active maintainer|
|.wip		|work in progress|
|.eos		|end of life|

