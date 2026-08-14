# Rockchip RK3568 quad core 1-8GB SoC 2x1GBe eMMC USB3
BOARD_NAME="YouYeeToo YY3568"
BOARD_VENDOR="youyeetoo"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="hqnicolas"
INTRODUCED="2023"
BOOTCONFIG="youyeetoo-yy3568-rk3568_defconfig"
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge,vendor"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-yy3568.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__yy3568_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="youyeetoo-yy3568-rk3568_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07/board_${BOARD}"

	# Let binman combine U-Boot with Armbian's trusted firmware and DDR blobs.
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# The mainline binman image is complete and does not need vendor post-processing.
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

function pre_config_uboot_target__yy3568_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "mmc0" "scsi" "usb" "pxe" "dhcp") # mmc1=SD, mmc0=eMMC
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}
