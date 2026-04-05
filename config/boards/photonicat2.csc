# Rockchip RK3576 octa core 4-16GB 2x GbE eMMC HDMI WiFi USB3 3x M.2 (B/E/M-Key)

BOARD_NAME="Photonicat2"
BOARD_VENDOR="ariaboard"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOOTCONFIG="photonicat2-rk3576_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="no"
BOOT_FDT_FILE="rockchip/rk3576-photonicat2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOARD_FIRMWARE_INSTALL="-full"
ENABLE_EXTENSIONS="radxa-aic8800,photonicat-pm"
AIC8800_TYPE="usb"

# Enable btrfs support in u-boot
enable_extension "uboot-btrfs"

# Mainline U-Boot
function post_family_config__photonicat2_mainline_uboot() {
	display_alert "$BOARD" "Using Mainline U-Boot v2026.01" "info"
	declare -g BOOTSOURCE='https://github.com/u-boot/u-boot.git'
	declare -g BOOTBRANCH='tag:v2026.01'
	declare -g BOOTPATCHDIR='v2026.01'
	declare -g BOOTDIR="u-boot-${BOARD}"

	# Use binman for Mainline U-Boot
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable legacy rockchip processing
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Custom write function for u-boot-rockchip.bin
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
