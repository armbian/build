# Allwinner H618 quad core 1GB/2GB/4GB RAM
BOARD_NAME="Longan Pi 3H"
BOARD_VENDOR="mangopi"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER=""
INTRODUCED="2023"
BOOTCONFIG="longanpi_3h_defconfig"
# u-boot rides the sunxi64 family default (v2026.07 / v2026.07-sunxi64).
# DT (sun50i-h618-longanpi-3h + longan-module-3h.dtsi, incl. eMMC) is upstream;
# the defconfig is carried board-scoped in v2026.07-sunxi64/board_longanpi-3h.
# Was self-pinned to v2024.10.
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
enable_extension "radxa-aic8800" # compatible with radxa-aic8800
AIC8800_TYPE="usb"
