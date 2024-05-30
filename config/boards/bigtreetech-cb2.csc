# Rockchip RK3566 quad core 2GB-8GB GBE eMMC NVMe USB3 WiFi
BOARD_NAME="BigTreeTech CB2"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="generic-rk3568_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3566-bigtreetech-cb2.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
OVERLAY_PREFIX='rk3566'
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

DDR_BLOB="rk35/rk3566_ddr_1056MHz_v1.18.bin"
BL31_BLOB="rk35/rk3568_bl31_v1.43.elf" # NOT a typo, bl31 is shared across 68 and 66

function post_family_config__bigtreetech-cb2_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (Kwiboo's tree) u-boot overrides" "info"

	declare -g BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git"
	declare -g BOOTBRANCH="branch:rk3xxx-2024.07"
	declare -g BOOTPATCHDIR="v2024.07/board_${BOARD}" # empty
	declare -g BOOTDIR="u-boot-${BOARD}"              # do not share u-boot directory
	declare -g BOOTDELAY=1                            # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}
}
