# Qualcomm QRB2210 4 core 2/4GB RAM SoC USB-C
BOARD_NAME="Arduino UNO Q"
BOARD_VENDOR="arduino"
BOARDFAMILY="qrb2210"
BOARD_MAINTAINER=""
KERNEL_TARGET="edge"
BOOTCONFIG="qcom_defconfig"
BOOT_FDT_FILE="qcom/qrb2210-arduino-imola.dtb"
SERIALCON="ttyMSM0"
BOOTFS_TYPE="fat"
BOOTSIZE="512"

function post_family_tweaks__arduino-uno-q() {
	display_alert "Installing packages" "${BOARD}" "info"

	# Install packages
	do_with_retries 3 chroot_sdcard_apt_get_update
	do_with_retries 3 chroot_sdcard_apt_get_install \
		rmtfs qrtr-tools protection-domain-mapper tqftpserv \
		bluetooth bluez gdisk adbd qbootctl

	# ADB branding
	chroot_sdcard sed -i 's/"Debian"/"Armbian"/' /usr/lib/android-sdk/platform-tools/adbd-usb-gadget
	chroot_sdcard sed -i 's/"ADB device"/"Arduino UNO Q"/' /usr/lib/android-sdk/platform-tools/adbd-usb-gadget

	# Enable services
	chroot_sdcard systemctl enable adbd.service
	chroot_sdcard systemctl enable qbootctl.service
	chroot_sdcard systemctl enable armbian-resize-filesystem-qcom.service
}

function post_family_tweaks_bsp__arduino-uno-q_resize_rootfs() {
	display_alert "Installing rootfs resize script" "${BOARD}" "info"
	install -Dm755 "$SRC/packages/bsp/arduino/armbian-resize-filesystem-qcom" "$destination/usr/lib/armbian/armbian-resize-filesystem-qcom"
	install -Dm644 "$SRC/packages/bsp/arduino/armbian-resize-filesystem-qcom.service" "$destination/usr/lib/systemd/system/armbian-resize-filesystem-qcom.service"
}

function post_family_tweaks_bsp__arduino-uno-q_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/initramfs-hook-qcm2290-fw" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		add_firmware "qcom/qcm2290/a702_zap.mbn"
		add_firmware "qcom/a702_sqe.fw"
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}
