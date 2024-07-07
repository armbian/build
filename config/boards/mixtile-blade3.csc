# Rockchip RK3588 SoC octa core 16GB 4x PCIe Gen3 HDMI USB3 DP HDMIrx eMMC SD PD Mini-PCIe
declare -g BOARD_NAME="Mixtile Blade 3"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g KERNEL_TARGET="vendor,edge"
declare -g BOOT_FDT_FILE="rockchip/rk3588-blade3-v101-linux.dtb" # Included in https://github.com/armbian/linux-rockchip/pull/64 # has a hook to change it for edge below
declare -g BOOT_SCENARIO="spl-blobs"                             # so we don't depend on defconfig naming convention
declare -g BOOT_SOC="rk3588"                                     # so we don't depend on defconfig naming convention
declare -g BOOTCONFIG="blade3_defconfig"                         # there is also blade3_sata_defconfig available
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="blade3" # This _only_ used for uefi-edk2-rk3588 extension

# Vendor u-boot; use the default family (rockchip-rk3588) u-boot. See config/sources/families/rockchip-rk3588.conf
function post_family_config__vendor_uboot_mekotronics() {
	display_alert "$BOARD" "Configuring $BOARD vendor u-boot" "info"
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

function post_family_config_branch_edge__different_dtb_for_edge() {
	declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-blade3.dtb"
	display_alert "$BOARD" "Using ${BOOT_FDT_FILE} for ${BRANCH}" "info"
}
