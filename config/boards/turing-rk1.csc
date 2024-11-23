# Rockchip RK3588 octa core 8/16/32GB RAM SoM GBE NVMe eMMC USB3
BOARD_NAME="Turing RK1"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="turing-rk1-rk3588_defconfig"
BOOT_SOC="rk3588"
KERNEL_TARGET="edge,current,vendor"
KERNEL_TEST_TARGET="vendor,current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588-turing-rk1.dtb"
BOOT_SCENARIO="spl-blobs"
DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_uart9_115200_v1.16.bin'

function post_family_config__turing-rk1_default_serial_console_by_branch() {
	display_alert "$BOARD" "Declare serialcon for $BOARD / $BRANCH" "info"

	case $BRANCH in
		vendor)
			declare -g SERIALCON="ttyS9"
			;;
		*)
			declare -g SERIALCON="ttyS0"
			;;
	esac

	return 0
}

function post_family_tweaks__turing-rk1_default_serial_console_by_branch() {
	display_alert "$BOARD" "Modify bootscript serial console for $BOARD / $BRANCH" "info"

	case $BRANCH in
		vendor)
			sed -i 's/console=ttyS2,1500000/console=ttyS9,115200/g' $SDCARD/boot/boot.cmd
			;;
		*)
			sed -i 's/console=ttyS2,1500000/console=ttyS0,115200/g' $SDCARD/boot/boot.cmd
			;;
	esac

	mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr

	return 0
}

function post_family_config__turing-rk1_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH='tag:v2024.04'
	declare -g BOOTPATCHDIR="v2024.04"
	declare -g BOOTDELAY=1
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
