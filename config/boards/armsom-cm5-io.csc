# Rockchip RK3576 SoC octa core 8-64GB SoC GBe eMMC USB3 NvME WIFI
BOARD_NAME="CM5 IO (RK3576)"
BOARD_VENDOR="armsom"
BOARDFAMILY="rk35xx"
BOOTCONFIG="armsom-cm5-io-rk3576_defconfig"
KERNEL_TARGET="vendor,edge"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-armsom-cm5-io.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOARD_MAINTAINER="gahingwoo"
INTRODUCED="2024"

function post_family_tweaks__armsom-cm5-io_naming_audios() {
	display_alert "$BOARD" "Renaming armsom-cm5 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

# Mainline U-Boot for edge; vendor keeps the Radxa U-Boot
function post_family_config__armsom_cm5_io_use_mainline_uboot() {
	[[ "${BRANCH}" == vendor* ]] && return 0

	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
