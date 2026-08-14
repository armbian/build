# Allwinner H618 quad core 1GB/2GB/4GB LPDDR4 RAM SoC WiFi/BT
# Covers all LPDDR4 revisions (1G/2G/4G, size auto-detected); early DDR3
# revision boards are covered by walnutpi-1b-ddr3.
BOARD_NAME="Walnut Pi 1B"
BOARD_VENDOR="walnut"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="TallGuy74"
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
