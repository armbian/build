# Rockchip RK3576 SoC octa core 8-64GB SoC 2*GBe eMMC USB3 NvME WIFI
BOARD_NAME="Radxa CM4-IO"
BOARDFAMILY="rk35xx"
BOOTCONFIG="radxa-cm4-io-rk3576_defconfig"
KERNEL_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-radxa-cm4-io.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
enable_extension "radxa-aic8800"
AIC8800_TYPE="usb"
BOARD_MAINTAINER=""

function post_family_tweaks__radxa-cm4-io_naming_audios() {
	display_alert "$BOARD" "Renaming radxa-cm4-io audios" "info"

	mkdir -p "$SDCARD/etc/udev/rules.d/"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > "$SDCARD/etc/udev/rules.d/90-naming-audios.rules"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> "$SDCARD/etc/udev/rules.d/90-naming-audios.rules"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> "$SDCARD/etc/udev/rules.d/90-naming-audios.rules"

	return 0
}
