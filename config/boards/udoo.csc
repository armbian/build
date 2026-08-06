# Freescale / NXP iMx dual/quad core 1-2GB Gbe Wifi
BOARD_NAME="Udoo"
BOARD_VENDOR="seco"
BOARDFAMILY="imx6"
BOARD_MAINTAINER="igorpecovnik"
INTRODUCED="2014"
BOOTCONFIG="udoo_defconfig"
SERIALCON="ttymxc1"
BOOTSCRIPT="boot-udoo.cmd:boot.cmd"
BOOTENV_FILE="udoo.txt"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
# u-boot (mainline v2026.07) + SPL raw-sector load are set in the imx6 family conf.
