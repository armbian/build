# Amlogic A311D 4GB RAM eMMC USB3 WiFi BT
BOARD_NAME="Radxa Zero 2"
BOARD_VENDOR="radxa"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
BOOTCONFIG="radxa-zero2_config"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
ASOUND_STATE="asound.state.radxa-zero2"
BOOT_FDT_FILE="amlogic/meson-g12b-radxa-zero2.dtb"

BOOTBRANCH_BOARD="tag:v2024.07"
BOOTPATCHDIR="v2024.07"
