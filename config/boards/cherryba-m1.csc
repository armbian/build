# Allwinner H618 quad core 1GB 2GB 4GB RAM SoC WiFi USB-C emmc
BOARD_NAME="CherryBa M1"
BOARD_VENDOR="allwinner"
BOARDFAMILY="sun50iw9"
BOOTCONFIG="cherryba-m1_defconfig"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
FORCE_BOOTSCRIPT_UPDATE="yes"
# Bumped off the v2025.04 self-pin to the sunxi64 family default (v2026.07):
# the half-applied pin built v2026.07 source with the v2025.04 patch and failed.
# Board DT + defconfig now ride v2026.07-sunxi64/board_cherryba-m1.
BOARD_MAINTAINER="IsMrX"
INTRODUCED="2024"
