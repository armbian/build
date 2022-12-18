# Rockchip RK3568 quad core SOC with 1-8GB eMMC USB3
BOARD_NAME="Lubancat2"
BOARDFAMILY="rk35xx"
BOARD_FIRMWARE_INSTALL="-full"
BOARD_MAINTAINER="Andyshrk"
BOOTCONFIG="lubancat-2-rk3568_defconfig"
KERNEL_TARGET="edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-lubancat-2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# Mainline U-Boot
function post_family_config_branch_edge__lubancat2_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git" # Kwiboo U-Boot
	unset BOOTBRANCH
	declare BOOTPATCHDIR="v2024.07-lubancat2" 			      # empty, no patchs needed
	declare -g BOOTBRANCH_BOARD="tag:v2024.07-rc3"                        # commit: a7f0154c4128 as of v2024.07-rc3
	declare -g BOOTDIR="u-boot-${BOARD}"                                  # do not share u-boot directory
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
