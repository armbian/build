# Rockchip RK3566 quad core 2GB-8GB GBE eMMC NVMe USB3 WiFi
BOARD_NAME="BigTreeTech CB2"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="bigtreetech-cb2-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3566-bigtreetech-cb2.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
OVERLAY_PREFIX='rk3566'
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

function post_family_config__bigtreetech-cb2_uboot_overrides() {
	case $BRANCH in
		current)
			bigtreetech_uboot
			;;
		edge)
			mainline_uboot
			;;
	esac
}

function bigtreetech_uboot() {
	display_alert "$BOARD" "BigTreeTech u-boot overrides" "info"

	declare -g BOOTSOURCE='https://github.com/bigtreetech/u-boot'
	declare -g BOOTBRANCH='branch:stable-4.19-cb2'
	declare -g BOOTPATCHDIR='NEED-NOT'
	declare -g CMD_MTDPARTS=y

	declare -g SKIP_BOOTSPLASH="yes"

	declare -g BOOTCONFIG="bigtreetech_cb2_defconfig"
}

DDR_BLOB="rk35/rk3566_ddr_1056MHz_v1.21.bin"
BL31_BLOB="rk35/rk3568_bl31_v1.44.elf" # NOT a typo, bl31 is shared across 68 and 66

function mainline_uboot() {
	display_alert "$BOARD" "mainline u-boot overrides" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10/board_bigtreetech-cb2"
	#declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g BOOTDELAY=1                            # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}

	#declare -g BOOTCONFIG=generic-rk3568_defconfig
}

# vim: ft=bash
