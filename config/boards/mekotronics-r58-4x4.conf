# Rockchip RK3588 SoC octa core 4-16GB SoC 2x1GBe eMMC USB3 NVMe SATA WiFi/BT HDMI DP HDMI-In RS232 RS485
declare -g BOARD_NAME="Mekotronics R58-4X4"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="150balbes"
declare -g KERNEL_TARGET="vendor"
declare -g BOOTCONFIG="mekotronics_r58x-rk3588_defconfig"               # vendor u-boot; with NVMe and a DTS
declare -g BOOT_FDT_FILE="rockchip/rk3588-r58-4x4.dtb" 			# Specific to this board
declare -g UEFI_EDK2_BOARD_ID="r58-4x4"                                 # This _only_ used for uefi-edk2-rk3588 extension
declare -g DISPLAY_MANAGER="wayland"
declare -g ASOUND_STATE="asound.state.rk3588hd"

# Source vendor-specific configuration
source "${SRC}/config/sources/vendors/mekotronics/mekotronics-rk3588.conf.sh"

