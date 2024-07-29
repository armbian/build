# Generate kernel and rootfs image for Qcom ABL Custom booting
declare -g BOARD_NAME="Ayn Odin2"
declare -g BOARD_MAINTAINER="FantasyGmm"
declare -g BOARDFAMILY="qcom-abl"
declare -g KERNEL_TARGET="sm8550"
declare -g KERNELPATCHDIR="sm8550-6.7"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"
declare -g BOOTFS_TYPE="fat"
declare -g BOOTSIZE="256"
declare -g BOOTIMG_CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused panic=30 audit=0 allow_mismatched_32bit_el0 rw mem_sleep_default=s2idle"
declare -g IMAGE_PARTITION_TABLE="gpt"

# Use the full firmware, complete linux-firmware plus Armbian's
declare -g BOARD_FIRMWARE_INSTALL="-full"

declare -g DESKTOP_AUTOLOGIN="yes"

function post_family_config_branch_sm8550__edk2_kernel() {
	declare -g KERNELSOURCE='https://github.com/edk2-porting/linux-next'
	declare -g KERNEL_MAJOR_MINOR="6.7" # Major and minor versions of this kernel.
	declare -g KERNELBRANCH="branch:integration/ayn-odin2"
	declare -g LINUXCONFIG="linux-${ARCH}-${BRANCH}" # for this board: linux-arm64-sm8550
	display_alert "Setting up kernel ${KERNEL_MAJOR_MINOR} for" "${BOARD}" "info"
}

function ayn-odin2_is_userspace_supported() {
	[[ "${RELEASE}" == "trixie" || "${RELEASE}" == "sid" || "${RELEASE}" == "mantic" || "${RELEASE}" == "noble" ]] && return 0
	return 1
}

function post_family_tweaks__enable_services() {
	if ! ayn-odin2_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	if [[ "${RELEASE}" == "noble" ]]; then
		display_alert "Adding Mesa PPA For Ubuntu " "${BOARD}" "info"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:oibaf/graphics-drivers --yes --no-update
	fi

	# We need unudhcpd from armbian repo, so enable it
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled "${SDCARD}"/etc/apt/sources.list.d/armbian.list

	# Add zink env
	echo '__GLX_VENDOR_LIBRARY_NAME=mesa' | tee -a "${SDCARD}"/etc/environment
	echo 'MESA_LOADER_DRIVER_OVERRIDE=zink' | tee -a "${SDCARD}"/etc/environment
	echo 'GALLIUM_DRIVER=zink' | tee -a "${SDCARD}"/etc/environment
	# Add Gamepad udev rule
	echo 'SUBSYSTEM=="input", ATTRS{name}=="Ayn Odin2 Gamepad", MODE="0666", ENV{ID_INPUT_MOUSE}="0", ENV{ID_INPUT_JOYSTICK}="1"' > "${SDCARD}"/etc/udev/rules.d/99-ignore-gamepad.rules
	# No driver support for suspend
	chroot_sdcard systemctl mask suspend.target
	# Add Bt Mac Fixed service
	install -Dm655 $SRC/packages/bsp/ayn-odin2/bt-fixed-mac.sh "${SDCARD}"/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/ayn-odin2/bt-fixed-mac.service "${SDCARD}"/usr/lib/systemd/system/
	chroot_sdcard systemctl enable bt-fixed-mac

	do_with_retries 3 chroot_sdcard_apt_get_update
	display_alert "$BOARD" "Installing board tweaks" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install alsa-ucm-conf unudhcpd mkbootimg git

	# Disable armbian repo back
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled
	do_with_retries 3 chroot_sdcard_apt_get_update

	do_with_retries 3 chroot_sdcard_apt_get_install mesa-vulkan-drivers qbootctl qrtr-tools protection-domain-mapper tqftpserv

	# Kernel postinst script to update abl boot partition
	install -Dm655 $SRC/packages/bsp/ayn-odin2/zz-update-abl-kernel "${SDCARD}"/etc/kernel/postinst.d/

	cp $SRC/packages/bsp/ayn-odin2/LinuxLoader.cfg "${SDCARD}"/boot/

	return 0
}

function post_family_tweaks__preset_configs() {
	display_alert "$BOARD" "preset configs for rootfs" "info"
	# Set PRESET_NET_CHANGE_DEFAULTS to 1 to apply any network related settings below
	echo "PRESET_NET_CHANGE_DEFAULTS=1" > "${SDCARD}"/root/.not_logged_in_yet

	# Enable WiFi or Ethernet.
	#      NB: If both are enabled, WiFi will take priority and Ethernet will be disabled.
	echo "PRESET_NET_ETHERNET_ENABLED=0" >> "${SDCARD}"/root/.not_logged_in_yet
	echo "PRESET_NET_WIFI_ENABLED=1" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset user default shell, you can choose bash or zsh
	echo "PRESET_USER_SHELL=zsh" >> "${SDCARD}"/root/.not_logged_in_yet

	# Set PRESET_CONNECT_WIRELESS=y if you want to connect wifi manually at first login
	echo "PRESET_CONNECT_WIRELESS=n" >> "${SDCARD}"/root/.not_logged_in_yet

	# Set SET_LANG_BASED_ON_LOCATION=n if you want to choose "Set user language based on your location?" with "n" at first login
	echo "SET_LANG_BASED_ON_LOCATION=y" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset default locale
	echo "PRESET_LOCALE=en_US.UTF-8" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset timezone
	echo "PRESET_TIMEZONE=Etc/UTC" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset root password
	echo "PRESET_ROOT_PASSWORD=admin" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset username
	echo "PRESET_USER_NAME=odin" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset user password
	echo "PRESET_USER_PASSWORD=admin" >> "${SDCARD}"/root/.not_logged_in_yet

	# Preset user default realname
	echo "PRESET_DEFAULT_REALNAME=Odin" >> "${SDCARD}"/root/.not_logged_in_yet
}

function post_family_tweaks_bsp__firmware_in_initrd() {
	random_mac=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
	declare -g BOOTIMG_CMDLINE_EXTRA="${BOOTIMG_CMDLINE_EXTRA} bt_mac=${random_mac}"
	display_alert "Generate a random Bluetooth MAC address, Mac:${random_mac}" "info"
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination # Will be filled in by add_file_from_stdin_to_bsp_destination
	# Using odin2's firmware for now
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/ayn-odin2-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for f in /lib/firmware/qcom/sm8550/ayn/odin2/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/a740_sqe.fw" # Extra one for dpu
		add_firmware "qcom/gmu_gen70200.bin" # Extra one for gpu
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
