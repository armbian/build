# Allwinner H618 quad core 1GB/1.5GB/2GB/4GB RAM
BOARD_NAME="Orange Pi Zero2W"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="chraac"
INTRODUCED="2023"
BOOTCONFIG="orangepi_zero2w_defconfig"
# u-boot rides the sunxi64 family default (v2026.07 / v2026.07-sunxi64);
# defconfig + DT are upstream. Was self-pinned to v2025.04 (H616 DRAM patches
# it needed are now upstream: size-detection rework + 1.5GB).
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

enable_extension "uwe5622-allwinner"
