# Allwinner H6 quad core 2GB SoC WiFi eMMC
BOARD_NAME="Inovato Quadra"
BOARDFAMILY="sun50iw6"
BOARD_MAINTAINER=""
BOOTCONFIG="tanix_tx6_defconfig"
CRUSTCONFIG="tanix_tx6_defconfig"
BOOT_FDT_FILE="allwinner/sun50i-h6-inovato-quadra.dtb"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
BOOT_LOGO="desktop"
FULL_DESKTOP="yes"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200 console=tty0 mem=2048M video=HDMI-A-1:e"
OFFSET=16
