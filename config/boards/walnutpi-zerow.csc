# Walnut Pi Zero W - Allwinner H618
# Board config file for Armbian build framework
# Based on Orange Pi Zero 2W (same H618 SoC)

BOARD_NAME="Walnut Pi Zero W"
BOARD_VENDOR="Walnut"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="community"
INTRODUCED="2024"
BOOTCONFIG="walnutpi_zerow_defconfig"
BOOTBRANCH="tag:v2024.01"
BOOTPATCHDIR="v2024-sunxi"
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

# WiFi/BT modules (UWE5622 chip - same as Orange Pi Zero 2W)
MODULES_CURRENT="uwe5622_bsp_sdio sprdwl_ng sprdbt_tty"
MODULES_EDGE="uwe5622_bsp_sdio sprdwl_ng sprdbt_tty"
MODULES_BLACKLIST_CURRENT="bcmdhd"

# Enable UWE5622 extension for WiFi/BT support
enable_extension "uwe5622-allwinner"
