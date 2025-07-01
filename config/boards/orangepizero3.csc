# Allwinner H618 quad core 1/2/4GB RAM SoC WiFi SPI USB-C
BOARD_NAME="Orange Pi Zero3"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="alexl83 chraac"
BOOTCONFIG="orangepi_zero3_defconfig"
BOOTBRANCH="tag:v2025.04"
BOOTPATCHDIR="v2025-sunxi"
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

enable_extension "uwe5622-allwinner"
