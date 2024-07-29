# Rockchip RK3588s 2GB-16GB GBE eMMC NVMe SATA USB3 WiFi
declare -g BOARD_NAME="Khadas Edge2"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="igorpecovnik"
declare -g BOOT_SOC="rk3588" # Just to avoid errors in rockchip64_commmon
declare -g KERNEL_TARGET="vendor,edge"
declare -g KERNEL_TEST_TARGET="vendor"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g BOOT_FDT_FILE="rockchip/rk3588s-khadas-edge2.dtb" # Specific to this board

declare -g BLUETOOTH_HCIATTACH_PARAMS="-s 115200 /dev/ttyS9 bcm43xx 1500000" # For the bluetooth-hciattach extension
enable_extension "bluetooth-hciattach"                                       # Enable the bluetooth-hciattach extension

declare -g KHADAS_OOWOW_BOARD_ID="Edge2" # for use with EXT=output-image-oowow
declare -g UEFI_EDK2_BOARD_ID="edge2"    # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__kedge2_naming_audios() {
	display_alert "$BOARD" "Renaming khadas-edge2 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

declare -g BL32_BLOB='rk35/rk3588_bl32_v1.15.bin'

# for the kedge2, we're counting on the blobs+u-boot in SPI working, as it comes from factory. It does not support bootscripts.
function post_family_config__uboot_kedge2() {
	display_alert "$BOARD" "Configuring ($BOARD) u-boot" "info"

	declare -g BOOTSOURCE='https://github.com/khadas/u-boot.git'
	declare -g BOOTBRANCH='branch:khadas-edges-v2017.09'
	declare -g BOOTPATCHDIR="legacy/u-boot-khadas-edge2-rk3588"
	declare -g BOOTCONFIG="khadas-edge2-rk3588s_defconfig"
	declare -g SRC_EXTLINUX="yes" # For now, use extlinux. Thanks Monka
}
