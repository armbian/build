# Allwinner H618 quad core 1GB/2GB/4GB RAM
BOARD_NAME="Longan Pi 3H"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER=""
BOOTCONFIG="longanpi_3h_defconfig"
BOOTBRANCH="tag:v2024.10"
BOOTPATCHDIR="v2024.10"
BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
enable_extension "radxa-aic8800" # compatible with radxa-aic8800
AIC8800_TYPE="usb"
