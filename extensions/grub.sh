#!/usr/bin/env bash
# This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the u ser.
function extension_prepare_config__prepare_flash_kernel() {
	# Extension configuration defaults.
	export DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}             # if yes, does not build our own kernel, instead, uses generic one from distro
	export UEFI_GRUB_TERMINAL="${UEFI_GRUB_TERMINAL:-serial console}"     # 'serial' forces grub menu on serial console. empty to not include
	export UEFI_GRUB_DISABLE_OS_PROBER="${UEFI_GRUB_DISABLE_OS_PROBER:-}" # 'true' will disable os-probing, useful for SD cards.
	export UEFI_GRUB_DISTRO_NAME="${UEFI_GRUB_DISTRO_NAME:-Armbian}"      # Will be used on grub menu display
	export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-0}                      # Small timeout by default
	export GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT:-}"   # Cmdline by default
	export UEFI_ENABLE_BIOS_AMD64="${UEFI_ENABLE_BIOS_AMD64:-yes}"        # Enable BIOS too if target is amd64
	export UEFI_EXPORT_KERNEL_INITRD="${UEFI_EXPORT_KERNEL_INITRD:-no}"   # Export kernel and initrd for direct kernel boot "kexec"

	if [[ "${UEFI_GRUB}" != "skip" ]]; then
		# User config overrides for GRUB.
		export BOOTCONFIG="none"                                                     # To try and convince lib/ to not build or install u-boot.
		unset BOOTSOURCE                                                             # To try and convince lib/ to not build or install u-boot.
		export IMAGE_PARTITION_TABLE="gpt"                                           # GPT partition table is essential for many UEFI-like implementations, eg Apple+Intel stuff.
		export UEFISIZE=256                                                          # in MiB - grub EFI is tiny - but some EFI BIOSes ignore small too small EFI partitions
		export BOOTSIZE=0                                                            # No separate /boot when using UEFI.
		export CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}" # use /boot/efi for cloud-init as default when using Grub.
		export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-grub"                               # Unique bsp name.
		export UEFI_GRUB_TARGET_BIOS=""                                              # Target for BIOS GRUB install, set to i386-pc when UEFI_ENABLE_BIOS_AMD64=yes and target is amd64
		local uefi_packages=""                                                       # Use growroot, add some efi-related packages

		uefi_packages="efibootmgr efivar cloud-initramfs-growroot"      # Use growroot, add some efi-related packages
		uefi_packages="os-prober grub-efi-${ARCH}-bin ${uefi_packages}" # This works for Ubuntu and Debian, by sheer luck; common for EFI and BIOS

		# BIOS-compatibility for amd64
		if [[ "${ARCH}" == "amd64" ]]; then
			export UEFI_GRUB_TARGET="x86_64-efi" # Default for x86_64
			if [[ "${UEFI_ENABLE_BIOS_AMD64}" == "yes" ]]; then
				export uefi_packages="${uefi_packages} grub-pc-bin grub-pc"
				export UEFI_GRUB_TARGET_BIOS="i386-pc"
				export BIOSSIZE=4 # 4 MiB BIOS partition
			else
				export uefi_packages="${uefi_packages} grub-efi-${ARCH}"
			fi
		fi

		[[ "${ARCH}" == "arm64" ]] && export uefi_packages="${uefi_packages} grub-efi-${ARCH}"
		[[ "${ARCH}" == "arm64" ]] && export UEFI_GRUB_TARGET="arm64-efi" # Default for arm64-efi
	fi

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
		DISTRO_KERNEL_PACKAGES="linux-image-generic"
		DISTRO_FIRMWARE_PACKAGES="linux-firmware"
	elif [[ "${DISTRIBUTION}" == "Debian" ]]; then
		DISTRO_KERNEL_PACKAGES="linux-image-${ARCH}"
		DISTRO_FIRMWARE_PACKAGES="firmware-linux-free"
		# Debian's prebuilt kernels dont support hvc0, hack.
		if [[ "${SERIALCON}" == "hvc0" ]]; then
			display_alert "Debian's kernels don't support hvc0, changing to ttyS0" "${DISTRIBUTION}" "wrn"
			export SERIALCON="ttyS0"
		fi
	fi

	if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
		export VER="generic"
		unset KERNELSOURCE                 # This should make Armbian skip most stuff. At least, I hacked it to.
		export INSTALL_ARMBIAN_FIRMWARE=no # Should skip build and install of Armbian-firmware.
	else
		export KERNELDIR="linux-uefi-${LINUXFAMILY}" # Avoid sharing a source tree with others, until we know it's safe.
		# Don't install anything. Armbian handles everything.
		DISTRO_KERNEL_PACKAGES=""
		DISTRO_FIRMWARE_PACKAGES=""
	fi

	# @TODO: use actual arrays. Yeah...
	# shellcheck disable=SC2086
	add_packages_to_image ${DISTRO_FIRMWARE_PACKAGES} ${DISTRO_KERNEL_PACKAGES} ${uefi_packages}

	display_alert "${UEFI_GRUB} activating" "GRUB with SERIALCON=${SERIALCON}; timeout ${UEFI_GRUB_TIMEOUT}; BIOS=${UEFI_GRUB_TARGET_BIOS}" ""
}

# @TODO: extract u-boot into an extension, so that core bsps don't have this stuff in there to begin with.
# @TODO: this code is duplicated in flash-kernel.sh extension, so another reason to refactor the root of the evil
post_family_tweaks_bsp__remove_uboot_grub() {
	display_alert "Removing uboot from BSP" "${EXTENSION}" "info"
	# Simply remove everything with 'uboot' or 'u-boot' in their filenames from the BSP package.
	# shellcheck disable=SC2154 # $destination is the target dir of the bsp building function
	pushd "${destination}" || exit_with_error "cray-cray about destination: ${destination}"
	run_host_command_logged find "." -type f "|" grep -e "uboot" -e "u-boot" "|" xargs rm -v
	popd
}

pre_umount_final_image__remove_uboot_initramfs_hook_grub() {
	# even if BSP still contained this (cached .deb), make sure by removing from ${MOUNT}
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && rm -v "$MOUNT"/etc/initramfs/post-update.d/99-uboot
	return 0 # shortcircuit above
}

pre_umount_final_image__install_grub() {
	if [[ "${UEFI_GRUB}" == "skip" ]]; then
		display_alert "Skipping GRUB install" "due to UEFI_GRUB:${UEFI_GRUB}" "debug"
		if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
			display_alert "Skipping GRUB install" "due to UEFI_GRUB:${UEFI_GRUB} - calling update_initramfs directly" "debug"
			VER="generic" update_initramfs "${MOUNT}"
		fi
		return 0
	fi

	configure_grub
	local chroot_target=$MOUNT
	display_alert "Installing bootloader" "GRUB" "info"

	# getting rid of the dtb package, if installed, is hard. for now just zap it, otherwise update-grub goes bananas
	rm -rf "$MOUNT"/boot/dtb* || true

	# add config to disable os-prober, otherwise image will have the host's other OSes boot entries.
	cat <<- grubCfgFragHostSide >> "${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg
		GRUB_DISABLE_OS_PROBER=true
	grubCfgFragHostSide

	# copy Armbian GRUB wallpaper
	mkdir -p "${MOUNT}"/usr/share/images/grub/
	cp "${SRC}"/packages/blobs/splash/grub.png "${MOUNT}"/usr/share/images/grub/wallpaper.png

	if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
		display_alert "Using Distro Generic Kernel" "${EXTENSION}: update_initramfs" "debug"
		VER="generic" update_initramfs "${MOUNT}"
	fi

	# Mount the chroot...
	mount_chroot "$chroot_target/" # this already handles /boot/efi which is required for it to work.

	# update-grub is secretly `grub-mkconfig` under wraps, but the actual work is done by /etc/grub.d/10-linux
	# that decides based on 'test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}"' so that _must_ exist.
	# If it does NOT exist, then a reference to a /dev/devYpX is used, and will fail to boot.
	# Irony: let's use grub-probe to find out the UUID of the root partition, and then create a symlink to it.
	# Another: on some systems (eg, not Docker) the thing might already exist due to udev actually working.
	# shellcheck disable=SC2016 # some wierd escaping going on there.
	chroot_custom "$chroot_target" mkdir -pv '/dev/disk/by-uuid/"$(grub-probe --target=fs_uuid /)"' "||" true

	display_alert "Creating GRUB config..." "grub-mkconfig" ""
	chroot_custom "$chroot_target" update-grub || {
		exit_with_error "update-grub failed!"
	}

	if [[ "${UEFI_GRUB_TARGET_BIOS}" != "" ]]; then
		display_alert "Installing GRUB BIOS..." "${UEFI_GRUB_TARGET_BIOS} device ${LOOP}" ""
		chroot_custom "$chroot_target" grub-install --target=${UEFI_GRUB_TARGET_BIOS} "${LOOP}" || {
			exit_with_error "${install_grub_cmdline} failed!"
		}
	fi

	local install_grub_cmdline="grub-install --target=${UEFI_GRUB_TARGET} --no-nvram --removable" # nvram is global to the host, even across chroot. take care.
	display_alert "Installing GRUB EFI..." "${UEFI_GRUB_TARGET}" ""
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

	umount_chroot "$chroot_target/"

}

pre_umount_final_image__900_export_kernel_and_initramfs() {
	if [[ "${UEFI_EXPORT_KERNEL_INITRD}" == "yes" ]]; then
		display_alert "Exporting Kernel and Initrd for" "kexec" "info"
		# this writes to ${DESTIMG} directly, since debootstrap.sh will move them later.
		# capture the $MOUNT/boot/vmlinuz and initrd and send it out ${DESTIMG}
		run_host_command_logged ls -la "${MOUNT}"/boot/vmlinuz-* "${MOUNT}"/boot/initrd.img-* || true
		run_host_command_logged cp -pv "${MOUNT}"/boot/vmlinuz-* "${DESTIMG}/${version}.kernel"
		run_host_command_logged cp -pv "${MOUNT}"/boot/initrd.img-* "${DESTIMG}/${version}.initrd"
	fi
}

configure_grub() {
	[[ -n "$SERIALCON" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" console=${SERIALCON}"

	[[ "$BOOT_LOGO" == "yes" || "$BOOT_LOGO" == "desktop" && "$BUILD_DESKTOP" == "yes" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" quiet splash plymouth.ignore-serial-consoles i915.force_probe=* loglevel=3" ||
		GRUB_CMDLINE_LINUX_DEFAULT+=" splash=verbose i915.force_probe=*"

	# Enable Armbian Wallpaper on GRUB
	if [[ "${VENDOR}" == Armbian ]]; then
		mkdir -p "${MOUNT}"/usr/share/desktop-base/
		cat <<- grubWallpaper >> "${MOUNT}"/usr/share/desktop-base/grub_background.sh
			WALLPAPER=/usr/share/images/grub/wallpaper.png
			COLOR_NORMAL=white/black
			COLOR_HIGHLIGHT=black/white
		grubWallpaper
	fi

	display_alert "GRUB EFI kernel cmdline" "${GRUB_CMDLINE_LINUX_DEFAULT} distro=${UEFI_GRUB_DISTRO_NAME} timeout=${UEFI_GRUB_TIMEOUT}" ""
	cat <<- grubCfgFrag >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
		GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT}"
		GRUB_TIMEOUT_STYLE=menu                                  # Show the menu with Kernel options (Armbian or -generic)...
		GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT}                        # ... for ${UEFI_GRUB_TIMEOUT} seconds, then boot the Armbian default.
		GRUB_DISTRIBUTOR="${UEFI_GRUB_DISTRO_NAME}"              # On GRUB menu will show up as "Armbian GNU/Linux" (will show up in some UEFI BIOS boot menu (F8?) as "armbian", not on others)
		GRUB_GFXMODE=1024x768
		GRUB_GFXPAYLOAD=keep
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
