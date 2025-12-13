# Rockchip RK3588 SoC octa core 16GB 4x PCIe Gen3 HDMI USB3 DP HDMIrx eMMC SD PD Mini-PCIe
declare -g BOARD_NAME="Mixtile Blade 3"
declare -g BOARD_VENDOR="mixtile"
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
function post_family_config__vendor_uboot_blade3() {
	if [[ "${BRANCH}" == "vendor" || "${BRANCH}" == "legacy" ]]; then
		display_alert "$BOARD" "Using vendor u-boot for $BOARD on branch $BRANCH" "info"
	else
		return 0
	fi

	display_alert "$BOARD" "Configuring $BOARD vendor u-boot (using Radxa's older next-dev-v2024.03)" "info"
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing

	# Override the stuff from rockchip-rk3588 family; Meko's have a patch for stable MAC address that breaks with Radxa's next-dev-v2024.10+
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH='branch:next-dev-v2024.03' # NOT next-dev-v2024.10
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx"
}

function post_family_config__blade3_use_mainline_uboot() {
	if [[ "${BRANCH}" != "edge" ]]; then
		return 0
	fi

	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="mixtile-blade3-rk3588_defconfig" # MAINLINE U-BOOT OVERRIDE

	declare -g BOOTDELAY=1

	BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	BOOTBRANCH="tag:v2025.10"
	BOOTPATCHDIR="v2025.10" # with 000.patching_config.yaml - no patching, straight .dts/defconfigs et al

	BOOTDIR="u-boot-${BOARD}"

	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin" # NOT u-boot-rockchip-spi.bin
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd                                 # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	# @TODO: boot order stuff; we want to boot nvme / usb / sd before eMMC

	declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
}

function post_family_config_branch_edge__different_dtb_for_edge() {
	declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-blade3.dtb"
	display_alert "$BOARD" "Using ${BOOT_FDT_FILE} for ${BRANCH}" "warn"
}
