# Allwinner H618 quad core 2GB/4GB RAM SoC WiFi/BT
# Covers the LPDDR4 (2G/4G) variant; the 1GB variant uses DDR3 and needs its
# own u-boot DRAM profile (vendor u-boot used a DDR3/LPDDR4 auto option that
# mainline does not have).
BOARD_NAME="Walnut Pi 1B"
BOARD_VENDOR="walnutpi"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER=""
INTRODUCED="2026"
BOOTCONFIG="walnutpi_1b_defconfig"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="sun50i-h618-walnutpi-1b.dtb"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
SERIALCON="ttyS0"

enable_extension "uwe5622-allwinner"
