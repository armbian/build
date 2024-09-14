# Amlogic A311D 4GB RAM eMMC USB3 WiFi BT
BOARD_NAME="Radxa Zero 2"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER="monkaBlyat"
BOOTCONFIG="radxa-zero2_config"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
ASOUND_STATE="asound.state.radxa-zero2"
BOOT_FDT_FILE="amlogic/meson-g12b-radxa-zero2.dtb"

# Newer u-boot for the Zero2
# 2022.10: Radxa's patches with new DT, Makefile and defconfig in v2022.10/board_radxa-zero2 dir; common to 22.10's meson64 boot-usb-first
# v2023.10: board-specific boot-usb-first patch; zero2 landed in upstream u-boot v2023.07-rc1
BOOTBRANCH_BOARD="tag:v2024.07"
BOOTPATCHDIR="v2024.07"
