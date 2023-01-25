# Allwinner A64 quad core 2GB SoC Wi-Fi/BT
# Maintained on opoortunistic and/or 'whenever i feel like it' bases by Jacob "Kreyren" Hrbek
## Matrix contact: #kreyren:qoto.org

###! # OLIMEX Teres-1 on Armbian!
###! This file stores configuration for the armbian build system
###!
###! For armbian documentation see:
###! * https://github.com/armbian/build/blob/master/config/boards/README.md
###! * https://docs.armbian.com/Developer-Guide_Build-Options
###!
###! WARNING: Many of the armbian documentation is outdated/deprecated so use `$ grep -A5 -B5 -r "BOARD_NAME" /path/to/armbian/build/directory` to get the context on what is the option doing
###!
###! # Non-Free
###! The board revisions B and C are using a WiFi/BLE module that depends on proprietary firmware namely 'rtlwifi/rt18723bs' which needs to be included for the said functionality to work
###! 
###! # Known issues
###! * mesa-[>22.3.1-r0] is known to cause 'DRM_IOCTL_MODE_CREATE_DUMB failed: Out of memory' (https://gitlab.alpinelinux.org/alpine/aports/-/issues/14588), this issue is as of 25.01.2023-EU being investigated
###!
###! # References:
###! 1. Instructions by Milan P.Stanič (Alpine kernel developer, nicknamed 'mps') on packaging for Alpine Linux - https://arvanta.net/alpine/alpine-on-olimex/
###! 2. Linux sunxi wikipage on the device - https://linux-sunxi.org/Olimex_Teres-A64 
###! 3. Sunxi mainlining effort - https://linux-sunxi.org/Linux_mainlining_effort
###! 4. Milan O. Stanič's configuration for OlinuXino-A64 - https://gist.github.com/Kreyren/20398aa7213bfc8de74d5dda242c491c
###! 5. Unofficial wiki - https://olimex.miraheze.org/wiki/Products/Teres-1
###! 6. Debian wiki on teres-1 - https://wiki.debian.org/InstallingDebianOn/Olimex/Teres-I

BOARD_NAME="OLIMEX Teres A64"

BOARDFAMILY="sun50iw1"

# The board is fully supported since v2019.07 as 'teres_i_defconfig' target[2]
BOOTCONFIG="teres_i_defconfig"

# NOTE(Krey): Size below 300M seems to cause issues when doing release upgrades (https://github.com/OLIMEX/DIY-LAPTOP/issues/52)
BOOTSIZE="256"

BOOT_LOGO="yes"

# The 'btrfs' needs more testing for objective results
BOOTFS_TYPE="ext4"

# FIXME(Krey): Should be using custom kernel by mps from alpine
# NOTE(Krey): The legacy kernel (<5.17) doesn't have full support so should be avoided[3]
KERNEL_TARGET="current,edge"

# NOTE(Krey): Doesn't make sense to include full desktop considering the demands for network bandwidth and system resources to remove bloat
FULL_DESKTOP="no"

# NOTE(Krey): Using modules declared by mps[4]
MODULES_CURRENT="sd-mod usb-storage ext4 f2fs sunxi-mmc"
MODULES_EDGE="sd-mod usb-storage ext4 f2fs sunxi-mmc"

# NOTE(Krey): The 'gpt' needs more testing for objective results
IMAGE_PARTITION_TABLE="msdos"

# NOTE(Krey): No idea what this is
# DEFAULT_OVERLAYS

# NOTE(Krey): The notebook comes with a debug cable for a reason!
DEFAULT_CONSOLE="serial"

SERIALCON="ttyS0:115200"

HAS_VIDEO_OUTPUT="yes"

# NOTE(Krey): Requires network manager to avoid removing DE causing inability to connect to the internet
# NOTE(Krey): firmware-realtek is needed for the wifi as it's using non-free[6]
PACKAGE_LIST_BOARD="network-manager firmware-realtek"
