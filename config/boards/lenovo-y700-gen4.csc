# Qualcomm SM8750 12GB/16GB LPDDR5X UFS USB-C WiFi/BT
declare -g BOARD_NAME="Y700 Gen4"
declare -g BOARD_VENDOR="lenovo"
declare -g BOARD_MAINTAINER="retro98boy"
declare -g INTRODUCED="2025"
declare -g BOARDFAMILY="sm8750"
declare -g KERNEL_TARGET="edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"

# Use the full firmware, complete linux-firmware plus Armbian's
declare -g BOARD_FIRMWARE_INSTALL="-full"

# Default boots via the UEFI (Needs UEFI environment support, such as Project Aloha)
# WITH_GRUB=no switches to the Android bootimg path
declare -g WITH_GRUB="${WITH_GRUB:-yes}"

if [[ "${WITH_GRUB}" == "yes" ]]; then
	declare -g UEFI_GRUB_TERMINAL="gfxterm"
	declare -g GRUB_CMDLINE_LINUX_DEFAULT="rootwait quiet video=efifb:off efi=noruntime clk_ignore_unused regulator_ignore_unused pd_ignore_unused"
	declare -g SERIALCON="${SERIALCON:-tty0}"
	declare -g BOOT_FDT_FILE="qcom/sm8750-lenovo-elden.dtb"

	enable_extension "lenovo-y700-gen4-grub-split-image"
else
	declare -g -a ABL_DTB_LIST=("sm8750-lenovo-elden")
	declare -g BOOTIMG_CMDLINE_EXTRA="rootwait rw console=tty0 quiet clk_ignore_unused regulator_ignore_unused pd_ignore_unused"

	function post_family_tweaks_bsp__lenovo-y700-gen4_kernel_postinst() {
		install -Dm755 $SRC/packages/bsp/lenovo-y700-gen4/zz-update-abl-kernel $destination/etc/kernel/postinst.d/
	}
fi

function extension_prepare_config__lenovo_elden_image_suffix() {
	if [[ "${WITH_GRUB}" == "yes" ]]; then
		EXTRA_IMAGE_SUFFIXES+=("-grub")
	else
		EXTRA_IMAGE_SUFFIXES+=("-abl")
	fi
}

function post_family_tweaks_bsp__lenovo-y700-gen4_alsa_ucm_conf() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	local alsa_ucm_src="${SRC}/packages/bsp/lenovo-y700-gen4"
	local alsa_ucm_dir="${destination}/usr/share/alsa/ucm2"
	install -Dm644 "${alsa_ucm_src}/Lenovo-Y700-Gen4.conf" \
		"${alsa_ucm_dir}/Qualcomm/sm8750/Lenovo-Y700-Gen4/Lenovo-Y700-Gen4.conf"
	install -Dm644 "${alsa_ucm_src}/HiFi.conf" \
		"${alsa_ucm_dir}/Qualcomm/sm8750/Lenovo-Y700-Gen4/HiFi.conf"
	mkdir -p "${alsa_ucm_dir}/conf.d/sm8750"
	ln -sfn "../../Qualcomm/sm8750/Lenovo-Y700-Gen4/Lenovo-Y700-Gen4.conf" \
		"${alsa_ucm_dir}/conf.d/sm8750/Lenovo-Y700-Gen4.conf"
}

function post_family_tweaks_bsp__lenovo-y700-gen4_usb_gadget() {
	display_alert "Install firmwares for ${BOARD}" "${RELEASE}" "warn"

	# USB Gadget Network service
	mkdir -p $destination/usr/local/bin/
	mkdir -p $destination/usr/lib/systemd/system/
	mkdir -p $destination/etc/initramfs-tools/scripts/init-bottom/
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/setup-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/remove-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/usb-gadget-network/usbgadget-rndis.service $destination/usr/lib/systemd/system/
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-hook $destination/etc/initramfs-tools/hooks/usb-gadget
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-premount $destination/etc/initramfs-tools/scripts/init-premount/usb-gadget
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/dropbear $destination/etc/initramfs-tools/scripts/init-premount/
	install -Dm755 $SRC/packages/bsp/usb-gadget-network/kill-dropbear $destination/etc/initramfs-tools/scripts/init-bottom/

	return 0
}

function post_family_tweaks__lenovo-y700-gen4_enable_services() {
	# We need unudhcpd from armbian repo, so enable it
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled "${SDCARD}"/etc/apt/sources.list.d/armbian.sources

	do_with_retries 3 chroot_sdcard_apt_get_update
	display_alert "Installing ${BOARD} tweaks" "warn"
	declare -a abl_only_pkgs=()
	if [[ "${WITH_GRUB}" != "yes" ]]; then
		abl_only_pkgs+=(qbootctl mkbootimg)
	fi
	do_with_retries 3 chroot_sdcard_apt_get_install alsa-ucm-conf qrtr-tools unudhcpd "${abl_only_pkgs[@]}"
	# disable armbian repo back
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled
	do_with_retries 3 chroot_sdcard_apt_get_update
	if [[ "${WITH_GRUB}" != "yes" ]]; then
		chroot_sdcard systemctl enable qbootctl.service
	fi

	# Not Any driver support suspend mode
	chroot_sdcard systemctl mask suspend.target

	chroot_sdcard systemctl enable usbgadget-rndis.service

	return 0
}

function post_family_tweaks__lenovo-y700-gen4_mesa_backports() {
	# The Adreno 830 needs a newer Mesa than trixie ships; pull the GL and
	# Vulkan stack from backports, otherwise the desktop falls back to llvmpipe.
	# Only trixie needs this: sid and forky already carry 26.1, and Ubuntu has
	# no backports pocket with a newer Mesa (noble 25.2, resolute 26.0).
	# The Armbian rootfs already lists trixie-backports in debian.sources.
	if [[ "${DISTRIBUTION}" != "Debian" || "${RELEASE}" != "trixie" ]]; then
		display_alert "No Mesa backports path for this release" "${DISTRIBUTION} ${RELEASE}" "warn"
		return 0
	fi
	do_with_retries 3 chroot_sdcard_apt_get -t trixie-backports install libgl1-mesa-dri libegl-mesa0 libgbm1 mesa-vulkan-drivers

	# GMEM workaround for the A830, harmless where it does not apply
	mkdir -p "${SDCARD}"/etc/environment.d
	echo "FD_MESA_DEBUG=sysmem" > "${SDCARD}"/etc/environment.d/50-lenovo-y700-gen4-mesa.conf
}

function post_family_tweaks_bsp__lenovo-y700-gen4_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "warn"
	declare file_added_to_bsp_destination # Will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/lenovo-y700-gen4-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for dir in \
			ath12k/WCN7860/hw2.0/LENOVO/elden \
			qca/LENOVO/elden \
			qcom/sm8750/LENOVO/elden; do
			if [[ ! -d "/lib/firmware/${dir}" ]]; then
				echo "Missing required lenovo-y700-gen4 firmware directory: ${dir}" >&2
				exit 1
			fi
		done
		for f in $(find /lib/firmware/qcom/sm8750 -type f) ; do
		add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/gen80000_gmu.bin" # Extra one for gpu
		add_firmware "qcom/gen80000_sqe.fw" # Extra one for gpu
		add_firmware "qcom/gen80000_aqe.fw" # Extra one for gpu
		add_firmware "qcom/vpu/vpu30_p4.mbn" # Extra one for vpu
		# Extra one for wifi
		for f in $(find /lib/firmware/ath12k/WCN7860/hw2.0 -type f) ; do
		add_firmware "${f#/lib/firmware/}"
		done
		# Extra one for bt
		for f in $(find /lib/firmware/qca -type f) ; do
		add_firmware "${f#/lib/firmware/}"
		done
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}
