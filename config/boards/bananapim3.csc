# Allwinner A83T octa core 2Gb SoC Wifi
BOARD_NAME="Banana Pi M3"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER="AaronNGray"
INTRODUCED="2015"
BOOTCONFIG="Sinovoip_BPI_M3_defconfig"
OVERLAY_PREFIX="sun8i-a83t"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
# u-boot rides the sunxi family default (v2026.07-rc4 / v2026.07-sunxi); the one
# A83T fix (MMC calibrate) is board-scoped in v2026.07-sunxi/board_bananapim3.
# Was self-pinned to v2024.01 (fails on trixie).
