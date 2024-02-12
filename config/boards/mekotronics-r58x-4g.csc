# Rockchip RK3588 SoC octa core 4-16GB SoC 2x1GBe eMMC USB3 NVMe SATA 4G WiFi/BT HDMI DP HDMI-In RS232 RS485
declare -g BOARD_NAME="Mekotronics R58X-4G"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="monkaBlyat"
declare -g KERNEL_TARGET="legacy"
declare -g BOOT_FDT_FILE="rockchip/rk3588-blueberry-edge-v12-linux.dtb" # Specific to this board
declare -g UEFI_EDK2_BOARD_ID="r58x"                                    # This _only_ used for uefi-edk2-rk3588 extension

# Source vendor-specific configuration
source "${SRC}/config/sources/vendors/mekotronics/mekotronics-rk3588.conf.sh"

# Board-specific override
declare -g BOOTCONFIG="rk3588_meko_r58x_defconfig" # specific, with nvme
