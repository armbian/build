# Allwinner H616 quad core 512MB/1GB RAM SoC WiFi SPI USB-C
BOARD_NAME="Orange Pi Zero2"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="AGM1968 krachlatte"
BOOTCONFIG="orangepi_zero2_defconfig"
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

enable_extension "uwe5622-allwinner"
