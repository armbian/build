# Rockchip RK3588 SoC octa core 4-16GB SoC 1GBe eMMC USB3 SATA WiFi/BT
declare -g BOARD_NAME="Mekotronics R58 MiniPC"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="monkaBlyat"
declare -g KERNEL_TARGET="vendor"
declare -g BOOTCONFIG="mekotronics_r58-rk3588_defconfig"              # generic ebv-ish defconfig
declare -g BOOT_FDT_FILE="rockchip/rk3588-blueberry-minipc-linux.dtb" # Specific to this board
declare -g UEFI_EDK2_BOARD_ID="r58-mini"                              # This _only_ used for uefi-edk2-rk3588 extension

# Source vendor-specific configuration
source "${SRC}/config/sources/vendors/mekotronics/mekotronics-rk3588.conf.sh"
