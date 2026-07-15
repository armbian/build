# Freescale / NXP iMx6 dual-quad core 1GB/2GB RAM SoC Wifi/BT GBE
BOARD_NAME="Cubox i2eX/i4"
BOARD_VENDOR="solidrun"
BOARDFAMILY="imx6"
BOARD_MAINTAINER="igorpecovnik"
INTRODUCED="2014"
BOOTCONFIG="mx6cuboxi_defconfig"
BOOTSCRIPT="boot-cubox.cmd:boot.cmd"
BOOTENV_FILE="cubox.txt"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
# Promoted from .eos: u-boot bumped off the SolidRun fork to mainline v2026.07
# (builds on trixie). u-boot version + SPL raw-sector load are in the imx6 family
# conf; SERIALCON defaults to ttymxc0. Boots on hardware (SOM auto-detected).
