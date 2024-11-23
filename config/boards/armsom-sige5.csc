# Rockchip RK3576 SoC octa core 8-64GB SoC 2*GBe eMMC USB3 NvME WIFI
BOARD_NAME="ArmSoM Sige5"
BOARDFAMILY="rk35xx"
BOOTCONFIG="armsom-sige5-rk3576_defconfig"
KERNEL_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-armsom-sige5.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOARD_MAINTAINER=""

function post_family_config_branch_vendor__armsom-sige7_use_vendor_uboot() {
	display_alert "$BOARD" "vendor u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/ArmSoM/u-boot.git"
	declare -g BOOTBRANCH="tag:rk3576-6.1-rk3.1"
	declare -g BOOTPATCHDIR="legacy/u-boot-armsom-rk3576"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB TEE=$RKBIN_DIR/$BL32_BLOB spl/u-boot-spl.bin u-boot.dtb u-boot.itb;;idbloader.img u-boot.itb"
}

function post_family_tweaks__armsom-sige7_naming_audios() {
	display_alert "$BOARD" "Renaming armsom-sige7 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
