# Rockchip RK3568 quad core 4GB-8GB GBE PCIe USB3 SATA NVMe
BOARD_NAME="Mixtile Edge 2"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge,vendor"
BOOT_FDT_FILE="rockchip/rk3568-mixtile-edge2.dtb"
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
SRC_CMDLINE="earlycon=uart8250,mmio32,0xfe660000 loglevel=7 console=ttyS2,1500000" # for extlinux / EXT=u-boot-menu

# Mainline U-Boot
function post_family_config__h96_max_use_mainline_uboot() {
	if [[ "${BRANCH}" == "vendor" || "${BRANCH}" == "legacy" ]]; then
		display_alert "$BOARD" "Using vendor U-Boot for $BOARD / $BRANCH" "info" # See below hook
		return
	fi

	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="generic-rk3568_defconfig"             # Use generic defconfig which should boot all RK3568 boards
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2024.07"
	declare -g BOOTPATCHDIR="v2024.07/board_${BOARD}"
	declare -g BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

function post_family_config_branch_vendor__kernel_and_uboot_rk35xx_mixtile_edge2() {
	# Copypasta from rockchip-rk3588.conf family file -- we _really_ gotta find a better way!
	declare -g KERNEL_MAJOR_MINOR="6.1" # Major and minor versions of this kernel.
	declare -g KERNELSOURCE='https://github.com/armbian/linux-rockchip.git'
	declare -g KERNELBRANCH='branch:rk-6.1-rkr3'
	declare -g KERNELPATCHDIR='rk35xx-vendor-6.1'
	declare -g LINUXFAMILY=rk35xx
	declare -g -i KERNEL_GIT_CACHE_TTL=120 # 2 minutes
	declare -g OVERLAY_PREFIX='rk35xx'

	# Use vendor u-boot, same as rk35xx; we've a defconfig and dt in there
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH='branch:next-dev-v2024.03' # Always use same version as rk3588, they share a patch dir
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx"
	declare -g BOOTCONFIG="mixtile-edge2-rk3568_defconfig"
}
