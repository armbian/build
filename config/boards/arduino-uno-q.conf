# Qualcomm QRB2210 4 core 2/4GB RAM SoC USB-C
BOARD_NAME="Arduino UNO Q"
BOARD_VENDOR="arduino"
BOARDFAMILY="qrb2210"
BOARD_MAINTAINER="SuperKali sdeleeuw"
INTRODUCED="2025"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
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
		bluetooth bluez gdisk qbootctl

	# USB access: adbd on Debian, USB gadget network on Ubuntu (adbd not available)
	if [[ "${DISTRIBUTION}" == "Debian" ]]; then
		do_with_retries 3 chroot_sdcard_apt_get_install adbd
		chroot_sdcard sed -i 's/"Debian"/"Armbian"/' /usr/lib/android-sdk/platform-tools/adbd-usb-gadget
		chroot_sdcard sed -i 's/"ADB device"/"Arduino UNO Q"/' /usr/lib/android-sdk/platform-tools/adbd-usb-gadget
		chroot_sdcard systemctl enable adbd.service
	else
		# unudhcpd is in the Armbian repo
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled "${SDCARD}"/etc/apt/sources.list.d/armbian.sources
		do_with_retries 3 chroot_sdcard_apt_get_update
		do_with_retries 3 chroot_sdcard_apt_get_install unudhcpd
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled
		do_with_retries 3 chroot_sdcard_apt_get_update
		chroot_sdcard systemctl enable usbgadget-rndis.service
	fi

	# Enable services
	chroot_sdcard systemctl enable qbootctl.service
	chroot_sdcard systemctl enable armbian-resize-filesystem-qcom.service
}

# Pin src:mesa to trixie-backports for the Adreno 702 (qrb2210, chip 0xb2070002;
# needs Mesa >= 25.2.0). trixie ships 25.0.7, backports has 26.x. Desktop only.
function post_family_tweaks__arduino-uno-q_mesa_backports_pin() {
	if [[ "${DISTRIBUTION}" != "Debian" || "${RELEASE}" != "trixie" || "${BUILD_DESKTOP}" != "yes" ]]; then
		display_alert "Skipping Mesa backports pin" "${DISTRIBUTION} ${RELEASE} desktop=${BUILD_DESKTOP}" "info"
		return 0
	fi

	display_alert "Pinning Mesa to trixie-backports" "${BOARD}" "info"

	install -d -m755 "${SDCARD}/etc/apt/preferences.d"
	cat > "${SDCARD}/etc/apt/preferences.d/armbian-mesa-from-backports" <<-'EOF'
		Package: src:mesa
		Pin: release n=trixie-backports
		Pin-Priority: 990
	EOF

	do_with_retries 3 chroot_sdcard_apt_get_update

	# full-upgrade: lets apt drop mesa-va-drivers/mesa-vdpau-drivers
	# (their drivers are now provided directly by mesa-libgallium).
	do_with_retries 3 chroot_sdcard_apt_get full-upgrade
}

function post_family_tweaks_bsp__arduino-uno-q_usb_gadget() {
	# BSP is built once and cached across distros, so install files unconditionally.
	# The usbgadget-rndis service is enabled in post_family_tweaks__ only when adbd is unavailable.
	display_alert "Installing USB gadget network scripts" "${BOARD}" "info"
	install -Dm755 "$SRC/packages/bsp/usb-gadget-network/setup-usbgadget-network.sh" "$destination/usr/local/bin/setup-usbgadget-network.sh"
	install -Dm755 "$SRC/packages/bsp/usb-gadget-network/remove-usbgadget-network.sh" "$destination/usr/local/bin/remove-usbgadget-network.sh"
	install -Dm644 "$SRC/packages/bsp/usb-gadget-network/usbgadget-rndis.service" "$destination/usr/lib/systemd/system/usbgadget-rndis.service"
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
