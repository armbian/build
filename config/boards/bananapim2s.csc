# Amlogic A311D 4GB RAM eMMC 2xGBE USB3
BOARD_NAME="Banana Pi M2S"
BOARDFAMILY="meson-g12b"
BOOTCONFIG="bananapim2s_defconfig"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="amlogic/meson-g12b-a311d-bananapi-m2s.dtb"

# Newer u-boot; new DT, Makefile and defconfig in patch/u-boot/v2022.10/board_bananapi-m2s
BOOTBRANCH_BOARD="tag:v2022.10"
BOOTPATCHDIR="v2022.10"
