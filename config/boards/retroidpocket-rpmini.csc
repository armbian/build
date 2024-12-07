# Retroid Pocket RPMini Configuration
declare -g BOARD_NAME="Retroid Pocket RPMini"
declare -g BOARD_MAINTAINER=""
declare -g BOARDFAMILY="sm8250"
declare -g KERNEL_TARGET="current"
declare -g EXTRAWIFI="no"
declare -g MODULES="panel_ddic_ch13726a"
declare -g BOOTCONFIG="none"

declare -g UEFI_GRUB_TERMINAL="gfxterm" # Use graphics in grub, for the Armbian wallpaper.
declare -g GRUB_CMDLINE_LINUX_DEFAULT="clk_ignore_unused pd_ignore_unused arm64.nopauth efi=noruntime fbcon=rotate:1 console=ttyMSM0,115200n8"
declare -g BOOT_FDT_FILE="qcom/sm8250-retroidpocket-rpmini.dtb"

declare -g SERIALCON="${SERIALCON:-tty1}"

enable_extension "grub"
enable_extension "grub-with-dtb" # important, puts the whole DTB handling in place.

# declare -g BOOT_LOGO=desktop

# Use the full firmware, complete linux-firmware plus Armbian's
declare -g BOARD_FIRMWARE_INSTALL="-full"

function retroidpocket-rpmini_is_userspace_supported() {
	[[ "${RELEASE}" == "bookworm" ]] && return 0
	[[ "${RELEASE}" == "jammy" ]] && return 0
	[[ "${RELEASE}" == "noble" ]] && return 0
	[[ "${RELEASE}" == "trixie" ]] && return 0
	return 1
}

function pre_customize_image__retroidpocket-rpmini_alsa_ucm_conf() {
	if ! retroidpocket-rpmini_is_userspace_supported; then
		return 0
	fi

	display_alert "Add alsa-ucm-conf for ${BOARD}" "${RELEASE}" "warn"
	(
		cd "${SDCARD}/usr/share/alsa" || exit 6
		curl -L "https://github.com/RetroidPocket/alsa-ucm-conf/archive/refs/heads/rp/v1.2.13.tar.gz" | tar xvzf - --strip-components=1
	)
}

function post_family_tweaks_bsp__retroidpocket-rpmini_add_services() {
	if ! retroidpocket-rpmini_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	display_alert "$BOARD" "Add services" "info"

	# Bluetooth MAC addr setup service
	mkdir -p $destination/usr/local/bin/
	mkdir -p $destination/usr/lib/systemd/system/
	install -Dm655 $SRC/packages/bsp/generate-bt-mac-addr/bt-fixed-mac.sh $destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/generate-bt-mac-addr/bt-fixed-mac.service $destination/usr/lib/systemd/system/

	# Haptic and Gamepad rules
	install -Dm644 $SRC/packages/bsp/retroidpocket/90-feedbackd-spmi-haptics.rules $destination/etc/udev/rules.d/90-feedbackd-spmi-haptics.rules
	install -Dm644 $SRC/packages/bsp/retroidpocket/99-ignore-gamepad.rules $destination/etc/udev/rules.d/99-ignore-gamepad.rules
}

function post_family_tweaks__retroidpocket-rpmini_enable_services() {
	if ! retroidpocket-rpmini_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	display_alert "$BOARD" "Enable services" "info"

	chroot_sdcard systemctl enable bt-fixed-mac.service
	return 0
}

function post_family_config__retroidpocket-rpmini_extra_packages() {
	if ! retroidpocket-rpmini_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	display_alert "Setting up extra packages for ${BOARD}" "${RELEASE}" "info"
	add_packages_to_image "bluez" "bluetooth"        # for bluetooth stuff
	add_packages_to_image "mtools"                   # for access to the EFI partition
	add_packages_to_image "zstd"                     # for zstd compression of initrd
}

function post_family_tweaks_bsp__retroidpocket-rpmini_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination # will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/retroidpocket-rpmini-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for f in /lib/firmware/qcom/sm8250/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/a650_sqe.fw" # extra one for dpu
		add_firmware "qcom/a650_gmu.bin" # extra one for gpu
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

## Modules, required to boot, add them to initrd
function post_family_tweaks_bsp__retroidpocket-rpmini_bsp_modules_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: modules in initrd" "info"
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/modules" <<- 'EXTRA_MODULES'
		panel-ddic-ch13726a
	EXTRA_MODULES
}

# armbian-firstrun waits for systemd to be ready, but snapd.seeded might cause it to hang due to wrong clock.
# if the battery runs out, the clock is reset to 1970. This causes snapd.seeded to hang, and armbian-firstrun to hang.
function pre_customize_image__disable_snapd_seeded() {
	[[ "${DISTRIBUTION}" != "Ubuntu" ]] && return 0 # only needed for Ubuntu
	display_alert "Disabling snapd.seeded" "${BOARD}" "info"
	chroot_sdcard systemctl disable snapd.seeded.service "||" true
}
