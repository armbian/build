# Qualcomm SM8750 octa core 8GB/12GB/16GB RAM SoC eMMC USB-C WiFi/BT
declare -g BOARD_NAME="Ayn Odin3"
declare -g BOARD_VENDOR="ayntec"
declare -g BOARD_MAINTAINER="SuperKali kasimling"
declare -g INTRODUCED="2025"
declare -g BOARDFAMILY="sm8750"
declare -g KERNEL_TARGET="edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"

# Use the full firmware, complete linux-firmware plus Armbian's
declare -g BOARD_FIRMWARE_INSTALL="-full"
declare -g DESKTOP_AUTOLOGIN="yes"

# Check to make sure variants are supported
declare -g VALID_BOARDS=("ayn-odin3")

if [[ ! " ${VALID_BOARDS[*]} " =~ " ${BOARD} " ]]; then
	exit_with_error "Error: Invalid board '$BOARD'. Valid options are: ${VALID_BOARDS[*]}" >&2
fi

# Default boots via the stock ABL UEFI (GRUB on an ESP, nothing gets flashed);
# WITH_GRUB=no switches to the Android bootimg path over the ROCKNIX ABL.
declare -g WITH_GRUB="${WITH_GRUB:-yes}"

if [[ "${WITH_GRUB}" == "yes" ]]; then
	declare -g UEFI_GRUB_TERMINAL="gfxterm"
	declare -g GRUB_CMDLINE_LINUX_DEFAULT="rootwait quiet video=efifb:off console=tty0 irqaffinity=0-1 cgroup.memory=nokmem,nosocket nosoftlockup arm64.nopauth efi=noruntime fbcon=rotate:1"
	declare -g BOOT_FDT_FILE="qcom/cq8725s-${BOARD}.dtb"
	declare -g SERIALCON="${SERIALCON:-tty0}"

	enable_extension "grub"
	enable_extension "grub-with-dtb"
else
	declare -g BOOTFS_TYPE="fat"
	declare -g BOOTSIZE="512"
	declare -g IMAGE_PARTITION_TABLE="msdos"
	declare -g BOOTIMG_CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused rw quiet rootwait"

	function extension_prepare_config__ayn_odin3_image_suffix() {
		EXTRA_IMAGE_SUFFIXES+=("-abl")
	}

	function pre_umount_final_image__update_ABL_settings() {
		display_alert "Update ABL settings for " "${BOARD}" "info"
		uuid_line=$(head -n 1 "${SDCARD}"/etc/fstab)
		rootfs_image_uuid=$(echo "${uuid_line}" | awk '{print $1}' | awk -F '=' '{print $2}')
		[[ -n "$rootfs_image_uuid" ]] || exit_with_error "Could not determine rootfs UUID"
		initrd_name=$(find "${SDCARD}/boot/" -type f -name "config-*" | sed 's/.*config-//')

		cp /usr/bin/mkbootimg /tmp/mkbootimg
		sed -i 's/from gki.generate_gki_certificate import generate_gki_certificate/# &/' /tmp/mkbootimg
		chmod +x /tmp/mkbootimg

		gzip -c "${MOUNT}"/boot/Image > /tmp/Image.gz
		cat /tmp/Image.gz "${MOUNT}"/boot/dtb/qcom/cq8725s-ayn-odin3.dtb > /tmp/Image.gz-dtb
		/tmp/mkbootimg  \
			--kernel /tmp/Image.gz-dtb  \
			--ramdisk "${MOUNT}"/boot/initrd.img-${initrd_name}  \
			--base 0x0  \
			--second_offset 0x00f00000  \
			--cmdline "clk_ignore_unused pd_ignore_unused console=tty0 ignore_loglevel rw rootwait root=UUID=${rootfs_image_uuid}"  \
			--kernel_offset 0x10008000          \
			--ramdisk_offset 0x16000000         \
			--tags_offset 0x10000100         \
			--pagesize 2048   -o "${MOUNT}"/boot/KERNEL
		rm /tmp/Image.gz /tmp/Image.gz-dtb /tmp/mkbootimg
	}

	function post_create_partitions__change_bootpart_type() {
		display_alert "Setting boot partition type to Win95 on" "${SDCARD}.raw" "info"

		# Needed for Android to mount this partition
		run_host_command_logged parted "${SDCARD}".raw type 1 0xb
	}

	function post_family_tweaks_bsp__ayn_odin3_abl_kernel_postinst() {
		# Kernel postinst script to update abl boot partition
		install -Dm755 $SRC/packages/bsp/ayn-odin3/zz-update-abl-kernel $destination/etc/kernel/postinst.d/
	}
fi

function pre_customize_image__ayn-odin3_alsa_ucm_conf() {
	# Vendored AYN SM8750 UCM with the Class-AB headphone bring-up and the
	# entrypoint for the UEFI card name; stock codec sequences come from the
	# distro alsa-ucm-conf package.
	display_alert "Install alsa-ucm for ${BOARD}" "vendored AYN SM8750 UCM" "info"
	cp -a "${SRC}/packages/bsp/${BOARD}/usr/share/alsa/." "${SDCARD}"/usr/share/alsa/
}

function post_family_tweaks_bsp__ayn-odin3_firmware() {
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

function post_family_tweaks__ayn-odin3_enable_services() {
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

	# Add Gamepad udev rule
	echo 'SUBSYSTEM=="input", ATTRS{name}=="AYN Odin3 Gamepad", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"' > "${SDCARD}"/etc/udev/rules.d/99-ignore-gamepad.rules
	# Not Any driver support suspend mode
	chroot_sdcard systemctl mask suspend.target

	chroot_sdcard systemctl enable usbgadget-rndis.service
	if [[ "${WITH_GRUB}" != "yes" ]]; then
		cp -a "${SRC}/packages/bsp/${BOARD}/rocknix_abl" "${SDCARD}"/boot/
	fi

	return 0
}

function post_family_tweaks__ayn-odin3_mesa_backports() {
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
	echo "FD_MESA_DEBUG=sysmem" > "${SDCARD}"/etc/environment.d/50-odin3-mesa.conf
}

function post_family_tweaks_bsp__ayn-odin3_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "warn"
	declare file_added_to_bsp_destination # Will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/ayn-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
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
