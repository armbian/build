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
# u-boot rides the sunxi family default (v2026.07 / v2026.07-sunxi).
# Was self-pinned to v2024.01 (fails on trixie); defconfig + DT are upstream.
# NB: do NOT re-add the old A83T sunxi_mmc_can_calibrate patch - upstream
# excludes A83T on purpose (no delay-calibration HW) and forcing it breaks the
# SPL MMC read (Error -38).
# Boots from SD. eMMC boot untested via armbian-install (see build #10099:
# install leaves /boot empty on single-partition sunxi eMMC) - not a u-boot limit.
