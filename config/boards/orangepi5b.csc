# Rockchip RK3588S octa core 4/8/16GB RAM SoC eMMC USB3 USB-C GbE
BOARD_NAME="Orange Pi 5B"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-5b-rk3588s_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="edge,vendor"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-orangepi-5b.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

declare -g BLUETOOTH_HCIATTACH_PARAMS="-s 115200 /dev/ttyS9 bcm43xx 1500000" # For the bluetooth-hciattach extension
enable_extension "bluetooth-hciattach"                                       # Enable the bluetooth-hciattach extension

function post_family_tweaks_bsp__orangepi5b_copy_usb2_service() {
	if [[ $BRANCH == "edge" || $BRANCH == "current" ]]; then
		return
	fi

	display_alert "Installing BSP firmware and fixups"

	# Add USB2 init service. Otherwise, USB2 and TYPE-C won't work by default
	cp $SRC/packages/bsp/orangepi5/orangepi5-usb2-init.service $destination/lib/systemd/system/

	return 0
}

function post_family_tweaks__orangepi5b_enable_usb2_service() {
	if [[ $BRANCH == "edge" || $BRANCH == "current" ]]; then
		return
	fi

	display_alert "$BOARD" "Installing board tweaks" "info"

	# enable usb2 init service
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable orangepi5-usb2-init.service >/dev/null 2>&1"

	return 0
}

function post_family_tweaks__orangepi5b_naming_audios() {
	if [[ $BRANCH == "edge" || $BRANCH == "current" ]]; then
		return
	fi

	display_alert "$BOARD" "Renaming orangepi5b audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}