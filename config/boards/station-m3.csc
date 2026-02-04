# Rockchip RK3588s 2GB-16GB GBE eMMC NVMe SATA USB3 WiFi
BOARD_NAME="Station M3"
BOARD_VENDOR="firefly"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="vendor,current"
KERNEL_TEST_TARGET="vendor"
BOOTCONFIG="roc-pc-rk3588s_defconfig"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-roc-pc.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="station-m3" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__station-m3_naming_audios() {
	display_alert "$BOARD" "Renaming station-m3 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
