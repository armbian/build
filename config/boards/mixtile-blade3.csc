# Rockchip RK3588 SoC octa core 16GB 4x PCIe Gen3 HDMI USB3 DP HDMIrx eMMC SD PD Mini-PCIe
declare -g BOARD_NAME="Mixtile Blade 3"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g KERNEL_TARGET="legacy,vendor,edge"
declare -g BOOT_FDT_FILE="rockchip/rk3588-blade3-v101-linux.dtb" # Included in https://github.com/armbian/linux-rockchip/pull/64 # has a hook to change it for edge below

declare -g BOOT_SCENARIO="spl-blobs" # so we don't depend on defconfig naming convention
declare -g BOOT_SOC="rk3588"         # so we don't depend on defconfig naming convention
declare -g BOOTCONFIG="blade3_defconfig"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="blade3" # This _only_ used for uefi-edk2-rk3588 extension

# newer blobs from rockchip. tested to work.
# set as variables, early, so they're picked up by `prepare_boot_configuration()`
declare -g DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.11.bin'
declare -g BL31_BLOB='rk35/rk3588_bl31_v1.38.elf'

# post_family_config hook which only runs when branch is legacy.
function post_family_config__uboot_mixtile() {
	display_alert "$BOARD" "Configuring Mixtile u-boot" "info"
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH="commit:ddc91cd08c10f625f7a7c93033042aa4071c78a8" # specific commit in next-dev branch
	declare -g OVERLAY_PREFIX='rockchip-rk3588'
	declare -g BOOTDIR="u-boot-${BOARD}"                   # do not share u-boot directory
	declare -g BOOTPATCHDIR="legacy/u-boot-mixtile-rk3588" # Few patches in there; defconfig & PD hacks
	declare -g BOOTDELAY=1                                 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

function post_family_config_branch_edge__different_dtb_for_edge() {
	declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-blade3.dtb"
	display_alert "$BOARD" "Using ${BOOT_FDT_FILE} for ${BRANCH}" "info"
}
