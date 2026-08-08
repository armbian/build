# Allwinner H618 quad core 1GB DDR3 RAM SoC WiFi/BT
# Early 1B revision with 2x 512MB DDR3 (vendor schematic v1.0); newer 1GB
# boards use LPDDR4 and are covered by walnutpi-1b. Untested on hardware.
BOARD_NAME="Walnut Pi 1B DDR3"
BOARD_VENDOR="walnut"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="TallGuy74"
INTRODUCED="2026"
BOOTCONFIG="walnutpi_1b_ddr3_defconfig"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="sun50i-h618-walnutpi-1b.dtb"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
SERIALCON="ttyS0"

enable_extension "uwe5622-allwinner"
