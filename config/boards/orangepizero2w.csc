# Allwinner H618 quad core 1GB/1.5GB/2GB/4GB RAM
BOARD_NAME="Orange Pi Zero2W"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="chraac"
BOOTCONFIG="orangepi_zero2w_defconfig"
BOOTBRANCH="tag:v2024.04"
BOOTPATCHDIR="v2024.04"
BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

enable_extension "uwe5622-allwinner"
