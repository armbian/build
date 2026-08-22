# Rockchip RK3588S octa core SoC LPDDR4x GBe eMMC USB3 mini-PCIe HDMI
BOARD_NAME="LubanCat 4"
BOARD_VENDOR="embedfire"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="miskin-lee"
INTRODUCED="2024"
BOOTCONFIG="lubancat-4-rk3588s_defconfig"
BOOT_SOC="rk3588"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588s-lubancat-4.dtb"
BOOT_SCENARIO="spl-blobs"

# Mainline U-Boot - use post_family_config hook to override family config.
function post_family_config__lubancat_4_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"

	BOOT_SCENARIO="tpl-blob-atf-mainline"
	prepare_boot_configuration

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go.
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
