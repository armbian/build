# Milk-V Duo S (Sophgo SG2000) - RISC-V mode
# T-Head C906 @ 1GHz, 512MB LPDDR3, microSD, 100M Ethernet, USB-C OTG, USB-A,
# AIC8800D80 Wi-Fi 6 + BT 5, 26-pin + 14-pin GPIO headers.
#
# The SG2000 has both a Cortex-A53 and a C906 RISC-V core, and only one of them
# runs at a time. Which one is chosen by the slide switch on the board, which is
# what brings that core out of reset and runs the BootROM on it.
#
# Two board files for one physical board, because BOARD is the build target and
# each produces a different image. One image runs from either medium (SD or eMMC).
# The first line of the boot log is the quickest way to tell which core you are
# actually on: it starts with 'B' for ARM and 'C' for RISC-V.
#
# https://milkv.io/duo-s
BOARD_NAME="Milk-V Duo S"
BOARD_VENDOR="milkv"
BOARDFAMILY="sophgo-sg200x-riscv64"
BOARD_MAINTAINER="lukaszsobala"
INTRODUCED="2024"
KERNEL_TARGET="edge,bleedingedge"
KERNEL_TEST_TARGET="edge"
BOOT_FDT_FILE="sophgo/sg2000-milkv-duo-s.dtb"
# The silicon could in principle drive a panel through pins on the GPIO
# headers, but no device tree we ship enables any of it, so every image is
# declared headless.
HAS_VIDEO_OUTPUT="no"

# Because 512MB of RAM does not go far.
PACKAGE_LIST_BOARD_REMOVE="snapd cloud-init"

enable_extension "sophgo-sg200x-aic8800"
