# Ayn Odin2 Configuration
declare -g BOARD_NAME="Ayn Odin2"
declare -g BOARD_VENDOR="ayntec"
declare -g BOARD_MAINTAINER="FantasyGmm"
declare -g BOARDFAMILY="sm8550"
declare -g KERNEL_TARGET="old,current,edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"
declare -g BOOTFS_TYPE="fat"
declare -g BOOTSIZE="256"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g BOOTIMG_CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused rw quiet rootwait"

# Use the full firmware, complete linux-firmware plus Armbian's
declare -g BOARD_FIRMWARE_INSTALL="-full"
declare -g DESKTOP_AUTOLOGIN="yes"

function ayn-odin2_is_userspace_supported() {
	[[ "${RELEASE}" == "jammy" ]] && return 0
	[[ "${RELEASE}" == "trixie" ]] && return 0
	[[ "${RELEASE}" == "noble" ]] && return 0
	[[ "${RELEASE}" == "plucky" ]] && return 0
	return 1
}

function pre_customize_image__ayn-odin2_alsa_ucm_conf() {
	if ! ayn-odin2_is_userspace_supported; then
		return 0
	fi

	display_alert "Add alsa-ucm-conf for ${BOARD}" "${RELEASE}" "warn"
	(
		cd "${SDCARD}/usr/share/alsa" || exit 6
		curl -L -o temp.zip "https://github.com/AYNTechnologies/alsa-ucm-conf/archive/refs/heads/ayn/v1.2.13.zip"
		unzip -o temp.zip
		unzip_dir=$(unzip -Z1 temp.zip | head -n1 | cut -d/ -f1)
		cp -rf "${unzip_dir}/"* .
		rm -rf "$unzip_dir" temp.zip
	)
}

function post_family_tweaks_bsp__ayn-odin2_firmware() {
	display_alert "Install firmwares for ${BOARD}" "${RELEASE}" "warn"

	# USB Gadget Network service
	mkdir -p $destination/usr/local/bin/
	mkdir -p $destination/usr/lib/systemd/system/
	mkdir -p $destination/etc/initramfs-tools/scripts/init-bottom/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/setup-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/remove-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/usb-gadget-network/usbgadget-rndis.service $destination/usr/lib/systemd/system/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-hook $destination/etc/initramfs-tools/hooks/usb-gadget
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-premount $destination/etc/initramfs-tools/scripts/init-premount/usb-gadget
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/dropbear $destination/etc/initramfs-tools/scripts/init-premount/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/kill-dropbear $destination/etc/initramfs-tools/scripts/init-bottom/

	return 0
}

function post_family_tweaks__ayn-odin2_enable_services() {
	if ! ayn-odin2_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	if [[ "${RELEASE}" == "jammy" ]] || [[ "${RELEASE}" == "noble" ]] || [[ "${RELEASE}" == "plucky" ]]; then
		display_alert "Adding Mesa PPA For Ubuntu ${BOARD}" "warn"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:kisak/kisak-mesa --yes

		do_with_retries 3 chroot_sdcard_apt_get_update
		display_alert "Installing Mesa Vulkan Drivers"
		do_with_retries 3 chroot_sdcard_apt_get_install libgl1-mesa-dri mesa-vulkan-drivers vulkan-tools
	fi

	# We need unudhcpd from armbian repo, so enable it
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled "${SDCARD}"/etc/apt/sources.list.d/armbian.sources

	do_with_retries 3 chroot_sdcard_apt_get_update
	display_alert "Installing ${BOARD} tweaks" "warn"
	do_with_retries 3 chroot_sdcard_apt_get_install alsa-ucm-conf qbootctl qrtr-tools unudhcpd mkbootimg
	# disable armbian repo back
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled
	do_with_retries 3 chroot_sdcard_apt_get_update
	chroot_sdcard systemctl enable qbootctl.service

	# Add Gamepad udev rule
	echo 'SUBSYSTEM=="input", ATTRS{name}=="AYN Odin2 Gamepad", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"' > "${SDCARD}"/etc/udev/rules.d/99-ignore-gamepad.rules
	# Not Any driver support suspend mode
	chroot_sdcard systemctl mask suspend.target

	chroot_sdcard systemctl enable usbgadget-rndis.service
	cp $SRC/packages/bsp/ayn-odin2/LinuxLoader.cfg "${SDCARD}"/boot/

	return 0
}

function post_family_tweaks_bsp__ayn-odin2_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "warn"
	declare file_added_to_bsp_destination # Will be filled in by add_file_from_stdin_to_bsp_destination
	# Using odin2's firmware for now
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/ayn-odin2-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for f in /lib/firmware/qcom/sm8550/ayn/odin2portal/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/a740_sqe.fw" # Extra one for dpu
		add_firmware "qcom/gmu_gen70200.bin" # Extra one for gpu
		add_firmware "qcom/vpu/vpu30_p4.mbn" # Extra one for vpu
		# Extra one for wifi
		for f in /lib/firmware/ath12k/WCN7850/hw2.0/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
		# Extra one for bt
		for f in /lib/firmware/qca/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

function pre_umount_final_image__update_ABL_settings() {
	if [ -z "$BOOTFS_TYPE" ]; then
		return 0
	fi
	display_alert "Update ABL settings for " "${BOARD}" "info"
	uuid_line=$(head -n 1 "${SDCARD}"/etc/fstab)
	rootfs_image_uuid=$(echo "${uuid_line}" | awk '{print $1}' | awk -F '=' '{print $2}')
	initrd_name=$(find "${SDCARD}/boot/" -type f -name "config-*" | sed 's/.*config-//')
	sed -i "s/UUID_PLACEHOLDER/${rootfs_image_uuid}/g" "${MOUNT}"/boot/LinuxLoader.cfg
	sed -i "s/INITRD_PLACEHOLDER/${initrd_name}/g" "${MOUNT}"/boot/LinuxLoader.cfg
}
