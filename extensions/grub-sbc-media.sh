#!/usr/bin/env bash

# @TODO: rpardini: there's no good reason for this ("grub-sbc-media") to exist. "grub" could be refactored to allow configuration to do the same.

# This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
function extension_prepare_config__prepare_grub-sbc-media() {
	display_alert "Prepare config" "${EXTENSION}" "info"
	# Extension configuration defaults.
	declare -g DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}             # if yes, does not build our own kernel, instead, uses generic one from distro
	declare -g UEFI_GRUB_DISABLE_OS_PROBER="${UEFI_GRUB_DISABLE_OS_PROBER:-}" # 'true' will disable os-probing, useful for SD cards.
	declare -g UEFI_GRUB_DISTRO_NAME="${UEFI_GRUB_DISTRO_NAME:-Armbian}"      # Will be used on grub menu display
	declare -g UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3}                      # Small timeout by default
	declare -g UEFI_GRUB_RECORDFAIL_TIMEOUT=${UEFI_GRUB_RECORDFAIL_TIMEOUT:-3}
	declare -g GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT:-}" # Cmdline by default
	declare -g UEFI_ENABLE_BIOS_AMD64="${UEFI_ENABLE_BIOS_AMD64:-no}"       # Enable BIOS too if target is amd64
	# User config overrides.
	declare -g IMAGE_PARTITION_TABLE="gpt"                                           # GPT partition table is essential for many UEFI-like implementations, eg Apple+Intel stuff.
	declare -g UEFISIZE=256                                                          # in MiB - grub EFI is tiny - but some EFI BIOSes ignore small too small EFI partitions
	declare -g BOOTSIZE=0                                                            # No separate /boot when using UEFI.
	declare -g CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}" # use /boot/efi for cloud-init as default when using Grub.
	declare -g EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-grub"                               # Unique bsp name.
	declare -g UEFI_GRUB_TARGET_BIOS=""                                              # Target for BIOS GRUB install, set to i386-pc when UEFI_ENABLE_BIOS_AMD64=yes and target is amd64

	# local
	declare -a packages=()

	packages+=(efibootmgr efivar os-prober "grub-efi-${ARCH}-bin")

	if [[ "${ARCH}" == "arm64" ]]; then
		packages+=("grub-efi-${ARCH}")
		declare -g UEFI_GRUB_TARGET="arm64-efi" # Default for arm64-efi
	fi

	add_packages_to_image "${packages[@]}"
}

pre_umount_final_image__install_grub() {
	configure_grub
	local chroot_target=$MOUNT
	display_alert "Installing bootloader" "GRUB" "info"

	# SBC-MEDIA: copy the dtbs to ESP
	display_alert "Copying DTBs to ESP" "${EXTENSION}" "info"
	run_host_command_logged mkdir -pv "$MOUNT"/boot/efi/dtb
	run_host_command_logged cp -vr "$MOUNT"/boot/dtb/* "$MOUNT"/boot/efi/dtb/
	display_alert "Copying Splash to ESP" "${EXTENSION}" "info"
	run_host_command_logged cp -rv ${SRC}/packages/blobs/splash/grub.png "$MOUNT"/boot/grub

	# add config to disable os-prober, otherwise image will have the host's other OSes boot entries.
	cat <<- grubCfgFragHostSide >> "${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg
		GRUB_DISABLE_OS_PROBER=true
	grubCfgFragHostSide

	# copy Armbian GRUB wallpaper
	run_host_command_logged mkdir -pv "${chroot_target}"/usr/share/images/grub/
	run_host_command_logged cp -v "${SRC}"/packages/blobs/splash/grub.png "${chroot_target}"/usr/share/images/grub/wallpaper.png

	# Mount the chroot...
	mount_chroot "$chroot_target/" # this already handles /boot/efi which is required for it to work.

	# SBC-MEDIA specific...
	sed -i '/devicetree/c echo' "$MOUNT"/etc/grub.d/10_linux

	# update-grub is secretly `grub-mkconfig` under wraps, but the actual work is done by /etc/grub.d/10-linux
	# that decides based on 'test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}"' so that _must_ exist.
	# If it does NOT exist, then a reference to a /dev/devYpX is used, and will fail to boot.
	# Irony: let's use grub-probe to find out the UUID of the root partition, and then create a symlink to it.
	# Another: on some systems (eg, not Docker) the thing might already exist due to udev actually working.
	# shellcheck disable=SC2016 # some wierd escaping going on there.
	chroot_custom "$chroot_target" mkdir -pv '/dev/disk/by-uuid/"$(grub-probe --target=fs_uuid /)"' "||" true

	display_alert "Creating GRUB config..." "${EXTENSION}: grub-mkconfig / update-grub"
	chroot_custom "$chroot_target" update-grub || {
		exit_with_error "update-grub failed!"
	}

	local install_grub_cmdline="grub-install --target=${UEFI_GRUB_TARGET} --no-nvram --removable" # nvram is global to the host, even across chroot. take care.
	display_alert "Installing GRUB EFI..." "${EXTENSION}: ${UEFI_GRUB_TARGET}"
	chroot_custom "$chroot_target" "$install_grub_cmdline" || {
		exit_with_error "${install_grub_cmdline} failed!"
	}

	### Sanity check. The produced "/boot/grub/grub.cfg" should:
	declare -i has_failed_sanity_check=0

	# - NOT have any mention of `/dev` inside; otherwise something is going to fail
	if grep -q '/dev' "${chroot_target}/boot/grub/grub.cfg"; then
		display_alert "GRUB sanity check failed" "grub.cfg contains /dev" "err"
		SHOW_LOG=yes run_host_command_logged grep '/dev' "${chroot_target}/boot/grub/grub.cfg" "||" true
		has_failed_sanity_check=1
	else
		display_alert "GRUB config sanity check passed" "no '/dev' found in grub.cfg" "info"
	fi

	# - HAVE references to initrd, otherwise going to fail.
	if ! grep -q 'initrd.img' "${chroot_target}/boot/grub/grub.cfg"; then
		display_alert "GRUB config sanity check failed" "no initrd.img references found in /boot/grub/grub.cfg" "err"
		has_failed_sanity_check=1
	else
		display_alert "GRUB config sanity check passed" "initrd.img references found OK in /boot/grub/grub.cfg" "debug"
	fi

	if [[ ${has_failed_sanity_check} -gt 0 ]]; then
		exit_with_error "GRUB config sanity check failed, image will be unbootable; see above errors"
	fi

	# Remove host-side config.
	rm -f "${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg

	if [[ $BOARD == jetson-nano ]]; then
		run_host_command_logged cp -v "${SRC}/packages/blobs/jetson/boot.scr" "${MOUNT}"/boot/efi/boot.scr
	fi

	umount_chroot "$chroot_target/"

}

configure_grub() {
	[[ -n "$SRC_CMDLINE" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" ${SRC_CMDLINE}"
	[[ -n "$MAIN_CMDLINE" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" ${MAIN_CMDLINE}"

	display_alert "GRUB EFI kernel cmdline" "${GRUB_CMDLINE_LINUX_DEFAULT} distro=${UEFI_GRUB_DISTRO_NAME} timeout=${UEFI_GRUB_TIMEOUT}" ""
	cat <<- grubCfgFrag >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
		GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT}"
		GRUB_TIMEOUT_STYLE=menu                                  # Show the menu with Kernel options (Armbian or -generic)...
		GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT}                        # ... for ${UEFI_GRUB_TIMEOUT} seconds, then boot the Armbian default.
		GRUB_RECORDFAIL_TIMEOUT=${UEFI_GRUB_RECORDFAIL_TIMEOUT}
		GRUB_DISTRIBUTOR="${UEFI_GRUB_DISTRO_NAME}"              # On GRUB menu will show up as "Armbian GNU/Linux" (will show up in some UEFI BIOS boot menu (F8?) as "armbian", not on others)
		GRUB_BACKGROUND="/boot/grub/grub.png"
	grubCfgFrag

	if [[ "a${UEFI_GRUB_DISABLE_OS_PROBER}" != "a" ]]; then
		cat <<- grubCfgFragHostSide >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_DISABLE_OS_PROBER=${UEFI_GRUB_DISABLE_OS_PROBER}
		grubCfgFragHostSide
	fi

	if [[ "a${UEFI_GRUB_TERMINAL}" != "a" ]]; then
		cat <<- grubCfgFragTerminal >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_TERMINAL="${UEFI_GRUB_TERMINAL}"
		grubCfgFragTerminal
	fi
}
